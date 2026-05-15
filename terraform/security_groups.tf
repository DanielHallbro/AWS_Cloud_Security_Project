###############################################################################
# CloudCorp — Security Groups
#
# Resource creation and rules are separated into two blocks to avoid circular
# dependencies. All three SGs are created empty first, then rules are added
# as separate resources that reference the already-created SG IDs.
#
# Chain:
#   Internet → [CloudFront prefix list] → ALB-SG → EC2-SG → RDS-SG
#
# SG-to-SG references are used for internal hops rather than IP ranges,
# so rules remain stable as instances scale in and out.
###############################################################################


#####
##### --- Step 1: Create all SGs empty ---
#####
# No ingress/egress blocks here — rules are added below as separate resources.

resource "aws_security_group" "alb" {
  provider = aws.stockholm

  name        = "CloudCorp-SG-ALB"
  description = "Load Balancer Security Group"
  vpc_id      = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-SG-ALB"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ec2" {
  provider = aws.stockholm

  name        = "CloudCorp-SG-EC2"
  description = "EC2 Security Group"
  vpc_id      = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-SG-EC2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  provider = aws.stockholm

  name        = "CloudCorp-SG-RDS"
  description = "RDS Security Group"
  vpc_id      = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-SG-RDS"
  }

  lifecycle {
    create_before_destroy = true
  }
}


#####
##### --- Step 2: ALB Security Group rules ---
#####

# Inbound: HTTPS (443) from CloudFront managed prefix list.
# pl-fab65393 = com.amazonaws.global.cloudfront.origin-facing
# Forces all traffic through CloudFront/WAF — direct ALB access is blocked.
resource "aws_vpc_security_group_ingress_rule" "alb_inbound_https" {
  provider = aws.stockholm

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from CloudFront managed prefix list"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = "pl-fab65393"
}

# Outbound: HTTPS (443) to EC2-SG only.
# ALB only communicates with EC2 — no other outbound traffic needed.
resource "aws_vpc_security_group_egress_rule" "alb_outbound_to_ec2" {
  provider = aws.stockholm

  security_group_id            = aws_security_group.alb.id
  description                  = "HTTPS to EC2"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ec2.id
}


#####
##### --- Step 3: EC2 Security Group rules ---
#####

# Inbound: HTTPS (443) from ALB-SG only.
# EC2 accepts traffic from ALB only — no SSH, no direct internet access.
resource "aws_vpc_security_group_ingress_rule" "ec2_inbound_from_alb" {
  provider = aws.stockholm

  security_group_id            = aws_security_group.ec2.id
  description                  = "HTTPS from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.alb.id
}

# Outbound: HTTPS (443) to internet.
# Required for SSM Session Manager, CloudWatch Agent, and OS updates.
# EC2 initiates these connections outbound — no inbound rules needed for SSM.
resource "aws_vpc_security_group_egress_rule" "ec2_outbound_https" {
  provider = aws.stockholm

  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS out for SSM, CloudWatch, OS updates"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound: MySQL (3306) to RDS-SG.
# EC2 initiates database connections — RDS never initiates.
resource "aws_vpc_security_group_egress_rule" "ec2_outbound_to_rds" {
  provider = aws.stockholm

  security_group_id            = aws_security_group.ec2.id
  description                  = "MySQL to RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.rds.id
}


#####
##### --- Step 4: RDS Security Group rules ---
#####

# Inbound: MySQL (3306) from EC2-SG only.
# Only EC2 can reach the database — nothing else.
resource "aws_vpc_security_group_ingress_rule" "rds_inbound_from_ec2" {
  provider = aws.stockholm

  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EC2"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ec2.id
}

# Outbound: no rules.
# RDS does not initiate any outbound connections.
