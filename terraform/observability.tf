# observability.tf
# CloudWatch Dashboard (no alarms in this file to avoid duplicates)

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "url-shortener-${var.stage}"

  dashboard_body = jsonencode({
    widgets = [
      {
        "type" : "metric", "width" : 12, "height" : 6, "x" : 0, "y" : 0,
        "properties" : {
          "title" : "Lambda — Invocations / Errors / Throttles",
          "region" : var.aws_region,
          "stat" : "Sum", "view" : "timeSeries", "stacked" : false, "period" : 300,
          "metrics" : [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.url.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.url.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.url.function_name]
          ]
        }
      },

      {
        "type" : "metric", "width" : 12, "height" : 6, "x" : 12, "y" : 0,
        "properties" : {
          "title" : "API Gateway — 4xx / 5xx / Latency (HTTP API)",
          "region" : var.aws_region,
          "view" : "timeSeries", "stacked" : false, "period" : 300,
          "metrics" : [
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.http.id, "Stage", aws_apigatewayv2_stage.default.name],
            ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.http.id, "Stage", aws_apigatewayv2_stage.default.name],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.http.id, "Stage", aws_apigatewayv2_stage.default.name, { "stat" : "p90" }]
          ]
        }
      },

      {
        "type" : "metric", "width" : 12, "height" : 6, "x" : 0, "y" : 6,
        "properties" : {
          "title" : "DynamoDB — Throttles",
          "region" : var.aws_region,
          "view" : "timeSeries", "period" : 300,
          "metrics" : [
            ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", aws_dynamodb_table.urls.name],
            ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", aws_dynamodb_table.urls.name]
          ]
        }
      },

      {
        "type" : "log", "width" : 12, "height" : 6, "x" : 12, "y" : 6,
        "properties" : {
          "region" : var.aws_region,
          "query" : format(
            "SOURCE '%s' | fields @timestamp, httpMethod, status, path, responseLatency, requestId | sort @timestamp desc | limit 50",
            aws_cloudwatch_log_group.api_gw.name
          ),
          "title" : "Recent API access logs"
        }
      }
    ]
  })
}
