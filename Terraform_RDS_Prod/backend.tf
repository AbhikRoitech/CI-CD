# ── Remote state backend (production) ───────────────────────────────────────────
# In production the state file must NOT live on your laptop. It goes in an S3
# bucket (encrypted, versioned) with a DynamoDB table for state locking so two
# people can't apply at the same time.
#
# The S3 bucket + DynamoDB table must already exist BEFORE you run this. Create
# them once (by hand or a separate tiny Terraform project), then uncomment the
# block below and run `terraform init` — Terraform will migrate state into S3.
#
# Left commented so this folder still works with local state while you're learning.

# terraform {
#   backend "s3" {
#     bucket         = "your-tf-state-bucket-name"   # must be globally unique, pre-created
#     key            = "rds/prod/terraform.tfstate"  # path within the bucket
#     region         = "ap-south-1"
#     dynamodb_table = "your-tf-lock-table"          # pre-created, primary key "LockID"
#     encrypt        = true
#   }
# }
