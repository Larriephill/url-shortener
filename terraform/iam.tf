# Discover current region/account for ARNs
data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

# 1) Trust policy: let Lambda assume this role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "url_lambda_role_${var.stage}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

# 2) Policy: allow Lambda to write logs to CloudWatch
data "aws_iam_policy_document" "lambda_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:*"
    ]
  }
}

resource "aws_iam_policy" "lambda_logs" {
  name   = "url_lambda_logs_${var.stage}"
  policy = data.aws_iam_policy_document.lambda_logs.json
}

# 3) Policy: least-privilege access to your DynamoDB table
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem"
    ]
    resources = [aws_dynamodb_table.urls.arn]
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name   = "url_lambda_dynamodb_${var.stage}"
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

# 4) Attach both policies to the role
resource "aws_iam_role_policy_attachment" "attach_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_logs.arn
}

resource "aws_iam_role_policy_attachment" "attach_dynamodb" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}


data "aws_iam_policy_document" "lambda_metrics" {
  statement {
    sid       = "PutCustomMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # PutMetricData doesn’t support resource ARNs
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["UrlShortener"]
    }
  }
}

resource "aws_iam_policy" "lambda_metrics" {
  name   = "url_lambda_metrics_${var.stage}"
  policy = data.aws_iam_policy_document.lambda_metrics.json
}

resource "aws_iam_role_policy_attachment" "attach_metrics" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_metrics.arn
}

# (Optional) Output for convenience
output "lambda_role_arn" {
  value       = aws_iam_role.lambda.arn
  description = "IAM role ARN used by Lambda"
}
