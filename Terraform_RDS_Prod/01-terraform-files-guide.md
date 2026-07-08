# Terraform files guide — what each file does and why

This walks every file in `Terraform_RDS_Prod/` in the order Terraform effectively
builds them. Read `00-learn-rds.md` first for the concepts. Terraform doesn't care
about file names or order — it reads all `.tf` files together and figures out
dependencies from references — so the split below is purely for **human** clarity.

---

## The files at a glance

| File | Role | Creates |
|------|------|---------|
| `versions.tf` | Pin Terraform & provider versions | (nothing — settings only) |
| `backend.tf` | Where the state file lives (S3, for teams) | (nothing — settings only) |
| `providers.tf` | Configure the AWS provider + default tags | (nothing — settings only) |
| `variables.tf` | Declare all inputs and their defaults | (nothing — inputs only) |
| `network.tf` | The private network the DB sits in | VPC, subnets, subnet group, security groups |
| `kms.tf` | Encryption key | KMS key + alias |
| `parameter_group.tf` | Engine config (force TLS) | DB parameter group |
| `monitoring.tf` | Permission for Enhanced Monitoring | IAM role + policy attachment |
| `rds.tf` | **The database itself** | `aws_db_instance` |
| `outputs.tf` | Values printed after apply | (nothing — reads results) |
| `terraform.tfvars.example` | Template for your real values | (nothing — copy to `terraform.tfvars`) |

---

## 1. `versions.tf` — pin the toolchain
Declares the minimum Terraform version (`>= 1.5.0`) and the AWS provider
(`~> 5.0`, meaning any 5.x). **Why it matters:** everyone and every CI run uses the
same provider behavior, so `apply` is reproducible instead of silently changing when
a new provider version ships.

## 2. `backend.tf` — where state is stored
State is Terraform's record of what it built. By default it's a local file
(`terraform.tfstate`) — fine for solo learning, **wrong for a team** because two
people would overwrite each other and the file contains secrets.

This file contains a **commented** S3 backend block. In real prod you:
1. Pre-create an S3 bucket (versioned, encrypted) + a DynamoDB lock table.
2. Uncomment the block, fill in the names, run `terraform init`.
3. Terraform moves state into S3; DynamoDB provides a lock so only one `apply` runs at a time.

Left commented so the folder works locally while you learn.

## 3. `providers.tf` — configure AWS
Sets the region and, importantly, `default_tags` — tags (`Project`, `Environment`,
`ManagedBy`) automatically stamped on every resource. **Why it matters:** consistent
tags make cost reports and cleanup possible ("show me everything for prod").

## 4. `variables.tf` — the knobs
Declares every input with a `type`, `description`, and a **prod-safe default**. This
is the file you skim to understand what's tunable: instance size, storage, Multi-AZ,
backup retention, etc. Notice there is **no `db_password`** — see `rds.tf` for why.
You override defaults in `terraform.tfvars` (copy from the `.example`).

## 5. `network.tf` — the private home for the DB
The biggest prod difference from a dev box. Builds, in dependency order:

1. **`aws_vpc.this`** — a dedicated private network (`10.20.0.0/16`).
2. **`data.aws_availability_zones`** — looks up which AZs exist in the region.
3. **`aws_subnet.private[*]`** — one private subnet per CIDR, each in a different AZ,
   with `map_public_ip_on_launch = false`. Two AZs is what makes Multi-AZ possible.
4. **`aws_db_subnet_group.this`** — tells RDS "you may place the primary/standby in
   these subnets."
5. **`aws_security_group.app`** — represents your application servers. You attach this
   to your EC2/ECS/Lambda later.
6. **`aws_security_group.db`** + rules — the DB firewall. The key rule
   (`db_from_app`) allows port 5432 **only from the app SG** — not from any IP range.
   There is deliberately **no `0.0.0.0/0`** ingress anywhere.

**Why it matters:** the database has no public IP and can only be reached by things
you explicitly put in the app security group. This is the core of prod DB security.

## 6. `kms.tf` — the encryption key
A **customer-managed** KMS key (with automatic rotation) plus a friendly alias. The
RDS instance references this key to encrypt storage, backups, snapshots, and the
Performance Insights data. **Why it matters:** you own the key and its access policy,
rather than relying on the shared AWS-owned default key. Encryption must be set at
creation — you can't retrofit it.

## 7. `parameter_group.tf` — engine settings
The RDS equivalent of editing `postgresql.conf`. Two settings here:
- `rds.force_ssl = 1` — the server **rejects any non-TLS connection**.
- `log_min_duration_statement = 1000` — log queries slower than 1 second.

