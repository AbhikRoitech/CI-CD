output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.postgres.endpoint
}

output "address" {
  description = "Hostname only (use as DB_HOST)."
  value       = aws_db_instance.postgres.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Initial database name."
  value       = aws_db_instance.postgres.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the generated master password. Fetch with the AWS CLI or SDK."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "db_security_group_id" {
  description = "Security group protecting the database."
  value       = aws_security_group.db.id
}

output "app_security_group_id" {
  description = "Attach this SG to your app (EC2/ECS/Lambda) so it can reach the DB."
  value       = aws_security_group.app.id
}

output "vpc_id" {
  description = "ID of the dedicated VPC."
  value       = aws_vpc.this.id
}
