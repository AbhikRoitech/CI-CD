# Learn RDS — concepts before the code

A plain-English guide to Amazon RDS so the Terraform in this folder makes sense.
Read this first, then read `01-terraform-files-guide.md`.

---

## 1. What RDS actually is

**RDS (Relational Database Service)** is AWS running a database *for* you. You pick
an engine (PostgreSQL here) and an instance size; AWS installs it, patches the OS,
takes backups, and can fail over to a standby if the server dies. You do **not** get
SSH into the box — you only get a connection **endpoint** (a hostname + port).

You still own: your data, your schema, your users/passwords, your security rules,
and choosing the right size and settings. That's what this Terraform manages.

```
Your app  ──(hostname:5432, TLS)──►  RDS endpoint  ──►  PostgreSQL managed by AWS
```

---

## 2. The pieces that surround an RDS instance

An RDS instance never lives alone. In production it sits inside a small web of
supporting resources. Understanding these is 80% of understanding the Terraform:

| Piece | What it is | Why prod needs it |
|-------|-----------|-------------------|
| **VPC** | Your private network in AWS | The DB should live in *your* isolated network, not the shared default VPC |
| **Private subnets** | IP ranges with **no route to the internet** | A production DB must NOT be publicly reachable |
| **DB subnet group** | The set of subnets RDS may place the instance/standby in | RDS requires ≥2 subnets in different AZs to support Multi-AZ |
| **Security group** | A stateful firewall | Restricts who can reach port 5432 — only your app, not the world |
| **Parameter group** | Engine config knobs (like `postgresql.conf`) | Enforce settings such as "require TLS" |
| **KMS key** | Encryption key | Encrypts storage, backups, and snapshots at rest |
| **Secrets Manager secret** | Stores the master password | Keeps the password out of code and state |
| **IAM monitoring role** | Lets RDS push OS metrics to CloudWatch | Enables Enhanced Monitoring |

---

## 3. Availability Zones and Multi-AZ (the big prod difference)

A **Region** (e.g. `ap-south-1`, Mumbai) is split into **Availability Zones** (AZs) —
physically separate data centers.

- **Single-AZ** (dev): one instance in one AZ. If that AZ has an outage, your DB is down.
- **Multi-AZ** (prod): AWS keeps a **synchronous standby** in a *second* AZ. If the
  primary fails, RDS automatically flips the endpoint to the standby, usually in
  60–120 seconds. **You don't change your connection string** — the endpoint stays the same.

Multi-AZ roughly **doubles the cost** (you pay for the standby) but is the single most
important production setting. This is why a DB subnet group needs subnets in ≥2 AZs.

> Multi-AZ standby is for **failover**, not for read scaling. To scale reads you add
> separate **read replicas** (out of scope here).

---

## 4. Storage

- **Type:** `gp3` is the modern default (better price/performance than `gp2`; IOPS and
  throughput are configurable independently of size).
- **Allocated storage:** how much you start with (GB).
- **Storage autoscaling:** set a `max_allocated_storage` higher than allocated and RDS
  grows the disk automatically when it fills up — so you never get a "disk full" outage.
- **Encryption at rest:** turned on with a KMS key. Must be enabled **at creation** —
  you cannot encrypt an existing unencrypted instance in place.

---

## 5. Backups & recovery

- **Automated backups:** RDS snapshots daily and keeps transaction logs, giving you
  **Point-In-Time Recovery (PITR)** — restore to any second within the retention window.
  Controlled by `backup_retention_period` (days). Prod: 14–35. Dev: often 1 or 0.
- **Backup window:** the daily time slot for the snapshot (UTC).
- **Final snapshot:** when you *delete* an instance, RDS can take one last snapshot.
  `skip_final_snapshot = true` means **no snapshot → data is gone forever**. Prod = `false`.
- **Deletion protection:** `true` blocks accidental deletes; you must turn it off first.

---

## 6. Security (defense in depth)

Production databases layer several defenses:

1. **Network isolation** — private subnets + `publicly_accessible = false`. The DB has
   no public IP; nothing on the internet can even reach it.
2. **Security group** — only the application's security group is allowed in on 5432.
3. **Encryption in transit** — force TLS via a parameter group (`rds.force_ssl = 1`).
4. **Encryption at rest** — KMS-encrypted storage, backups, and snapshots.
5. **Credentials** — master password managed by Secrets Manager, never written in
   plaintext into `.tf` files or state.

Contrast with the dev setup in `../Terraform_RDS/`, which is `publicly_accessible = true`
with `0.0.0.0/0` open — fine for a throwaway learning box, unacceptable for prod.

---

## 7. Monitoring & observability

- **Enhanced Monitoring** — OS-level metrics (CPU, memory, disk) at up to 1-second
  granularity, delivered via an IAM role. Plain CloudWatch metrics are coarser.
- **Performance Insights** — a dashboard showing which SQL queries and waits are
  loading the DB. Extremely useful for diagnosing slow prod databases.
- **CloudWatch Logs exports** — ship `postgresql` and `upgrade` logs to CloudWatch so
  you can search and alarm on them.

---

## 8. Cost — the honest part

RDS bills **for as long as the instance exists**, whether or not anything is connected.
Rough on-demand cost drivers, largest first:

1. **Instance class** (biggest lever) — bigger = more $/hr.
2. **Multi-AZ** — roughly ×2 the instance cost.
3. **Storage** — per GB/month, plus provisioned IOPS on gp3 if you raise them.
4. **Backups** — free up to your allocated storage size, then per GB.
5. **Data transfer** out of AWS.

> ⚠️ This account is **not free-tier eligible** (see `../Terraform_RDS/CLAUDE.md`).
> A Multi-AZ prod instance will cost meaningfully more than the ~$21/mo single-AZ dev box.
> To pay $0, `terraform destroy` when you're done learning.

---

## 9. Terraform mental model (how the code maps to this)

Terraform describes the **desired state** of all the pieces above in `.tf` files, then:

```
terraform init      # download the AWS provider plugin (required after clone)
terraform plan      # show what it WILL create/change/destroy — read this every time
terraform apply     # make AWS match the files
terraform destroy   # tear it all down
```

Terraform records what it built in a **state file**. In production, that state lives in
a shared **S3 backend** (with locking) so a team doesn't clobber each other — not a
local file. The next doc walks each `.tf` file in this folder one by one.
