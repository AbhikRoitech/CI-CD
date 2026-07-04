# =============================================================================
# Step 1 — VPC and subnets (3 tiers x 2 AZs = 6 subnets)
#
# Mirrors the table in notesMD/secure-vpc-deployment.md (Step 1):
#   public : ALB + NAT        (will get an IGW route later)
#   app    : private EC2      (egress via NAT later; no inbound from internet)
#   db     : Aurora only      (no internet route at all)
#
# No IGW / NAT / route tables yet — those come in Step 2. This step just carves
# out the address space so you can verify the layout before adding routing.
# =============================================================================

locals {
  # Explicit subnet map, keyed by name, so the plan reads like the design table.
  # tier drives later behaviour (public IPs, which route table, which SGs).
  subnets = {
    "public-a" = { cidr = "10.0.0.0/24", az = var.azs[0], tier = "public" }
    "public-b" = { cidr = "10.0.1.0/24", az = var.azs[1], tier = "public" }
    "app-a"    = { cidr = "10.0.10.0/24", az = var.azs[0], tier = "app" }
    "app-b"    = { cidr = "10.0.11.0/24", az = var.azs[1], tier = "app" }
    "db-a"     = { cidr = "10.0.20.0/24", az = var.azs[0], tier = "db" }
    "db-b"     = { cidr = "10.0.21.0/24", az = var.azs[1], tier = "db" }
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for Aurora endpoint resolution and SSM (both used in later steps).
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # Only public subnets auto-assign a public IP; app/db stay private.
  map_public_ip_on_launch = each.value.tier == "public"

  tags = {
    Name = "${var.project}-${var.environment}-${each.key}"
    Tier = each.value.tier
  }
}
