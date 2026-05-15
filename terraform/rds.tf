###############################################################################
# CloudCorp — RDS MySQL (Multi-AZ)
#
# Structured customer data lives here: accounts, transactions, app state.
# Multi-AZ provides automatic failover within ~60-120 seconds on primary
# failure or AZ-level incident, and enables zero-downtime patching (AWS
# patches the standby first, then fails over).
#
# The instance sits in the private data subnets — no default route to the
# internet, reachable only from the EC2 security group on port 3306.
#
# Demo vs production differences (documented in the report):
#   - Demo runs db.t3.micro Single-AZ and 1-day backup retention (free tier)
#   - Production spec: db.t3.small, Multi-AZ, 14-day backup retention
###############################################################################


#####
##### --- DB Subnet Group ---
#####
# Spans both private data subnets (AZ-1a and AZ-1b).
# Required for Multi-AZ — AWS needs subnets in at least two AZs.

resource "aws_db_subnet_group" "cloudcorp" {
  name        = "cloudcorp-db-subnetgroup"
  description = "Private data subnets for RDS"

  subnet_ids = [
    aws_subnet.private_data_1a.id,
    aws_subnet.private_data_1b.id,
  ]

  tags = {
    Name = "CloudCorp-DB-SubnetGroup"
  }
}


#####
##### --- RDS Instance ---
#####

resource "aws_db_instance" "cloudcorp" {
  identifier = "cloudcorp-db"

  # Engine
  engine         = "mysql"
  engine_version = "8.0"

  # Demo: db.t3.micro to stay within free tier limits.
  # Production spec: db.t3.small Multi-AZ.
  instance_class = "db.t3.micro"

  # Storage
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.stockholm.arn

  # Credentials
  db_name  = "cloudcorp"
  username = "cloudcorp_admin"
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.cloudcorp.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Demo: Single-AZ due to free tier. Production spec: multi_az = true.
  multi_az = false

  # Backups — free tier allows max 1 day retention.
  # Production spec: 14 days.
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Upgrades and protection
  auto_minor_version_upgrade = true
  deletion_protection        = false

  # Snapshots — set to true for easy destroy in demo/dev environments.
  # Production should use false with a proper final_snapshot_identifier.
  skip_final_snapshot = true

  tags = {
    Name = "cloudcorp-db"
  }
}
