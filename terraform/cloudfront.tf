###############################################################################
# CloudCorp — CloudFront Distribution
#
# Two origins:
#   - ALB: dynamic content (all requests by default)
#   - S3 static assets: CSS, JS, images via Origin Access Control (OAC)
#
# Key decisions:
#   - Viewer protocol policy: redirect HTTP to HTTPS
#     (HTTP→HTTPS redirect handled here, not at ALB level)
#   - WAF attached for Layer 7 protection at the edge
#   - AWS Shield Standard included automatically (free)
#   - Price class PriceClass_100: North America + Europe + Israel
#   - Cache disabled for dynamic content (ALB origin)
#   - Cache enabled for static assets (S3 origin)
#   - Origin Shield disabled (cost optimization)
###############################################################################


#####
##### --- Origin Access Control for S3 static assets ---
#####

resource "aws_cloudfront_origin_access_control" "static_assets" {
  provider = aws.global

  name                              = "CloudCorp-OAC-StaticAssets"
  description                       = "OAC for CloudCorp static assets bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


#####
##### --- CloudFront Distribution ---
#####

resource "aws_cloudfront_distribution" "cloudcorp" {
  provider = aws.global

  enabled             = true
  comment             = "CloudCorp CDN"
  price_class         = "PriceClass_100"
  web_acl_id          = aws_wafv2_web_acl.cloudcorp.arn
  wait_for_deployment = false

  # --- Origin: ALB (dynamic content) ---
  origin {
    domain_name = aws_lb.cloudcorp.dns_name
    origin_id   = "CloudCorp-ALB"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- Origin: S3 static assets ---
  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "CloudCorp-S3-StaticAssets"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_assets.id
  }

  # --- Default cache behavior: ALB (dynamic content) ---
  default_cache_behavior {
    target_origin_id       = "CloudCorp-ALB"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # CachingDisabled policy — dynamic content should not be cached.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    compress = true
  }

  # --- Cache behavior: S3 static assets ---
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "CloudCorp-S3-StaticAssets"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # CachingOptimized policy — static assets should be cached aggressively.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "CloudCorp-CloudFront"
  }
}


#####
##### --- S3 bucket policy: allow CloudFront OAC access ---
#####

resource "aws_s3_bucket_policy" "static_assets" {
  provider = aws.stockholm

  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cloudcorp.arn
          }
        }
      }
    ]
  })
}
