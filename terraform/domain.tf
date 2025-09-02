# 13-domain.tf
data "aws_route53_zone" "root" {
  name         = var.domain_zone_name
  private_zone = false
}

# 1) ACM cert in the SAME region as API (eu-west-2)
resource "aws_acm_certificate" "api" {
  domain_name       = "${var.api_subdomain}.${var.domain_zone_name}"
  validation_method = "DNS"
}

# DNS validation records
resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
  zone_id = data.aws_route53_zone.root.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.api_cert_validation : r.fqdn]
}

# 2) API Gateway custom domain (HTTP API v2, regional)
resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = "${var.api_subdomain}.${var.domain_zone_name}"
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

# 3) Map your API + stage to the custom domain
#    Adjust stage name if your stage isn't "live" or "$default"
resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.http.id
  domain_name = aws_apigatewayv2_domain_name.api.domain_name
  stage       = "$default"
  # optional: route_key or base_path if you want path-based mapping
}

# 4) Route53 alias A-record to the API GW domain
resource "aws_route53_record" "api_alias" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = aws_apigatewayv2_domain_name.api.domain_name
  type    = "A"
  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
