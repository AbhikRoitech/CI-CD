# =============================================================================
# Step 3 — Security groups (least privilege, chained)
#
# Mirrors Step 3 of notesMD/secure-vpc-deployment.md. The whole point: the only
# CIDR-based inbound in the system is at the ALB. Everything behind it accepts
# traffic ONLY from the SG in front of it:
#
#   internet --(80,443)--> sg-alb --(80)--> sg-ec2 --(5432)--> sg-aurora
#                                    sg-ec2 --(443)--> sg-vpce   (for SSM, Step 5)
#
# These reference each other in one direction only (no cycles). Using standalone
# rule resources (provider v5 style) instead of inline ingress/egress blocks.
# =============================================================================

# ----- sg-alb : public entry point (the ONLY place with 0.0.0.0/0 inbound) -----
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-sg-alb"
  description = "ALB: allow HTTP/HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet (redirects to 443 at the listener)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "All outbound (ALB forwards to targets)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ----- sg-ec2 : the private app instance(s); only the ALB may reach it -----
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-sg-ec2"
  description = "App EC2: allow port 80 only from the ALB SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-sg-ec2"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "HTTP from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

# Egress open so the box can pull images / dnf / git via the NAT gateway.
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All outbound (image pulls, updates, Aurora, SSM via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ----- sg-aurora : the DB; only the app instances may reach 5432 -----
resource "aws_security_group" "aurora" {
  name        = "${var.project}-${var.environment}-sg-aurora"
  description = "Aurora: allow 5432 only from the EC2 app SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-sg-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_ec2" {
  security_group_id            = aws_security_group.aurora.id
  description                  = "PostgreSQL from the app EC2 only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_vpc_security_group_egress_rule" "aurora_all" {
  security_group_id = aws_security_group.aurora.id
  description       = "All outbound (Aurora doesn't initiate, but keep default)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ----- sg-vpce : SSM interface VPC endpoints; only the app instances may reach it
# Provisioned ahead of Step 5. Harmless/free until endpoints are attached to it.
resource "aws_security_group" "vpce" {
  name        = "${var.project}-${var.environment}-sg-vpce"
  description = "VPC endpoints (SSM): allow 443 from the EC2 app SG"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-sg-vpce"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ec2" {
  security_group_id            = aws_security_group.vpce.id
  description                  = "HTTPS from the app EC2 only (SSM endpoints)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_vpc_security_group_egress_rule" "vpce_all" {
  security_group_id = aws_security_group.vpce.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
