# --- Lambda Errors >= 1 in a 5-minute window ---

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "url-${var.stage}-lambda-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    FunctionName = aws_lambda_function.url.function_name
  }

  alarm_description  = "Lambda reported Errors >= 1 in the last 5 minutes"
  treat_missing_data = "notBreaching"

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# --- API Gateway 5XX >= 1 in a 5-minute window ---

resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "url-${var.stage}-apigw-5xx"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # For HTTP API (v2), use ApiId and Stage
  dimensions = {
    ApiId = aws_apigatewayv2_api.http.id
    Stage = aws_apigatewayv2_stage.default.name
  }

  alarm_description  = "API Gateway returned 5XX >= 1 in the last 5 minutes"
  treat_missing_data = "notBreaching"

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}
