# ── Customer-managed KMS key for encryption at rest ─────────────────────────────
# Prod uses a customer-managed key (CMK) rather than the AWS-owned default key, so
# you control rotation and access policy. Encrypts storage, backups, and snapshots.
resource "aws_kms_key" "rds" {
  description             = "${var.project}-${var.environment} RDS encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${var.project}-${var.environment}-rds-kms" }
}

# A friendly alias so the key is easy to find in the console.
resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}
