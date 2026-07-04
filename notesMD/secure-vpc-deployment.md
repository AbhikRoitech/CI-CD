# Secure VPC Deployment — Private-Subnet EC2

Deploy this microservices stack (client + gateway + auth-service + todo-service)
onto an EC2 host that lives in a **private subnet** — no public IP, no direct
inbound from the internet — fronted by an Application Load Balancer, talking to
Aurora PostgreSQL in isolated DB subnets.

This replaces the current "public EC2 with port 80 open to the world + SSH by
public IP" model (see [EC2-AL2023-SETUP.md](../EC2-AL2023-SETUP.md)). The app
itself doesn't change — only where it runs and how traffic reaches it.

---

## Why the app forces these choices

| App fact (from the code) | Consequence for the VPC design |
|---|---|
| Only the **client** container publishes port 80; gateway + services are internal to the Docker network | The instance only needs **one** inbound port (80), and only from the load balancer — never from the internet directly. |
| Services connect **out** to Aurora over TLS (`DB_SSL=true`), and the box must `docker pull` / `dnf` / `git pull` | A private instance has no internet route by default → needs a **NAT gateway** for egress. |
| CI currently SSHes into the EC2 **public IP** to deploy | A private instance has **no public IP** → SSH-by-IP breaks. Deploy/admin must go through **SSM Session Manager** (or a bastion). |
| auth-service & todo-service share a `JWT_SECRET`, no service-to-service calls | Nothing extra at the network layer — internal Docker DNS still handles it. |

---

## Target architecture

```
                          Internet
                             │
                    ┌────────▼─────────┐
                    │ Internet Gateway │
                    └────────┬─────────┘
        VPC 10.0.0.0/16      │
   ┌─────────────────────────┼──────────────────────────┐
   │  PUBLIC subnets (2 AZs)  │                           │
   │   ┌───────────────┐   ┌──▼───────────────┐          │
   │   │  NAT Gateway  │   │  Application LB   │◄── users │
   │   └───────┬───────┘   │  :443 / :80       │          │
   │           │           └────────┬──────────┘          │
   ├───────────┼────────────────────┼─────────────────────┤
   │  PRIVATE app subnets (2 AZs)    │  (target: EC2:80)   │
   │           │           ┌─────────▼──────────┐          │
   │  egress ──┘           │  EC2 (no public IP)│          │
   │  (pull images,        │  Docker stack:     │          │
   │   git, dnf)           │  client→gateway→   │          │
   │                       │  auth/todo svc     │          │
   │                       └─────────┬──────────┘          │
   ├─────────────────────────────────┼─────────────────────┤
   │  PRIVATE db subnets (2 AZs)      │ (5432, TLS)         │
   │                       ┌──────────▼─────────┐           │
   │                       │  Aurora PostgreSQL │           │
   │                       │  (devdb)           │           │
   │                       └────────────────────┘           │
   └───────────────────────────────────────────────────────┘

Admin/deploy access: AWS SSM Session Manager (no inbound SSH, no bastion)
Traffic path:  user → ALB (public) → EC2 client:80 (private) → gateway → services → Aurora
```

Three subnet tiers, each spread over **two Availability Zones** (required for the
ALB and for an Aurora subnet group):

- **Public** — only the ALB and the NAT gateway. Has a route to the Internet Gateway.
- **Private app** — the EC2 instance(s). Egress via NAT; no inbound from internet.
- **Private db** — Aurora only. No internet route at all.

---

## Prerequisites

- AWS account with permissions for VPC, EC2, ELB, RDS/Aurora, IAM, SSM, ACM.
- AWS CLI configured locally (`aws configure`) in your region (`ap-south-1`).
- A domain name (optional but recommended, for HTTPS via ACM).
- The app's images pushed to Docker Hub (`abhik98/cicd-*`) **or** built on the box
  — either works; building needs NAT egress, pulling needs it too.

> The steps use the AWS Console language but note the key CLI calls. For anything
> you'll recreate often, capture it as Terraform/CloudFormation later — this note
> is the manual "understand it once" path.

---

## Step 1 — Create the VPC and subnets

1. **VPC**: CIDR `10.0.0.0/16`. Enable **DNS hostnames** and **DNS resolution**
   (required for Aurora endpoints and SSM).
2. Create **6 subnets** across two AZs (`ap-south-1a`, `ap-south-1b`):

   | Name | AZ | CIDR | Tier |
   |---|---|---|---|
   | public-a | ap-south-1a | 10.0.0.0/24 | public |
   | public-b | ap-south-1b | 10.0.1.0/24 | public |
   | app-a | ap-south-1a | 10.0.10.0/24 | private app |
   | app-b | ap-south-1b | 10.0.11.0/24 | private app |
   | db-a | ap-south-1a | 10.0.20.0/24 | private db |
   | db-b | ap-south-1b | 10.0.21.0/24 | private db |

