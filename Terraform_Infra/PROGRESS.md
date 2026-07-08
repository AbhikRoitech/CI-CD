# Terraform_Infra — Build Progress

Incremental Terraform build of the secure private-subnet architecture described
in [../notesMD/secure-vpc-deployment.md](../notesMD/secure-vpc-deployment.md).
Region **ap-south-1**, account **786174827428 (AbhikIAM)**, environment **dev**.

Legend:  ✅ built & tested   🔨 in progress   ⬜ not started yet

---

## Architecture — what exists vs what's left

```
                                Internet
                                   │
                          ┌────────▼─────────┐
                          │ Internet Gateway │  ✅ igw
                          └────────┬─────────┘
      VPC 10.0.0.0/16   ✅         │
 ┌─────────────────────────────────┼───────────────────────────────────┐
 │  PUBLIC subnets (2 AZs)  ✅      │                                    │
 │   10.0.0.0/24 / 10.0.1.0/24      │                                    │
 │   ┌───────────────┐   ┌──────────▼──────────┐                        │
 │   │  NAT Gateway  │✅ │  Application LB      │⬜  ◄── users           │
 │   │  + EIP        │   │  :443 / :80          │  (Step 3 of plan)      │
 │   └───────┬───────┘   └──────────┬───────────┘                       │
 ├───────────┼──────────────────────┼──────────────────────────────────┤
 │  PRIVATE app subnets (2 AZs) ✅   │  target: EC2:80                   │
 │  10.0.10.0/24 / 10.0.11.0/24      │                                   │
 │           │           ┌──────────▼──────────┐                        │
 │  egress ──┘ (via NAT) │  EC2 (no public IP) │⬜  (Step 2 of plan)    │
 │                       │  Docker stack       │    + IAM/SSM role ⬜    │
 │                       │  client→gateway→svc │    (Step 6 of plan)     │
 │                       └──────────┬──────────┘                        │
 ├──────────────────────────────────┼──────────────────────────────────┤
 │  PRIVATE db subnets (2 AZs) ✅    │  5432, TLS                        │
 │  10.0.20.0/24 / 10.0.21.0/24      │  (NO internet route ✅)           │
 │                       ┌──────────▼──────────┐                        │
 │                       │  Aurora PostgreSQL  │⬜  (Step 4 of plan)     │
 │                       │  (devdb)            │    + Secrets Mgr ⬜     │
 │                       └─────────────────────┘    (Step 5 of plan)    │
 └───────────────────────────────────────────────────────────────────┘

 Security groups (chained, least-privilege) ✅ built:
   internet ─(80,443)→ sg-alb ─(80)→ sg-ec2 ─(5432)→ sg-aurora
                                       sg-ec2 ─(443)→ sg-vpce (for SSM)

 Later: SSM Session Manager ⬜ (Step 6) · EKS migration ⬜ (Step 7)
```

---

## Status by step

| # | Step (your plan) | Terraform | Status | Cost impact |
|---|------------------|-----------|--------|-------------|
| 1 | VPC + public/private subnets | `vpc.tf` | ✅ built & tested | Free |
| 2 | IGW + NAT + route tables | `networking.tf` | ✅ built & tested | **NAT ~$32/mo + EIP** |
| 2b | Chained security groups | `security-groups.tf` | ✅ built & tested | Free |
| — | Private EC2 + IAM/SSM role | *(next)* | ⬜ not started | EC2 ~$15/mo (t3.small) |
| — | Application Load Balancer | *(pending)* | ⬜ not started | **ALB ~$18/mo** |
| 4 | Migrate to Aurora PostgreSQL | *(pending)* | ⬜ not started | Aurora usage-based |
| 5 | Secrets → AWS Secrets Manager | *(pending)* | ⬜ not started | ~$0.40/secret/mo |
| 6 | SSM Session Manager (drop SSH) | *(pending)* | ⬜ not started | Free (via NAT) |
| 7 | Containerize → Amazon EKS | *(pending)* | ⬜ not started | **EKS ~$73/mo + nodes** |

