# ── DB parameter group: engine configuration (like postgresql.conf) ─────────────
# The main prod hardening here is forcing TLS so no client can connect in plaintext.
resource "aws_db_parameter_group" "this" {
  name        = "${var.project}-${var.environment}-pg"
  family      = var.parameter_group_family
  description = "Parameter group for ${var.project}-${var.environment}"

  # Reject any non-SSL connection at the server.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log statements that take longer than 1s — useful for spotting slow queries.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-${var.environment}-pg" }
}
