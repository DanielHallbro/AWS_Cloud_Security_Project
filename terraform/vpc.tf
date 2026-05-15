###############################################################################
# CloudCorp — VPC, subnets, routing, and S3 Gateway Endpoint
#
# Matches the ClickOps build documented in CloudCorp_Report.pdf:
#   - 1 VPC: 10.0.0.0/16
#   - 6 subnets (3 per AZ): public, private-app, private-data
#   - 1 Internet Gateway
#   - 2 NAT Gateways (one per AZ — avoids SPoF and cross-AZ traffic charges)
#   - 5 route tables (1 shared public, 2 private-app per AZ, 2 private-data per AZ)
#   - S3 Gateway Endpoint attached to private-app route tables ONLY
#     (deliberate security decision — public route table is excluded)
###############################################################################


#####
##### --- VPC ---
#####

resource "aws_vpc" "cloudcorp" {
  provider = aws.stockholm

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "CloudCorp-VPC"
  }
}


#####
##### --- Subnets: public (AZ-1a, AZ-1b) ---
#####

resource "aws_subnet" "public_1a" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1a"

  # Auto-assign public IPv4 deliberately disabled — ALB and NAT Gateway
  # receive their own public IPs at creation time; nothing else should live here.
  map_public_ip_on_launch = false

  tags = {
    Name = "AZ-1a-public"
  }
}

resource "aws_subnet" "public_1b" {
  provider = aws.stockholm

  vpc_id                  = aws_vpc.cloudcorp.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "eu-north-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "AZ-1b-public"
  }
}


#####
##### --- Subnets: private app layer (AZ-1a, AZ-1b) ---
#####

resource "aws_subnet" "private_app_1a" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "AZ-1a-private-app"
  }
}

resource "aws_subnet" "private_app_1b" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "eu-north-1b"

  tags = {
    Name = "AZ-1b-private-app"
  }
}


#####
##### --- Subnets: private data layer (AZ-1a, AZ-1b) ---
#####

resource "aws_subnet" "private_data_1a" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "AZ-1a-private-data"
  }
}

resource "aws_subnet" "private_data_1b" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "eu-north-1b"

  tags = {
    Name = "AZ-1b-private-data"
  }
}


#####
##### --- Internet Gateway ---
#####

resource "aws_internet_gateway" "cloudcorp" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-IGW"
  }
}


#####
##### --- Elastic IPs for NAT Gateways ---
#####
# depends_on IGW — best practice: IGW must be attached before EIPs
# are allocated to a NAT Gateway in the same VPC.

resource "aws_eip" "nat_1a" {
  provider = aws.stockholm

  domain     = "vpc"
  depends_on = [aws_internet_gateway.cloudcorp]

  tags = {
    Name = "CloudCorp-NAT-EIP-1a"
  }
}

resource "aws_eip" "nat_1b" {
  provider = aws.stockholm

  domain     = "vpc"
  depends_on = [aws_internet_gateway.cloudcorp]

  tags = {
    Name = "CloudCorp-NAT-EIP-1b"
  }
}


#####
##### --- NAT Gateways (one per AZ) ---
#####
# Two NAT Gateways instead of one shared — avoids SPoF and cross-AZ
# traffic charges. Each private-app subnet routes through the NAT
# Gateway in its own AZ.

resource "aws_nat_gateway" "nat_1a" {
  provider = aws.stockholm

  allocation_id = aws_eip.nat_1a.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "CloudCorp-NAT-1a"
  }

  depends_on = [aws_internet_gateway.cloudcorp]
}

resource "aws_nat_gateway" "nat_1b" {
  provider = aws.stockholm

  allocation_id = aws_eip.nat_1b.id
  subnet_id     = aws_subnet.public_1b.id

  tags = {
    Name = "CloudCorp-NAT-1b"
  }

  depends_on = [aws_internet_gateway.cloudcorp]
}


#####
##### --- Route table: public subnets (shared between AZ-1a and AZ-1b) ---
#####

resource "aws_route_table" "public" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudcorp.id
  }

  tags = {
    Name = "CloudCorp-RT-public"
  }
}

resource "aws_route_table_association" "public_1a" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}


#####
##### --- Route tables: private-app (one per AZ) ---
#####
# Each private-app subnet routes 0.0.0.0/0 through the NAT Gateway in
# its own AZ — avoids cross-AZ traffic and maintains AZ fault isolation.

resource "aws_route_table" "private_app_1a" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1a.id
  }

  tags = {
    Name = "CloudCorp-RT-private-app-1a"
  }
}

resource "aws_route_table_association" "private_app_1a" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.private_app_1a.id
  route_table_id = aws_route_table.private_app_1a.id
}

resource "aws_route_table" "private_app_1b" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1b.id
  }

  tags = {
    Name = "CloudCorp-RT-private-app-1b"
  }
}

resource "aws_route_table_association" "private_app_1b" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.private_app_1b.id
  route_table_id = aws_route_table.private_app_1b.id
}


#####
##### --- Route tables: private-data (one per AZ) ---
#####
# No default routes — local only. RDS does not need and must not have
# any outbound internet path.

resource "aws_route_table" "private_data_1a" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-RT-private-data-1a"
  }
}

resource "aws_route_table_association" "private_data_1a" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.private_data_1a.id
  route_table_id = aws_route_table.private_data_1a.id
}

resource "aws_route_table" "private_data_1b" {
  provider = aws.stockholm

  vpc_id = aws_vpc.cloudcorp.id

  tags = {
    Name = "CloudCorp-RT-private-data-1b"
  }
}

resource "aws_route_table_association" "private_data_1b" {
  provider = aws.stockholm

  subnet_id      = aws_subnet.private_data_1b.id
  route_table_id = aws_route_table.private_data_1b.id
}


#####
##### --- S3 Gateway Endpoint ---
#####
# Attached to private-app route tables ONLY. Public route table is
# deliberately excluded — no direct S3 access from the public subnet.
# Policy is omitted for now (defaults to full access) and will be
# restricted once IAM roles are in place.

resource "aws_vpc_endpoint" "s3" {
  provider = aws.stockholm

  vpc_id            = aws_vpc.cloudcorp.id
  service_name      = "com.amazonaws.eu-north-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private_app_1a.id,
    aws_route_table.private_app_1b.id,
  ]

  tags = {
    Name = "CloudCorp-S3-Endpoint"
  }
}