3. On the **public** subnets only, enable "auto-assign public IPv4". Leave it
   **off** for app and db subnets.

---

## Step 2 — Internet Gateway, NAT Gateway, route tables

1. **Internet Gateway (IGW)** — create and attach to the VPC.
2. **NAT Gateway** — create in `public-a`, allocate an Elastic IP for it.
   (One NAT is cheapest; for full HA create one per AZ.)
3. **Route tables**:
   - `rt-public` → default route `0.0.0.0/0` → **IGW**. Associate `public-a`, `public-b`.
   - `rt-app` → default route `0.0.0.0/0` → **NAT Gateway**. Associate `app-a`, `app-b`.
   - `rt-db` → **no** `0.0.0.0/0` route (local only). Associate `db-a`, `db-b`.

> The db tier having no internet route is deliberate — Aurora never needs egress,
> and this makes exfiltration meaningfully harder.

---

## Step 3 — Security groups (least privilege, chained)

Create four SGs. Each references the previous one as its source — this is the
core of the security model: **no CIDR-based inbound except at the ALB.**

| SG | Inbound | Source | Purpose |
|---|---|---|---|
| `sg-alb` | 443, 80 | `0.0.0.0/0` | public entry point |
| `sg-ec2` | 80 | **`sg-alb`** | only the ALB can reach the app |
| `sg-aurora` | 5432 | **`sg-ec2`** | only the app can reach the DB |
| `sg-vpce` (optional) | 443 | **`sg-ec2`** | SSM VPC endpoints (see Step 5) |

Outbound: leave default (all) on `sg-ec2` so it can pull via NAT; you can tighten
later. **Do not** open 22 (SSH) or 5432 to `0.0.0.0/0` anywhere.

---

## Step 4 — Aurora in the private db subnets

1. **DB subnet group** — include `db-a` and `db-b`.
2. Create/modify the Aurora PostgreSQL cluster:
   - **Subnet group**: the one above.
   - **Public access**: **No**.
   - **Security group**: `sg-aurora`.
   - Keep **TLS required** — the app already sets `DB_SSL=true` and
     `ssl.rejectUnauthorized=false` in each `db.js`, so no code change.
3. Note the **writer endpoint** — it goes into each service's `.env` as `DB_HOST`.
   The `devdb` database must exist on the cluster (create it once via a client
   from inside the VPC, e.g. through the SSM session in Step 6).

> If your Aurora cluster already exists elsewhere, either move it into this VPC's
> db subnet group or set up VPC peering — the instance must resolve and reach the
> writer endpoint on 5432 through `sg-aurora`.

---

## Step 5 — IAM role + SSM (how you get into a box with no public IP)

Instead of SSH + bastion, use **SSM Session Manager** — the instance opens an
*outbound* connection to SSM; you never open an inbound port.

1. Create an **IAM role** for EC2 with the managed policy
   `AmazonSSMManagedInstanceCore`. (Add ECR/S3 policies only if you need them.)
2. Attach this role as the instance profile in Step 6.
3. SSM reaches the instance one of two ways — pick one:
   - **Via NAT** (simplest): the SSM agent talks out through the NAT gateway. Works
     with the setup above, no extra resources.
   - **Via VPC endpoints** (most locked-down): create interface endpoints for
     `ssm`, `ssmmessages`, `ec2messages` in the app subnets, SG `sg-vpce`. Lets you
     administer even with **no** NAT/internet egress at all.

AL2023 ships the SSM agent preinstalled — no bootstrap needed.

---

## Step 6 — Launch the EC2 instance (private, no public IP)

1. AMI: **Amazon Linux 2023**. Type: `t3.small`+ (the 4-container build is memory-hungry).
2. **Network**: VPC above, subnet `app-a`, **Auto-assign public IP = Disable**.
3. **Security group**: `sg-ec2`.
4. **IAM instance profile**: the SSM role from Step 5.
5. Launch. There is intentionally **no key pair needed** for access (SSM handles it),
   but you may attach one for break-glass.

Connect:
```bash
aws ssm start-session --target i-0123456789abcdef0 --region ap-south-1
# lands you as ssm-user; then: sudo su - ec2-user
```

Now follow the software install from the existing guide — Docker, Docker Compose,
git — Steps 4–6 of [EC2-AL2023-SETUP.md](../EC2-AL2023-SETUP.md). **Skip the host
Postgres section entirely** (Step 7 & 10 there) — you're using Aurora.

