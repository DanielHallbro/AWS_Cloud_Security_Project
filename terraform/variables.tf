variable "aws_profile" {
  description = "AWS credentials profile (från ~/.aws/credentials)."
  type        = string
}

variable "project_name" {
  description = "Prefixnamn för alla resurser, t.ex. CloudCorp."
  type        = string
  default     = "CloudCorp"
}

variable "aws_account_id" {
  description = "AWS Account ID — används i bucket-namn och ARNs."
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "crr_region" {
  description = "CRR destination region (Frankfurt)."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR-block för VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "Master-lösenord för RDS. Hanteras som sensitive."
  type        = string
  sensitive   = true
}
