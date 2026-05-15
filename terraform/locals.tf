locals {
  # Availability zones i primary region
  az_1a = "eu-north-1a"
  az_1b = "eu-north-1b"

  # S3 bucket-namn (globalt unika via account ID)
  data_bucket_name   = "cloudcorp-data-${var.aws_account_id}"
  static_bucket_name = "cloudcorp-static-assets-${var.aws_account_id}"
  crr_bucket_name    = "cloudcorp-data-crr-${var.aws_account_id}"

  # Gemensamma taggar som sätts på alla resurser
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}
