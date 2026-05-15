###############################################################################
# CloudCorp — Observability and Security Monitoring
#
# Three services:
#   - CloudTrail: audit log of all API calls in the account.
#     Multi-region trail with log file validation — tamper-evident logs.
#     Direct countermeasure to the original incident where no logging existed.
#
#   - CloudWatch Alarms: operational and security metrics.
#     Covers EC2, RDS, ALB, and WAF. Alarms publish to SNS topic.
#
#   - GuardDuty: managed threat detection.
#     Analyzes CloudTrail, VPC Flow Logs, and DNS logs against AWS threat
#     intelligence. Detects anomalous behavior, known C2 servers, and
#     credential misuse — addressing the total lack of detection capability
#     in the original environment.
###############################################################################


#####
##### --- SNS Topic for alarm notifications ---
#####

resource "aws_sns_topic" "alarms" {
  provider = aws.stockholm

  name = "CloudCorp-Alarms"

  tags = {
    Name = "CloudCorp-Alarms"
  }
}


#####
##### --- CloudTrail ---
#####

resource "aws_cloudtrail" "main" {
  provider = aws.stockholm

  name                          = "CloudCorp-Trail"
  s3_bucket_name                = aws_s3_bucket.data.id
  s3_key_prefix                 = "logs/cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.stockholm.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log S3 object-level operations on the data bucket only.
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.data.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Name = "CloudCorp-Trail"
  }
}

# S3 bucket policy required for CloudTrail to write logs.
resource "aws_s3_bucket_policy" "cloudtrail" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.data.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:eu-north-1:${var.aws_account_id}:trail/CloudCorp-Trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.data.arn}/logs/cloudtrail/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:eu-north-1:${var.aws_account_id}:trail/CloudCorp-Trail"
          }
        }
      }
    ]
  })
}


#####
##### --- CloudWatch Alarms ---
#####

# EC2: CPU utilization > 80%
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  provider = aws.stockholm

  alarm_name          = "CloudCorp-Alarm-EC2-HighCPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU utilization exceeds 80%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.cloudcorp.name
  }

  tags = {
    Name = "CloudCorp-Alarm-EC2-HighCPU"
  }
}

# RDS: CPU utilization > 80%
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  provider = aws.stockholm

  alarm_name          = "CloudCorp-Alarm-RDS-HighCPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization exceeds 80%"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.cloudcorp.identifier
  }

  tags = {
    Name = "CloudCorp-Alarm-RDS-HighCPU"
  }
}

# RDS: free storage < 10 GB
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  provider = aws.stockholm

  alarm_name          = "CloudCorp-Alarm-RDS-LowStorage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB in bytes
  alarm_description   = "RDS free storage space below 10 GB"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.cloudcorp.identifier
  }

  tags = {
    Name = "CloudCorp-Alarm-RDS-LowStorage"
  }
}

# ALB: 5xx error rate > 10
resource "aws_cloudwatch_metric_alarm" "alb_5xx_high" {
  provider = aws.stockholm

  alarm_name          = "CloudCorp-Alarm-ALB-High5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB target 5xx errors exceed 10 per minute"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.cloudcorp.arn_suffix
  }

  tags = {
    Name = "CloudCorp-Alarm-ALB-High5xx"
  }
}

# WAF: blocked requests spike
# Must use aws.global provider (us-east-1) — CloudFront WAF metrics are
# only available in us-east-1.
resource "aws_cloudwatch_metric_alarm" "waf_blocked_spike" {
  provider = aws.global

  alarm_name          = "CloudCorp-Alarm-WAF-BlockedSpike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "WAF blocked requests exceed 1000 in 5 minutes — potential attack"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = "CloudCorp-WAF"
    Region = "us-east-1"
    Rule   = "ALL"
  }

  tags = {
    Name = "CloudCorp-Alarm-WAF-BlockedSpike"
  }
}


#####
##### --- GuardDuty ---
#####
# Note: GuardDuty requires a subscription and cannot be enabled on free tier
# accounts via Terraform. Enable manually in the AWS Console to start the
# 30-day free trial. Production spec: enable with S3 protection and
# EC2 malware scanning.
#
# resource "aws_guardduty_detector" "main" { ... }
