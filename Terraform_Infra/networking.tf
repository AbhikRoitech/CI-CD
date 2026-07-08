# =============================================================================
# Step 2 — Internet Gateway, NAT Gateway, route tables
#
# Mirrors Step 2 of notesMD/secure-vpc-deployment.md:
#   - IGW attached to the VPC (public egress/ingress).
#   - ONE NAT Gateway in public-a (+ Elastic IP) for private-app egress.
#     One NAT is the cheapest option; for full HA you'd run one per AZ.
#   - rt-public : 0.0.0.0/0 -> IGW   (public-a, public-b)
#     rt-app    : 0.0.0.0/0 -> NAT   (app-a, app-b)
#     rt-db     : local only, NO internet route (db-a, db-b) — deliberate.
#
# COST STARTS HERE: the NAT Gateway is ~$0.045/hr (~$32+/mo in ap-south-1) plus
# data processing, and the Elastic IP is billable while attached. Run
# `terraform destroy` (or just remove this file's NAT/EIP) when you stop testing.
# =============================================================================

locals {
  # Subnet keys grouped by tier — drives the route-table associations below.
  public_subnet_keys = [for k, v in local.subnets : k if v.tier == "public"]
  app_subnet_keys    = [for k, v in local.subnets : k if v.tier == "app"]
  db_subnet_keys     = [for k, v in local.subnets : k if v.tier == "db"]
}

# ----- Internet Gateway -----
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# ----- NAT Gateway (single, in the first public subnet) -----
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.environment}-nat-eip"
  }

  # EIP has nothing to attach to until the IGW exists.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this[local.public_subnet_keys[0]].id # public-a

  tags = {
    Name = "${var.project}-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ----- Public route table: default route to the IGW -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = toset(local.public_subnet_keys)

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ----- App route table: default route to the NAT (egress only) -----
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-app"
  }
}

resource "aws_route_table_association" "app" {
  for_each = toset(local.app_subnet_keys)

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app.id
}

# ----- DB route table: LOCAL ONLY, no 0.0.0.0/0 route -----
# Associating the db subnets with their own table keeps them off the VPC's main
# route table and guarantees they never get an internet route by accident.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-rt-db"
  }
}

resource "aws_route_table_association" "db" {
  for_each = toset(local.db_subnet_keys)

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.db.id
}
