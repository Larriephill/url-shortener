############################################
# CloudFront + WAF (CLOUDFRONT) in front of HTTP API v2
# Safe-by-default: disabled unless enable_cloudfront = true
############################################

variable "enable_cloudfront" {
  description = "Enable CloudFront + WAF(CLOUDFRONT) + DNS alias in front of the HTTP API"
  type        = bool
  default     = false
}

variable "cf_subdomain" {
  description = "Subdomain served by CloudFront (e.g., 'api' for api.example.com)"
  type        = string
  default     = "api"
}

variable "create_cf_alias_record" {
  description = "Whether to create/overwrite the Route53 A/AAAA alias to point at CloudFront"
  type        = bool
  default     = true
}

locals {
  cf_fqdn       = "${var.cf_subdomain}.${var.domain_zone_name}"
  http_api_host = replace(aws_apigatewayv2_api.http.api_endpoint, "https://", "")
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_acm_certificate" "cf" {
  count             = var.enable_cloudfront ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = local.cf_fqdn
  validation_method = "DNS"

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

resource "aws_route53_record" "cf_validation" {
  for_each = var.enable_cloudfront ? {
    for dvo in aws_acm_certificate.cf[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id         = data.aws_route53_zone.root.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cf" {
  count                   = var.enable_cloudfront ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cf[0].arn
  validation_record_fqdns = values(aws_route53_record.cf_validation)[*].fqdn
}

resource "aws_wafv2_web_acl" "cf" {
  count       = var.enable_cloudfront ? 1 : 0
  provider    = aws.us_east_1
  name        = "url-shortener-${var.stage}-cf"
  description = "Protect HTTP API - managed rules"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "CommonRuleSet"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "KnownBadInputs"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "IpReputation"
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 10

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
      sampled_requests_enabled   = true
      metric_name                = "RateLimitPerIP"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "UrlShortenerCFWebACL"
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

resource "aws_cloudfront_distribution" "api" {
  count       = var.enable_cloudfront ? 1 : 0
  enabled     = true
  price_class = "PriceClass_100"
  web_acl_id  = aws_wafv2_web_acl.cf[0].arn

  aliases = [local.cf_fqdn]

  origin {
    domain_name = local.http_api_host
    origin_id   = "http-api"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "http-api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cf[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }

  depends_on = [aws_acm_certificate_validation.cf]
}

resource "aws_route53_record" "cf_alias" {
  count   = var.enable_cloudfront && var.create_cf_alias_record ? 1 : 0
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.cf_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }

  allow_overwrite = true
}

resource "aws_route53_record" "cf_alias_aaaa" {
  count   = var.enable_cloudfront && var.create_cf_alias_record ? 1 : 0
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.cf_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }

  allow_overwrite = true
}
