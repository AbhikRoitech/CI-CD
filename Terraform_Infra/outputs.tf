output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet IDs grouped by tier — later steps consume these (route tables, ALB,
# EC2 placement, Aurora subnet group).
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [for k, s in aws_subnet.this : s.id if startswith(k, "public")]
}

output "app_subnet_ids" {
  description = "IDs of the private app subnets"
  value       = [for k, s in aws_subnet.this : s.id if startswith(k, "app")]
}

output "db_subnet_ids" {
  description = "IDs of the private db subnets"
  value       = [for k, s in aws_subnet.this : s.id if startswith(k, "db")]
}
