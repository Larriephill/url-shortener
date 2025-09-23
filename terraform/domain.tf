data "aws_route53_zone" "root" {
  name         = var.domain_zone_name
  private_zone = false
}

# Regional cert for API Gateway custom domain (same region)
resource "aws_acm_certificate" "api" {
  domain_name       = "${var.api_subdomain}.${var.domain_zone_name}"
  validation_method = "DNS"

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

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

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.api_cert_validation : r.fqdn]
}

resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = "${var.api_subdomain}.${var.domain_zone_name}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [aws_acm_certificate_validation.api]
}

resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.http.id
  domain_name = aws_apigatewayv2_domain_name.api.domain_name
  stage       = "$default"
}

resource "aws_route53_record" "api_alias" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = aws_apigatewayv2_domain_name.api.domain_name
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }

  allow_overwrite = true
}
