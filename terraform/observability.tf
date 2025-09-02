


resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "url-shortener-${var.stage}"

  # Use jsonencode so we can refer to Terraform values as expressions,
  # not as string interpolations inside JSON.
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 0
        properties = {
          metrics = [
            # Repeat notation: "." reuses prior namespace/dimension keys.
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.url.function_name],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          region  = data.aws_region.current.name
          title   = "Lambda — Invocations / Errors / Throttles"
          stat    = "Sum"
          view    = "timeSeries"
          stacked = false
          period  = 300
        }
      },

      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 0
        properties = {
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.http.id],
            [".", "5xx", ".", "."],
            [".", "Latency", "ApiId", aws_apigatewayv2_api.http.id, { stat = "Average" }]
          ]
          region  = data.aws_region.current.name
          title   = "API Gateway — 4xx / 5xx / Latency"
          view    = "timeSeries"
          stacked = false
          period  = 300
        }
      },

      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 6
        properties = {
          metrics = [
            ["UrlShortener", "RedirectCount", "Stage", var.stage],
            [".", "UrlCreatedCount", "Stage", var.stage]
          ]
          region  = data.aws_region.current.name
          title   = "Custom — Redirects / Creates"
          stat    = "Sum"
          view    = "timeSeries"
          stacked = false
          period  = 300
        }
      },

      {
        type   = "log"
        width  = 12
        height = 6
        x      = 12
        y      = 6
        properties = {
          region = data.aws_region.current.name
          # Build the Logs Insights query string in HCL, then jsonencode will stringify it.
          query = format(
            "SOURCE '%s' | fields @timestamp, httpMethod, status, path, responseLatency, requestId | sort @timestamp desc | limit 50",
            aws_cloudwatch_log_group.api_gw.name
          )
          title = "Recent API access logs"
        }
      }
    ]
  })
}
