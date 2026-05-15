###############################################################################
# CloudCorp — Launch Template, Target Group, ALB, and Auto Scaling Group
#
# Traffic flow:
#   CloudFront → ALB (public subnets) → EC2 (private app subnets)
#
# Key decisions:
#   - No SSH key pair — admin access via SSM Session Manager only
#   - No public IPs on EC2 — instances live in private app subnets
#   - Target group protocol HTTPS (443) — end-to-end encryption
#   - HTTP→HTTPS redirect handled by CloudFront, not ALB
#   - ASG min 2 across both AZs — no single point of failure
#
# Demo vs production differences:
#   - Demo ran t3.micro (free tier); production spec is t3.medium
###############################################################################


#####
##### --- Launch Template ---
#####

resource "aws_launch_template" "cloudcorp" {
  name        = "CloudCorp-LT"
  description = "Launch template for CloudCorp EC2 instances"

  # Demo: t3.micro to stay within free tier.
  # Production spec: t3.medium.
  instance_type = "t3.micro"

  image_id = data.aws_ami.amazon_linux_2023.id

  # No key pair — access via SSM Session Manager only.
  # SSM requires no open inbound ports; EC2 initiates outbound HTTPS to AWS.

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.stockholm.arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-cloudwatch-agent nginx

    # Generate self-signed cert for HTTPS
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/server.key \
      -out /etc/nginx/ssl/server.crt \
      -subj "/CN=cloudcorp.internal/O=CloudCorp"

    # Configure nginx for HTTPS on port 443
    cat > /etc/nginx/conf.d/cloudcorp.conf << 'NGINX'
    server {
        listen 443 ssl;
        ssl_certificate     /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        location / {
            return 200 'ok';
            add_header Content-Type text/plain;
        }
    }
    NGINX

    systemctl enable nginx
    systemctl start nginx
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "CloudCorp-EC2"
    }
  }

  tags = {
    Name = "CloudCorp-LT"
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  provider    = aws.stockholm
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}


#####
##### --- Target Group ---
#####
# Protocol HTTPS (443) — matches EC2 SG inbound rule, end-to-end encryption.

resource "aws_lb_target_group" "cloudcorp" {
  provider = aws.stockholm

  name        = "CloudCorp-TG"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.cloudcorp.id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "CloudCorp-TG"
  }
}


#####
##### --- Application Load Balancer ---
#####

resource "aws_lb" "cloudcorp" {
  provider = aws.stockholm

  name               = "CloudCorp-ALB"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1b.id,
  ]

  tags = {
    Name = "CloudCorp-ALB"
  }
}

# HTTPS listener — forwards to target group.
# No HTTP:80 listener — redirect is handled by CloudFront viewer protocol policy.
resource "aws_lb_listener" "https" {
  provider = aws.stockholm

  load_balancer_arn = aws_lb.cloudcorp.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cloudcorp.arn
  }
}


#####
##### --- ACM Certificate (self-signed for demo) ---
#####
# Production: replace with a validated ACM certificate for a registered domain.
# The certificate must be in the same region as the ALB (eu-north-1).

resource "aws_acm_certificate" "alb" {
  provider = aws.stockholm

  private_key       = tls_private_key.alb.private_key_pem
  certificate_body  = tls_self_signed_cert.alb.cert_pem

  tags = {
    Name = "CloudCorp-ALB-Cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "cloudcorp.internal"
    organization = "CloudCorp"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}


#####
##### --- Auto Scaling Group ---
#####

resource "aws_autoscaling_group" "cloudcorp" {
  name = "CloudCorp-ASG"

  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  vpc_zone_identifier = [
    aws_subnet.private_app_1a.id,
    aws_subnet.private_app_1b.id,
  ]

  target_group_arns = [aws_lb_target_group.cloudcorp.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.cloudcorp.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "CloudCorp-EC2"
    propagate_at_launch = true
  }
}

# Target tracking scaling policy — scale out when CPU exceeds 70%.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "CloudCorp-CPU-Scaling"
  autoscaling_group_name = aws_autoscaling_group.cloudcorp.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
