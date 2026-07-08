# ── Dedicated VPC for the database tier ─────────────────────────────────────────
# Production databases live in their own private network, not the shared default VPC.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-${var.environment}-vpc" }
}

# Look up the AZs available in this region so we can spread subnets across them.
data "aws_availability_zones" "available" {
  state = "available"
}

# ── Private subnets (no route to the internet) ──────────────────────────────────
# One per CIDR, each in a different AZ. Multi-AZ RDS requires >= 2 AZs.
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # No public IPs — this is a private data tier.
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-${var.environment}-private-${count.index + 1}" }
}

# ── DB subnet group: the set of subnets RDS may place the primary/standby in ─────
resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.environment}-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.project}-${var.environment}-subnet-group" }
}

# ── Application security group ───────────────────────────────────────────────────
# Represents your application tier (EC2/ECS/Lambda). Attach this SG to those
# resources; the DB only accepts connections from members of this SG.
resource "aws_security_group" "app" {
  name        = "${var.project}-${var.environment}-app-sg"
  description = "Application tier; allowed to reach the database"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-app-sg" }
}

# ── Database security group ──────────────────────────────────────────────────────
# Ingress on the DB port ONLY from the app SG (and any optional extra CIDRs).
# There is no 0.0.0.0/0 rule anywhere.
resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "Database tier; only reachable from the app SG"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.project}-${var.environment}-db-sg" }
}

resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  description              = "Postgres from application security group"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "db_from_extra_cidrs" {
  count             = length(var.app_ingress_cidrs) > 0 ? 1 : 0
  type              = "ingress"
  description       = "Postgres from extra allowed CIDRs (e.g. VPN)"
  from_port         = var.db_port
  to_port           = var.db_port
  protocol          = "tcp"
  security_group_id = aws_security_group.db.id
  cidr_blocks       = var.app_ingress_cidrs
}

resource "aws_security_group_rule" "db_egress" {
  type              = "egress"
  description       = "All outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.db.id
  cidr_blocks       = ["0.0.0.0/0"]
}
