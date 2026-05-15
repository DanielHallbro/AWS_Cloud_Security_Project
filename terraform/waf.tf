###############################################################################
# CloudCorp — AWS WAF Web ACL
#
# Attached to the CloudFront distribution (scope = CLOUDFRONT).
# WAF resources with CLOUDFRONT scope must be created in us-east-1 — hence
# the aws.global provider alias.
#
# Four managed rule groups provide layered protection:
#   - AWSManagedRulesCommonRuleSet:        OWASP Top 10 baseline
#   - AWSManagedRulesKnownBadInputsRuleSet: common attack payloads
#   - AWSManagedRulesSQLiRuleSet:           SQL injection (defense in depth)
#   - AWSManagedRulesAmazonIpReputationList: known malicious IPs
#
# Two custom rules:
#   - Rate limiting: max 2000 requests per 5 minutes per IP
#   - (IP block list placeholder — add specific IPs as needed)
###############################################################################


resource "aws_wafv2_web_acl" "cloudcorp" {
  provider = aws.global

  name  = "CloudCorp-WAF"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # --- Rate limiting ---
  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  # --- Core Rule Set (OWASP Top 10 baseline) ---
  rule {
    name     = "CoreRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CoreRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # --- Known Bad Inputs ---
  rule {
    name     = "KnownBadInputs"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # --- SQL injection protection ---
  rule {
    name     = "SQLiProtection"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiProtection"
      sampled_requests_enabled   = true
    }
  }

  # --- IP Reputation List ---
  rule {
    name     = "IPReputationList"
    priority = 5

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPReputationList"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CloudCorpWAF"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "CloudCorp-WAF"
  }
}
