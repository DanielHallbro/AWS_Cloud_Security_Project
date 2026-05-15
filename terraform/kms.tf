###############################################################################
# CloudCorp — KMS Customer-Managed Keys
#
# Two CMKs, one per region:
#   - Stockholm (eu-north-1): used by S3 data bucket, RDS, EBS, CloudTrail
#   - Frankfurt (eu-central-1): used by the S3 CRR destination bucket
#
# Separate keys per region provide cryptographic isolation — if one key
# is compromised, data in the other region remains protected.
#
# Key rotation is enabled on both keys (annual, AWS-managed rotation).
#
# The EC2 role (CloudCorp-EC2-Role) is granted key usage via
# aws_kms_grant in iam.tf, after the role has been created.
###############################################################################


#####
##### --- KMS key: Stockholm (primary region) ---
#####

resource "aws_kms_key" "stockholm" {
  provider = aws.stockholm

  description             = "CloudCorp KMS key — Stockholm (eu-north-1)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Grants the AWS account root full key management permissions.
        # Required — without this, the key becomes unmanageable if all
        # other admin access is removed.
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Allows CloudTrail to encrypt log files written to S3.
        Sid    = "AllowCloudTrailEncryption"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.aws_account_id}:trail/*"
          }
        }
      },
      {
        # Allows the EC2 instance role to use the key for EBS and S3.
        Sid    = "AllowEC2RoleUsage"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:role/CloudCorp-EC2-Role"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      },
      {
        # Allows the EC2 service to create grants for EBS volume encryption.
        # AWS requires this for encrypted EBS volumes — EC2 service creates
        # temporary grants on behalf of the instance at launch time.
        Sid    = "AllowEC2ServiceGrants"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "CloudCorp-KMS-Stockholm"
  }
}

resource "aws_kms_alias" "stockholm" {
  provider = aws.stockholm

  name_prefix   = "alias/cloudcorp-stockholm-"
  target_key_id = aws_kms_key.stockholm.key_id
}


#####
##### --- KMS key: Frankfurt (CRR destination region) ---
#####
# CRR destination buckets cannot reuse the source region key — a separate
# key in the destination region is required by AWS.

resource "aws_kms_key" "frankfurt" {
  provider = aws.frankfurt

  description             = "CloudCorp KMS key — Frankfurt (eu-central-1)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Allows the S3 CRR replication role to encrypt objects written
        # to the Frankfurt destination bucket.
        Sid    = "AllowS3CRRReplication"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "CloudCorp-KMS-Frankfurt"
  }
}

resource "aws_kms_alias" "frankfurt" {
  provider = aws.frankfurt

  name_prefix   = "alias/cloudcorp-frankfurt-"
  target_key_id = aws_kms_key.frankfurt.key_id
}
