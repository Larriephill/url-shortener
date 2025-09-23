data "aws_caller_identity" "me_prod" {}

data "aws_region" "current_prod" {}

# Trust: GH Actions OIDC, environment=prod (both repo casings)
data "aws_iam_policy_document" "gha_oidc_trust_apply_prod" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:larriephill/url-shortener:environment:prod",
        "repo:Larriephill/url-shortener:environment:prod",
      ]
    }
  }
}

resource "aws_iam_role" "gha_apply_prod" {
  name               = "url-prod-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust_apply_prod.json

  lifecycle {
    ignore_changes = [description]
  }

  tags = {
    Project = "url-shortener"
    Stage   = "prod"
  }
}

# Backend (S3 + DDB lock) RW — prod
data "aws_iam_policy_document" "gha_apply_backend_prod" {
  statement {
    sid       = "S3BucketMetaReads"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:Get*"]
    resources = ["arn:aws:s3:::urlshortenerlarriephill"]
  }

  statement {
    sid       = "S3StateRw"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::urlshortenerlarriephill/*"]
  }

  statement {
    sid    = "DDBStateLockProd"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:ListTagsOfResource"
    ]
    resources = [
      "arn:aws:dynamodb:${data.aws_region.current_prod.name}:${data.aws_caller_identity.me_prod.account_id}:table/tf-lock-prod"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_backend_prod" {
  name        = "url-prod-gha-apply-backend"
  description = "Backend (S3+DDB lock) RW for Terraform apply; prod"
  policy      = data.aws_iam_policy_document.gha_apply_backend_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_backend_prod" {
  role       = aws_iam_role.gha_apply_prod.name
  policy_arn = aws_iam_policy.gha_apply_backend_prod.arn
}

# App deploy perms (region-scoped)
data "aws_iam_policy_document" "gha_apply_app_prod" {
  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:Get*",
      "lambda:List*",
      "lambda:PublishVersion",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:DeleteAlias",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  statement {
    sid    = "ApiGatewayV2Manage"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:PUT"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  statement {
    sid    = "DynamoDbManageTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:UpdateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTables",
      "dynamodb:DescribeContinuousBackups"
    ]
    resources = [
      "arn:aws:dynamodb:eu-west-2:${data.aws_caller_identity.me_prod.account_id}:table/*"
    ]
  }

  statement {
    sid    = "LogsAndCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:ListTagsForResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-2"]
    }
  }

  statement {
    sid    = "IamForLambdaExec"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.me_prod.account_id}:role/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me_prod.account_id}:role/*lambda*",
      "arn:aws:iam::${data.aws_caller_identity.me_prod.account_id}:policy/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me_prod.account_id}:policy/*lambda*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_app_prod" {
  name        = "url-prod-gha-apply-app"
  description = "Deploy perms for Lambda, API GW v2, DynamoDB, Logs, CW (eu-west-2) — prod"
  policy      = data.aws_iam_policy_document.gha_apply_app_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_app_prod" {
  role       = aws_iam_role.gha_apply_prod.name
  policy_arn = aws_iam_policy.gha_apply_app_prod.arn
}

