# eu-north-1 är primary region för allt utom CRR-bucket och CloudFront/WAF.
provider "aws" {
  alias   = "stockholm"
  region  = "eu-north-1"
  profile = var.aws_profile
}

# eu-central-1 används enbart för CRR-destinationsbucket och dess KMS-nyckel.
provider "aws" {
  alias   = "frankfurt"
  region  = "eu-central-1"
  profile = var.aws_profile
}

# us-east-1 krävs för CloudFront-certifikat (ACM) och WAF Web ACL (CLOUDFRONT scope).
provider "aws" {
  alias   = "global"
  region  = "us-east-1"
  profile = var.aws_profile
}
