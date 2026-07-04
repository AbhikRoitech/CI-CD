# terraform-rds — project context

A learning/dev Terraform project that provisions a single **AWS RDS PostgreSQL**
instance + a security group. Purpose: learning Terraform + RDS.

> Read this first. You usually do NOT need to re-read every `.tf` file — the
> essentials are summarized here. Open the actual files only when editing them
> or when a detail below is missing.

## AWS context
- Account: `786174827428` (IAM user `AbhikIAM`)
- Region: `ap-south-1` (Mumbai)
- **Account is NOT free-tier eligible** — this DB costs real money (see Cost).

## Files
| File | Purpose |
|------|---------|
| `versions.tf` | TF `>= 1.5.0`, AWS provider `~> 5.0`, provider region from `var.aws_region` |
| `variables.tf` | All input variables (with defaults) |
| `terraform.tfvars` | Actual values used for this deployment |
| `main.tf` | `aws_security_group.db` + `aws_db_instance.postgres` |
| `outputs.tf` | endpoint, port, database_name, username, security_group_id |
| `terraform.tfstate` | State — **contains the DB password in plaintext** |

## Current deployment (as of 2026-07-03)
- Status: **deployed & `available`**
- Identifier: `learning-rds-dev`
- Endpoint: `learning-rds-dev.cl4wyoi28bez.ap-south-1.rds.amazonaws.com:5432`
- Engine: PostgreSQL **16.14** | Class: `db.t3.micro` | Storage: 20 GB gp2 (encrypted)
- DB name: `devdb` | Master user: `postgres`
- `publicly_accessible = true`, SG ingress on 5432 from `allowed_cidr_blocks`

## Cost (non-free-tier, on-demand)
- ~**$0.0296/hr** → ~**$0.71/day** → ~**$21.60/mo** if left running 24×7.
- Billed whenever the instance EXISTS (not just when connected).
- Stopped ≠ free (still pay ~$2.62/mo storage; auto-restarts after 7 days).
- To pay $0: `terraform destroy`.

## Common commands
```bash
cd /mnt/c/terraform/terraform-rds
terraform init      # REQUIRED after fresh clone/machine — provider plugin isn't cached
terraform plan
terraform apply
terraform destroy   # clean teardown (skip_final_snapshot=true, deletion_protection=false)
```
Quick live check without TF: `aws rds describe-db-instances --region ap-south-1`

## Known issues / gotchas
- `terraform` CLI currently errors until `terraform init` is run (AWS provider
  plugin `5.x` not cached in `.terraform/`). State itself is intact.
- **Security:** `allowed_cidr_blocks` may be `0.0.0.0/0` (world-open on 5432).
  Recommend locking to `<your-ip>/32` (`curl -s ifconfig.me`).
- Password lives in plaintext in both `terraform.tfvars` and `terraform.tfstate`.
  Better: `export TF_VAR_db_password=...` and gitignore tfvars/tfstate.
- Don't mix manual AWS CLI changes with this Terraform state → causes drift.
</content>
