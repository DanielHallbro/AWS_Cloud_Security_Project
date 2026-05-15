###############################################################################
# CloudCorp — S3 Buckets
#
# Three buckets:
#   - cloudcorp-data:         customer files, logs, backups (Stockholm)
#   - cloudcorp-static-assets: web assets served via CloudFront (Stockholm)
#   - cloudcorp-data-crr:     CRR destination bucket (Frankfurt)
#
# Account-level Block Public Access is enabled as a safety net — even if
# a bucket-level misconfiguration occurs, the account-level setting blocks
# public access. This directly addresses the root cause of the incident.
#
# CRR replicates the entire data bucket from Stockholm to Frankfurt,
# protecting against regional outages and ransomware-style data destruction.
###############################################################################


#####
##### --- Account-level Block Public Access ---
#####
# Applied to the Stockholm provider (primary account).
# Overrides any bucket-level public access setting.

resource "aws_s3_account_public_access_block" "main" {
  provider = aws.stockholm

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


#####
##### --- Data bucket (Stockholm) ---
#####

resource "aws_s3_bucket" "data" {
  provider = aws.stockholm

  bucket = local.data_bucket_name

  tags = {
    Name = "cloudcorp-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  provider = aws.stockholm

  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.stockholm.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "data" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.data.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


#####
##### --- Static assets bucket (Stockholm) ---
#####

resource "aws_s3_bucket" "static_assets" {
  provider = aws.stockholm

  bucket = local.static_bucket_name

  tags = {
    Name = "cloudcorp-static-assets"
  }
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  provider = aws.stockholm

  bucket                  = aws_s3_bucket.static_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "static_assets" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.static_assets.id

  versioning_configuration {
    # Versioning disabled — static assets are versioned at the
    # deployment level via CI/CD, not at the S3 object level.
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.static_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.stockholm.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "static_assets" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.static_assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


#####
##### --- CRR destination bucket (Frankfurt) ---
#####
# Versioning must be enabled on the destination bucket — required by AWS for CRR.

resource "aws_s3_bucket" "crr" {
  provider = aws.frankfurt

  bucket = local.crr_bucket_name

  tags = {
    Name = "cloudcorp-data-crr"
  }
}

resource "aws_s3_bucket_public_access_block" "crr" {
  provider = aws.frankfurt

  bucket                  = aws_s3_bucket.crr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "crr" {
  provider = aws.frankfurt

  bucket = aws_s3_bucket.crr.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "crr" {
  provider = aws.frankfurt

  bucket = aws_s3_bucket.crr.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.frankfurt.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "crr" {
  provider = aws.frankfurt

  bucket = aws_s3_bucket.crr.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


#####
##### --- IAM role for CRR replication ---
#####
# S3 needs a role to replicate objects from Stockholm to Frankfurt.

resource "aws_iam_role" "crr" {
  name        = "s3crr_role_for_cloudcorp-data"
  description = "Allows S3 to replicate objects to the Frankfurt CRR bucket"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "s3crr_role_for_cloudcorp-data"
  }
}

resource "aws_iam_policy" "crr" {
  name        = "CloudCorp-Policy-CRR"
  description = "Allows S3 CRR to read from Stockholm and write to Frankfurt"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SourceBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.data.arn
      },
      {
        Sid    = "SourceObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.data.arn}/*"
      },
      {
        Sid    = "DestinationBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.crr.arn}/*"
      },
      {
        Sid    = "SourceKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = aws_kms_key.stockholm.arn
      },
      {
        Sid    = "DestinationKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = aws_kms_key.frankfurt.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "crr" {
  role       = aws_iam_role.crr.name
  policy_arn = aws_iam_policy.crr.arn
}


#####
##### --- CRR replication rule ---
#####

resource "aws_s3_bucket_replication_configuration" "data" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.data.id
  role   = aws_iam_role.crr.arn

  rule {
    id     = "CloudCorp-CRR-Rule"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    destination {
      bucket        = aws_s3_bucket.crr.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.frankfurt.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.data]
}