> Ordering note: your 7-point plan puts EC2/ALB before Aurora; the design note
> lists Aurora first. We are following your plan order (EC2 → ALB → Aurora).

---

## What is actually deployed right now (Steps 1–2b)

**Networking**
- 1× VPC `10.0.0.0/16` (DNS hostnames + resolution ON — needed for Aurora & SSM)
- 6× subnets across `ap-south-1a` / `ap-south-1b`:
  - public-a `10.0.0.0/24`, public-b `10.0.1.0/24`  (auto-assign public IP ON)
  - app-a `10.0.10.0/24`, app-b `10.0.11.0/24`       (private)
  - db-a `10.0.20.0/24`, db-b `10.0.21.0/24`          (private, no internet route)
- 1× Internet Gateway
- 1× NAT Gateway + 1× Elastic IP (in public-a)
- 3× route tables: `rt-public`→IGW, `rt-app`→NAT, `rt-db`→local-only

**Security groups (chained by SG reference, not CIDR)**
- `sg-alb`   — inbound 80,443 from `0.0.0.0/0`
- `sg-ec2`   — inbound 80 from `sg-alb`
- `sg-aurora`— inbound 5432 from `sg-ec2`
- `sg-vpce`  — inbound 443 from `sg-ec2` (provisioned early for SSM endpoints)

Nothing opens SSH (22) or exposes 5432 to the internet.

---

## What remains

| Piece | Why it's needed | Notes |
|-------|-----------------|-------|
| **IAM role + instance profile** | EC2 needs `AmazonSSMManagedInstanceCore` so we can reach it without SSH | Free |
| **EC2 instance (private)** | Runs the Docker stack (client→gateway→auth/todo) | No public IP; subnet app-a; SG `sg-ec2` |
| **Application Load Balancer** | Public front door; TLS termination; only path in from internet | ALB + target group + listeners (80→443 redirect, 443→forward) |
| **ACM certificate** | HTTPS on the ALB | Needs a domain (optional; can start HTTP-only) |
| **Aurora PostgreSQL cluster** | Replace the standalone `Terraform_RDS` instance; lives in db subnets | DB subnet group (db-a, db-b), public access = No, SG `sg-aurora` |
| **AWS Secrets Manager** | Move DB creds + `JWT_SECRET` out of `.env` files | App/CI reads secrets at deploy time |
| **SSM VPC endpoints** (optional) | Admin the box with zero internet egress | Interface endpoints for ssm/ssmmessages/ec2messages, SG `sg-vpce` |
| **CI/CD rewrite** | Current workflow SSHes a public IP — breaks for a private box | OIDC + `ssm send-command` (no stored SSH key) |
| **EKS cluster** | Final step: containers on Kubernetes, same network design | Reuses this VPC/subnets |

---

## Files in this module

| File | Contains |
|------|----------|
| `versions.tf` | Terraform + AWS provider versions; provider `default_tags` |
| `variables.tf` | region, environment, project, vpc_cidr, azs, tags |
| `terraform.tfvars` | actual dev values |
| `vpc.tf` | VPC + 6 subnets (Step 1) |
| `networking.tf` | IGW, NAT, EIP, route tables (Step 2) |
| `security-groups.tf` | sg-alb / sg-ec2 / sg-aurora / sg-vpce (Step 2b) |
| `outputs.tf` | vpc id, subnet ids by tier, gateway ids, SG ids |
| `.gitignore` | keeps state (future secrets) out of git |

---

## Commands

```bash
cd Terraform_Infra
terraform init          # first time / after adding providers
terraform plan          # preview changes
terraform apply         # build (review, then: yes)
terraform output        # show vpc id, subnet ids, SG ids, NAT IP
terraform destroy       # tear everything down (stops the NAT/ALB meter)
```

## Cost reminder

Free: VPC, subnets, IGW, route tables, security groups.
**Billing while they exist:** NAT Gateway (~$0.045/hr) + EIP, and later the ALB
(~$0.025/hr), EC2, Aurora, and EKS. Run `terraform destroy` when you pause.
