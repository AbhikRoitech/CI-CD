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

# ----- Step 2: gateways -----
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "nat_public_ip" {
  description = "Elastic IP of the NAT Gateway (the egress IP for private app subnets)"
  value       = aws_eip.nat.public_ip
}

# ----- Step 3: security groups -----
output "sg_alb_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "sg_ec2_id" {
  description = "Security group ID for the app EC2 instances"
  value       = aws_security_group.ec2.id
}

output "sg_aurora_id" {
  description = "Security group ID for Aurora"
  value       = aws_security_group.aurora.id
}

output "sg_vpce_id" {
  description = "Security group ID for the SSM VPC endpoints"
  value       = aws_security_group.vpce.id
}
