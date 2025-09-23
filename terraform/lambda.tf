# Zip the lambda/ folder (relative to the terraform/ directory)

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda.zip"
}

# create the log group with a retention policy

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/url-${var.stage}"
  retention_in_days = 14

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# The Lambda function itself

resource "aws_lambda_function" "url" {
  function_name = "url-${var.stage}"

  # runtime/handler match your Python file and function name
  runtime = "python3.12"
  handler = "handler.lambda_handler"

  # execution role from Day 3
  role = aws_iam_role.lambda.arn

  # zipped code + hash to trigger updates on code changes
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  # env var to tell the code which table to use
  environment {
    variables = {
      TABLE           = aws_dynamodb_table.urls.name
      TTL_DAYS        = var.ttl_days
      ORIGIN_SECRET   = var.origin_shared_secret
      STAGE           = var.stage
      METRICS_ENABLED = "true"
    }
  }

  # Defaults
  timeout       = 5   # seconds
  memory_size   = 128 # MB
  architectures = ["x86_64"]

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda
  ]

  publish = true
}

# Useful outputs
output "lambda_name" {
  value       = aws_lambda_function.url.function_name
  description = "Deployed Lambda function name"
}

output "lambda_arn" {
  value       = aws_lambda_function.url.arn
  description = "Deployed Lambda function ARN"
}

resource "aws_lambda_alias" "live" {
  count            = var.enable_lambda_alias ? 1 : 0
  name             = "live"
  description      = "Stable alias for ${var.stage}"
  function_name    = aws_lambda_function.url.function_name
  function_version = aws_lambda_function.url.version

  dynamic "routing_config" {
    for_each = var.lambda_canary_weight > 0 ? [1] : []
    content {
      additional_version_weights = {
        "${aws_lambda_function.url.version}" = var.lambda_canary_weight / 100.0
      }
    }
  }
}
