# ======================
# HTTP API + Stage + IAM
# ======================

# -------------------------------
# API Gateway HTTP API
# -------------------------------
resource "aws_apigatewayv2_api" "http" {
  name                         = "url-${var.stage}"
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = false

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# -------------------------------
# Lambda Integration
# -------------------------------
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  payload_format_version = "2.0"

  integration_uri = (
    var.enable_lambda_alias && length(aws_lambda_alias.live) > 0
    ? aws_lambda_alias.live[0].invoke_arn
    : aws_lambda_function.url.invoke_arn
  )
}




# -------------------------------
# API Routes
# -------------------------------
resource "aws_apigatewayv2_route" "post_root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_code" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /{code}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# -------------------------------
# API Stage
# -------------------------------
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      httpMethod       = "$context.httpMethod"
      status           = "$context.status"
      routeKey         = "$context.routeKey"
      integrationError = "$context.integrationErrorMessage"
      ip               = "$context.identity.sourceIp"
      userAgent        = "$context.identity.userAgent"
      requestTime      = "$context.requestTime"
      path             = "$context.path"
      protocol         = "$context.protocol"
      responseLatency  = "$context.responseLatency"
    })
  }

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 25
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# -------------------------------
# CloudWatch Log Group
# -------------------------------
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigw/${aws_apigatewayv2_api.http.name}"
  retention_in_days = 14

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# -------------------------------
# Lambda Permission for API Gateway
# -------------------------------
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# -------------------------------
# Outputs
# -------------------------------
output "api_base_url" {
  value       = aws_apigatewayv2_api.http.api_endpoint
  description = "Base URL (uses $default stage)"
}

output "post_url" {
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/"
  description = "POST here with JSON body {\"url\":\"example.com\"}"
}

output "get_url_example" {
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/{code}"
  description = "GET here to be redirected"
}

# -------------------------------
# Partition and Region Metadata

data "aws_partition" "current" {}



locals {
  api_stage_arn = "arn:${data.aws_partition.current.partition}:apigateway:${data.aws_region.current.name}::/apis/${aws_apigatewayv2_api.http.id}/stages/${aws_apigatewayv2_stage.default.name}"
}
locals {
  lambda_invoke_uri = (
    var.enable_lambda_alias && length(aws_lambda_alias.live) > 0
  ) ? aws_lambda_alias.live[0].invoke_arn : aws_lambda_function.url.invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke_alias" {
  count        = var.enable_lambda_alias ? 1 : 0
  statement_id = "AllowAPIGatewayInvokeAlias"
  action       = "lambda:InvokeFunction"
  # function_name supports qualified names; we qualify with :live
  function_name = "${aws_lambda_function.url.function_name}:${aws_lambda_alias.live[0].name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}


