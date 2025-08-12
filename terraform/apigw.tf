# HTTP API
resource "aws_apigatewayv2_api" "http" {
  name          = "url-${var.stage}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }


  #  CORS for front-ends)
  # cors_configuration {
  #   allow_origins = ["*"]
  #   allow_methods = ["GET", "POST", "OPTIONS"]
  # }
  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# Integration: API → Lambda (proxy)
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.url.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Routes
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

# Stage ($default auto-deploys)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      httpMethod              = "$context.httpMethod"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      integrationErrorMessage = "$context.integrationErrorMessage"
      responseLatency         = "$context.responseLatency"
      path                    = "$context.path"
      ip                      = "$context.identity.sourceIp"
      userAgent               = "$context.identity.userAgent"
    })
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# Access logs log group
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigw/url-${var.stage}"
  retention_in_days = 14
  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# outputs
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
