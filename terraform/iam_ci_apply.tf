# OIDC trust for APPLY role: only our repo + environment "dev"
data "aws_iam_policy_document" "gha_oidc_trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience must be STS
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Job must run in the GitHub Environment 'dev'
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:larriephill/url-shortener:environment:dev",
        "repo:Larriephill/url-shortener:environment:dev",
      ]
    }
  }
}

resource "aws_iam_role" "gha_apply" {
  name               = "url-dev-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust_apply.json
}

# Minimal permissions: remote backend (S3+DDB) with WRITE so apply can update state.
data "aws_iam_policy_document" "gha_apply_backend" {
  statement {
    sid       = "S3BucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::urlshortenerlarriephill"]
  }

  statement {
    sid       = "S3StateRw"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::urlshortenerlarriephill/*"]
  }

  statement {
    sid    = "DDBStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = ["arn:aws:dynamodb:eu-west-2:416162027738:table/tf-lock-dev"]
  }
}

resource "aws_iam_policy" "gha_apply_backend" {
  name        = "url-dev-gha-apply-backend"
  description = "Backend write for Terraform apply (S3+DDB lock)"
  policy      = data.aws_iam_policy_document.gha_apply_backend.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_backend" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_backend.arn
}

# Read-only IAM so Terraform can refresh roles/policies/OIDC/etc.
data "aws_iam_policy_document" "gha_apply_iam_read" {
  statement {
    sid    = "IamReadOnly"
    effect = "Allow"
    # List/Get are required for refresh; no write actions here.
    actions = [
      "iam:Get*",
      "iam:List*"
    ]
    # Many IAM List* actions require resource "*"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_apply_iam_read" {
  name        = "url-dev-gha-apply-iam-readonly"
  description = "Allow IAM read-only for Terraform refresh"
  policy      = data.aws_iam_policy_document.gha_apply_iam_read.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_iam_read" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_iam_read.arn
}

# ---- App deploy permissions (region-scoped) ----
data "aws_iam_policy_document" "gha_apply_app" {
  # Lambda (create/update function code/config, aliases, permissions)
  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction", "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction", "lambda:Get*", "lambda:List*",
      "lambda:PublishVersion", "lambda:CreateAlias", "lambda:UpdateAlias", "lambda:DeleteAlias",
      "lambda:AddPermission", "lambda:RemovePermission",
      "lambda:TagResource", "lambda:UntagResource"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  # API Gateway v2 (HTTP APIs)
  statement {
    sid       = "ApiGatewayV2Manage"
    effect    = "Allow"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PATCH", "apigateway:DELETE", "apigateway:PUT"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  # DynamoDB (table lifecycle & TTL)
  statement {
    sid    = "DynamoDbManageTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable", "dynamodb:UpdateTable", "dynamodb:DeleteTable",
      "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource", "dynamodb:TagResource", "dynamodb:UntagResource",
      "dynamodb:UpdateTimeToLive", "dynamodb:DescribeTimeToLive", "dynamodb:ListTables"
    ]
    resources = ["arn:aws:dynamodb:eu-west-2:416162027738:table/*"]
  }

  # CloudWatch Logs & Alarms
  statement {
    sid    = "LogsAndCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup", "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource", "cloudwatch:UntagResource"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  # IAM operations needed for Lambda execution roles & managed policies used by this stack
  statement {
    sid    = "IamForLambdaExec"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:GetRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::416162027738:role/url-*",
      "arn:aws:iam::416162027738:role/*lambda*",
      "arn:aws:iam::416162027738:policy/url_*",
      "arn:aws:iam::416162027738:policy/*lambda*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_app" {
  name        = "url-dev-gha-apply-app"
  description = "Permissions for Lambda, API GW v2, DynamoDB, Logs, CW (eu-west-2)"
  policy      = data.aws_iam_policy_document.gha_apply_app.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_app" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_app.arn
}