Then create the two `.env` files (Step 9 of that guide), but with Aurora values:
```
PORT=5002                       # 5001 for todo-service
DB_USER=<aurora-user>
DB_PASS=<aurora-pass>
DB_HOST=<aurora-writer-endpoint>
DB_PORT=5432
DB_NAME=devdb
DB_SSL=true
JWT_SECRET=<same-value-in-both-files>
```

Deploy the stack:
```bash
cd ~/CI-CD
docker compose -f docker-compose.prod.yml up --build -d
curl http://localhost        # SPA should return HTML from inside the box
```

---

## Step 7 — Application Load Balancer (the public front door)

1. **Target group** `tg-client`: target type *Instances*, protocol **HTTP**, port
   **80**, VPC above. Register the EC2 instance. Health check path `/`
   (the SPA) — or `/api/health` if you route it through.
2. **Application Load Balancer** `alb-todo`:
   - Scheme **internet-facing**, subnets `public-a` + `public-b`, SG `sg-alb`.
   - **Listener :443** → forward to `tg-client`, with an **ACM certificate** for
     your domain (request/import it in ACM first, same region).
   - **Listener :80** → redirect to 443.
3. Point your domain's DNS (Route 53 `A`/ALIAS record) at the ALB.

Result: `https://yourdomain.com` → ALB → EC2 `client:80` → gateway → services.
The instance is never addressable from the internet directly.

> TLS terminates at the ALB. Traffic ALB→EC2 is plain HTTP inside the private
> subnet — acceptable for most setups; enable end-to-end TLS later if required.

---

## Step 8 — Fix CI/CD for a private instance

The current [deploy-dev.yml](../.github/workflows/deploy-dev.yml) SSHes into
`EC2_HOST` (a public IP). That won't work anymore. Replace SSH with an **SSM
Send-Command** driven by short-lived AWS credentials (OIDC — no stored keys):

```yaml
# .github/workflows/deploy-dev.yml (sketch)
permissions:
  id-token: write        # for OIDC
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<acct>:role/github-deploy   # OIDC trust
          aws-region: ap-south-1
      - name: Deploy via SSM
        run: |
          aws ssm send-command \
            --instance-ids ${{ secrets.EC2_INSTANCE_ID }} \
            --document-name AWS-RunShellScript \
            --comment "deploy dev" \
            --parameters commands='[
              "set -e",
              "cd /home/ec2-user/CI-CD",
              "git checkout dev && git pull origin dev",
              "docker compose -f docker-compose.prod.yml up --build -d --remove-orphans",
              "docker image prune -f"
            ]' \
            --output text
```

Set up an IAM OIDC identity provider for GitHub and a `github-deploy` role scoped
to `ssm:SendCommand` on that instance. This removes the long-lived `EC2_SSH_KEY`
secret entirely.

Alternatives if you'd rather not use SSM for CI:
- **Self-hosted GitHub runner** on the private instance (it polls out to GitHub — no inbound needed).
- **Bastion host** in a public subnet + SSH agent-forwarding (least preferred — reintroduces an SSH surface).

---

## Security checklist

- [ ] EC2 has **no public IP** and lives in a private (app) subnet.
- [ ] `sg-ec2` inbound is **only** port 80 from `sg-alb` — no `0.0.0.0/0`, no SSH.
- [ ] `sg-aurora` inbound is **only** 5432 from `sg-ec2`.
- [ ] Aurora **public access = No**, TLS required, in the private db subnet group.
- [ ] Admin access via **SSM only**; no key pair exposed, no bastion unless justified.
- [ ] db subnet route table has **no** `0.0.0.0/0` route.
- [ ] ALB terminates **HTTPS** (ACM cert); :80 redirects to :443.
- [ ] CI uses **OIDC + SSM**, not a stored SSH key.
- [ ] `.env` files live only on the instance (via SSM session), never in git.
- [ ] NAT gateway EIP is the only egress; consider VPC endpoints to drop NAT.
- [ ] VPC Flow Logs enabled; CloudWatch alarms on the ALB 5xx / target health.

---

## Cost note (ap-south-1, rough)

The private-subnet pieces add ongoing cost over a bare public EC2:
- **NAT Gateway**: ~$0.05/hr + data processing (~$32+/mo). Biggest add-on. Drop it
  by using VPC endpoints for SSM/ECR if the box needs no other egress.
- **ALB**: ~$0.025/hr + LCUs (~$18+/mo).
- **Aurora**, EC2, EIP: as before.

For a pure learning exercise where cost matters more than isolation, a single
public EC2 (the existing guide) is fine. This note is the pattern you'd actually
ship to production.
