# iam_ci_apply.tf
# Dev-only CI roles & policies (plan+apply). Prod has its own file.

# ---------- Trust policy (dev) ----------
data "aws_iam_policy_document" "gha_oidc_trust_apply" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn] # use common ARN string
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # restrict to environment:dev
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
  count              = local.is_dev ? 1 : 0
  name               = "url-dev-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust_apply.json

  lifecycle { ignore_changes = [description] }
}

# ---------- Backend (S3+DDB lock dev) ----------
data "aws_iam_policy_document" "gha_apply_backend" {
  statement {
    sid    = "S3BucketMetaReads"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:Get*"
    ]
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
      "dynamodb:DeleteItem",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:ListTagsOfResource"
    ]
    resources = ["arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:table/tf-lock-dev"]
  }
}

resource "aws_iam_policy" "gha_apply_backend" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-apply-backend"
  description = "Backend (S3+DDB lock) RW for Terraform apply (dev)"
  policy      = data.aws_iam_policy_document.gha_apply_backend.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_backend" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_apply[0].name
  policy_arn = aws_iam_policy.gha_apply_backend[0].arn
}

# ---------- IAM read-only for refresh ----------
data "aws_iam_policy_document" "gha_apply_iam_read" {
  statement {
    sid       = "IamReadOnly"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_apply_iam_read" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-apply-iam-readonly"
  description = "IAM read-only for Terraform refresh (dev)"
  policy      = data.aws_iam_policy_document.gha_apply_iam_read.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_iam_read" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_apply[0].name
  policy_arn = aws_iam_policy.gha_apply_iam_read[0].arn
}

# ---------- App deploy perms (eu-west-2) ----------
data "aws_iam_policy_document" "gha_apply_app" {
  # Lambda
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
      values   = [data.aws_region.current.name]
    }
  }

  # API Gateway v2
  statement {
    sid       = "ApiGatewayV2Manage"
    effect    = "Allow"
    actions   = ["apigateway:GET", "apigateway:POST", "apigateway:PATCH", "apigateway:DELETE", "apigateway:PUT"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # DynamoDB
  statement {
    sid    = "DynamoDbManageTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable", "dynamodb:UpdateTable", "dynamodb:DeleteTable",
      "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource", "dynamodb:TagResource", "dynamodb:UntagResource",
      "dynamodb:UpdateTimeToLive", "dynamodb:DescribeTimeToLive", "dynamodb:ListTables",
      "dynamodb:DescribeContinuousBackups"
    ]
    resources = ["arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:table/*"]
  }

  # CloudWatch + Logs (region-scoped)
  statement {
    sid    = "LogsAndCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup", "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "logs:ListTagsForResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }

  # IAM for Lambda exec roles & our url-* policies
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
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/*lambda*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/*lambda*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_app" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-apply-app"
  description = "Deploy perms for Lambda, API GW v2, DynamoDB, Logs, CW (dev)"
  policy      = data.aws_iam_policy_document.gha_apply_app.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_app" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_apply[0].name
  policy_arn = aws_iam_policy.gha_apply_app[0].arn
}

# Manage url-* policies precisely
data "aws_iam_policy_document" "gha_apply_manage_url_policies" {
  statement {
    sid    = "ManageUrlPolicies"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:ListPolicyVersions",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:DeletePolicy"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/url_*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_manage_url_policies" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-apply-manage-url-policies"
  description = "Allow apply role to manage url-* customer-managed policies (dev)"
  policy      = data.aws_iam_policy_document.gha_apply_manage_url_policies.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_manage_url_policies" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_apply[0].name
  policy_arn = aws_iam_policy.gha_apply_manage_url_policies[0].arn
}

# Allow updating own description (provider behavior)
data "aws_iam_policy_document" "gha_apply_self_desc" {
  statement {
    sid       = "UpdateOwnDescription"
    effect    = "Allow"
    actions   = ["iam:UpdateRoleDescription"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/url-dev-gha-apply"]
  }
}

resource "aws_iam_policy" "gha_apply_self_desc" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-apply-self-desc"
  description = "Allow apply role to update its own description only (dev)"
  policy      = data.aws_iam_policy_document.gha_apply_self_desc.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_self_desc" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_apply[0].name
  policy_arn = aws_iam_policy.gha_apply_self_desc[0].arn
}
