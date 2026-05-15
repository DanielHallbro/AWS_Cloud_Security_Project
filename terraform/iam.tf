###############################################################################
# CloudCorp — IAM Roles, Policies, and KMS Grant
#
# Three roles with separated responsibilities:
#   - CloudCorp-EC2-Role: assumed by EC2 instances via instance profile.
#     Least-privilege access to S3 and KMS only. SSM and CloudWatch
#     access comes from AWS managed policies.
#   - CloudCorp-InfraAdmin-Role: assumed by human operators for network,
#     compute, and storage configuration tasks.
#   - CloudCorp-SecurityAdmin-Role: assumed by human operators for
#     CloudTrail, GuardDuty, and CloudWatch. Cannot read customer data
#     or disable logging.
#
# Separation between InfraAdmin and SecurityAdmin means a compromised
# InfraAdmin credential cannot be used to tamper with audit trails.
#
# KMS grant for the EC2 role is defined here (after the role exists)
# rather than in the Stockholm key policy, to avoid the circular
# dependency where KMS validates principals at key creation time.
###############################################################################


#####
##### --- EC2 Role ---
#####

resource "aws_iam_role" "ec2" {
  name        = "CloudCorp-EC2-Role"
  description = "Assumed by EC2 instances via instance profile"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "CloudCorp-EC2-Role"
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "CloudCorp-EC2-Role"
  role = aws_iam_role.ec2.name
}

# Custom policy: least-privilege S3 access for the data and static assets buckets.
resource "aws_iam_policy" "ec2_s3" {
  name        = "CloudCorp-Policy-EC2-S3"
  description = "Least-privilege S3 and KMS access for EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DataAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::cloudcorp-data-${var.aws_account_id}",
          "arn:aws:s3:::cloudcorp-data-${var.aws_account_id}/*"
        ]
      },
      {
        Sid    = "S3StaticAssetsRead"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::cloudcorp-static-assets-${var.aws_account_id}/*"
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.stockholm.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_s3.arn
}

# AWS managed policies for SSM Session Manager and CloudWatch Agent.
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


#####
##### --- KMS grant: EC2 role → Stockholm key ---
#####
# Defined here rather than in kms.tf because KMS validates that principals
# exist at key creation time. The role must exist before the grant is created.

resource "aws_kms_grant" "ec2_stockholm" {
  name              = "cloudcorp-ec2-stockholm"
  key_id            = aws_kms_key.stockholm.key_id
  grantee_principal = aws_iam_role.ec2.arn

  operations = [
    "Decrypt",
    "GenerateDataKey",
    "GenerateDataKeyWithoutPlaintext",
    "DescribeKey"
  ]
}

# Grant for EC2 service to create grants for EBS volume encryption.
# When EC2 launches an instance with an encrypted EBS volume using a CMK,
# the EC2 service needs to create a grant on behalf of the instance.
resource "aws_kms_grant" "ebs_ec2_service" {
  name              = "cloudcorp-ebs-ec2-service"
  key_id            = aws_kms_key.stockholm.key_id
  grantee_principal = "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  operations = [
    "Decrypt",
    "GenerateDataKey",
    "GenerateDataKeyWithoutPlaintext",
    "DescribeKey",
    "CreateGrant",
    "ReEncryptFrom",
    "ReEncryptTo"
  ]
}


#####
##### --- InfraAdmin Role ---
#####

resource "aws_iam_role" "infra_admin" {
  name        = "CloudCorp-InfraAdmin-Role"
  description = "Network, compute, and storage configuration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "CloudCorp-InfraAdmin-Role"
  }
}

resource "aws_iam_policy" "infra_admin" {
  name        = "CloudCorp-Policy-InfraAdmin"
  description = "Network, compute, load balancing, and S3 config access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "NetworkAdmin"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:ModifySubnetAttribute",
          "ec2:ModifyVpcAttribute"
        ]
        Resource = "*"
      },
      {
        Sid    = "ComputeAdmin"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:TerminateInstances",
          "ec2:RunInstances",
          "elasticloadbalancing:*",
          "autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSAdmin"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:ModifyDBInstance",
          "rds:RebootDBInstance",
          "rds:CreateDBSnapshot",
          "rds:RestoreDBInstanceFromDBSnapshot"
        ]
        Resource = "*"
      },
      {
        # S3 configuration only — no GetObject/PutObject (cannot read customer data).
        Sid    = "S3ConfigAdmin"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetReplicationConfiguration",
          "s3:PutReplicationConfiguration",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_admin" {
  role       = aws_iam_role.infra_admin.name
  policy_arn = aws_iam_policy.infra_admin.arn
}


#####
##### --- SecurityAdmin Role ---
#####

resource "aws_iam_role" "security_admin" {
  name        = "CloudCorp-SecurityAdmin-Role"
  description = "CloudTrail, GuardDuty, and CloudWatch access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "CloudCorp-SecurityAdmin-Role"
  }
}

resource "aws_iam_policy" "security_admin" {
  name        = "CloudCorp-Policy-SecurityAdmin"
  description = "Security monitoring access — cannot decrypt customer data"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecurityMonitoring"
        Effect = "Allow"
        Action = [
          "cloudtrail:*",
          "guardduty:*",
          "cloudwatch:*",
          "logs:*",
          # KMS read-only — can audit key usage but cannot decrypt data.
          "kms:Describe*",
          "kms:List*",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "security_admin" {
  role       = aws_iam_role.security_admin.name
  policy_arn = aws_iam_policy.security_admin.arn
}
