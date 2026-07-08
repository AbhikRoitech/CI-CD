# ── The production RDS PostgreSQL instance ──────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier = "${var.project}-${var.environment}"

  # Engine
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage (gp3, encrypted with our CMK, autoscaling enabled)
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  # Database + credentials.
  # manage_master_user_password = true tells RDS to generate the master password
  # and store it in Secrets Manager. The password never appears in .tf or state.
  db_name                       = var.db_name
  username                      = var.db_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.rds.key_id
  port                          = var.db_port

  # Networking — private subnets, DB security group, NOT publicly accessible.
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # Engine configuration (forces TLS).
  parameter_group_name = aws_db_parameter_group.this.name

  # Backups & maintenance (enables Point-In-Time Recovery).
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # Monitoring & logging.
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = var.performance_insights_retention
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  # Upgrades — allow automatic minor patches during the maintenance window.
  auto_minor_version_upgrade = true
  apply_immediately          = false # prod changes wait for the maintenance window

  # Safety on delete.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.environment}-final"

  tags = { Name = "${var.project}-${var.environment}" }
}