`create_before_destroy` avoids downtime if the group is ever replaced. **Why it
matters:** enforces encryption-in-transit at the server, not just by client convention.

## 8. `monitoring.tf` — permission to emit OS metrics
Enhanced Monitoring needs an IAM role that RDS can assume to push CPU/memory/disk
metrics to CloudWatch. This file defines that role and attaches AWS's managed
`AmazonRDSEnhancedMonitoringRole` policy. It's conditional (`count`) — created only
when `monitoring_interval > 0`, so setting the interval to 0 cleanly removes it.

## 9. `rds.tf` — the database itself
The centerpiece — one `aws_db_instance` that references everything above. Highlights:

- **Storage:** `gp3`, `storage_encrypted = true`, `kms_key_id` → the CMK, plus
  `max_allocated_storage` for autoscaling.
- **Credentials:** `manage_master_user_password = true` — **RDS generates the master
  password and stores it in Secrets Manager.** This is why `variables.tf` has no
  password: it never touches your files or state. You read it from Secrets Manager
  when needed (the ARN is an output).
- **Networking:** `db_subnet_group_name`, `vpc_security_group_ids` → the DB SG,
  `publicly_accessible = false`, `multi_az = true`.
- **Config:** `parameter_group_name` → the force-SSL group.
- **Backups:** `backup_retention_period` (PITR), backup + maintenance windows,
  `copy_tags_to_snapshot`.
- **Observability:** Enhanced Monitoring role, Performance Insights (encrypted),
  CloudWatch log exports.
- **Safety:** `deletion_protection = true`, `skip_final_snapshot = false` with a
  `final_snapshot_identifier`, and `apply_immediately = false` so changes land in the
  maintenance window instead of causing surprise restarts.

## 10. `outputs.tf` — what you get back
After `apply`, prints the endpoint/address/port, the DB name, the **Secrets Manager
ARN** for the password, the two security group IDs, and the VPC ID. These are the
values you feed into your application (and the app SG id you attach to your servers).

## 11. `terraform.tfvars.example` — your values
A template. Copy it to `terraform.tfvars` and edit. Note it has **no password**
(managed by Secrets Manager). `terraform.tfvars` should be gitignored.

---

## How to run it

```bash
cd Terraform_RDS_Prod
cp terraform.tfvars.example terraform.tfvars   # edit if you want non-defaults

terraform init      # download the AWS provider (required after clone)
terraform plan      # READ THIS — shows everything that will be created
terraform apply     # build it (VPC + DB + supporting resources; ~10-15 min for the DB)
```

Fetch the generated master password after apply:
```bash
# get the secret ARN
terraform output -raw master_user_secret_arn
# then read the password (JSON with username/password)
aws secretsmanager get-secret-value --region ap-south-1 --secret-id <THAT_ARN> --query SecretString --output text
```

Tear everything down (you must disable deletion protection first):
```bash
terraform apply -var deletion_protection=false
terraform destroy
```

---

## Order of creation (dependency graph)

Terraform derives this automatically from references; shown so you can picture it:

```
KMS key ─────────────────────────────┐
VPC ──► subnets ──► subnet group ─────┤
        └────────► security groups ───┤──► aws_db_instance (rds.tf)
parameter group ──────────────────────┤
IAM monitoring role ──────────────────┘
```

Everything on the left is a prerequisite the DB points at. Change a variable, run
`terraform plan`, and Terraform shows exactly which of these it will add, change, or
replace before you commit with `apply`.

---

## Prod vs the dev setup in `../Terraform_RDS/`

| Aspect | dev (`Terraform_RDS`) | prod (this folder) |
|--------|----------------------|--------------------|
| Network | default VPC | dedicated VPC, private subnets |
| Public access | `true` | `false` |
| Ingress | `0.0.0.0/0` | app security group only |
| Multi-AZ | `false` | `true` |
| Password | plaintext in tfvars/state | Secrets Manager (generated) |
| Encryption key | default AWS key | customer-managed KMS key |
| TLS | not enforced | forced (`rds.force_ssl`) |
| Deletion protection | `false` | `true` |
| Final snapshot | skipped | taken |
| Monitoring | none | Enhanced Monitoring + Performance Insights + log exports |
| State | local file | S3 + DynamoDB lock |
| Cost | ~$21/mo | higher (Multi-AZ ×2, bigger class, PI) |
