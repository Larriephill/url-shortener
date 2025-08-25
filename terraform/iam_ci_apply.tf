
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

    # Only jobs running in environment "dev" (allow both repo casings)
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

  # Prevents Terraform from ever trying to change the role description
  lifecycle {
    ignore_changes = [description]
  }
}


# ---- BACKEND (S3 + DDB lock) — WRITE + reads terraform needs ----

data "aws_iam_policy_document" "gha_apply_backend" {
  # List & metadata on the state bucket
  statement {
    sid    = "S3BucketMetaReads"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:Get*"
    ]
    resources = ["arn:aws:s3:::urlshortenerlarriephill"]
  }

  # Read/Write state objects
  statement {
    sid       = "S3StateRw"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::urlshortenerlarriephill/*"]
  }

  # DDB state lock + backups describe
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
    resources = ["arn:aws:dynamodb:eu-west-2:416162027738:table/tf-lock-dev"]
  }
}




resource "aws_iam_policy" "gha_apply_backend" {
  name        = "url-dev-gha-apply-backend"
  description = "Backend (S3+DDB lock) RW for Terraform apply; includes required reads"
  policy      = data.aws_iam_policy_document.gha_apply_backend.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_backend" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_backend.arn
}

# ---- IAM READ for refresh (no writes) ----
data "aws_iam_policy_document" "gha_apply_iam_read" {
  statement {
    sid       = "IamReadOnly"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
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

# ---- APP DEPLOY perms (region-scoped where possible) ----
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
      values   = ["eu-west-2"]
    }
  }

  # API Gateway v2 control-plane
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

  # DynamoDB (tables, TTL, backups describe)
  statement {
    sid    = "DynamoDbManageTables"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable", "dynamodb:UpdateTable", "dynamodb:DeleteTable",
      "dynamodb:DescribeTable", "dynamodb:ListTagsOfResource", "dynamodb:TagResource", "dynamodb:UntagResource",
      "dynamodb:UpdateTimeToLive", "dynamodb:DescribeTimeToLive", "dynamodb:ListTables",
      "dynamodb:DescribeContinuousBackups"
    ]
    resources = ["arn:aws:dynamodb:eu-west-2:416162027738:table/*"]
  }

  # CloudWatch Logs + CloudWatch (incl. Logs tag reads)
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
      values   = ["eu-west-2"]
    }
  }

  # IAM needed for lambda exec roles & customer policies used by this stack
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
      "arn:aws:iam::416162027738:policy/url-*",
      "arn:aws:iam::416162027738:policy/*lambda*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_app" {
  name        = "url-dev-gha-apply-app"
  description = "Deploy perms for Lambda, API GW v2, DynamoDB, Logs, CW (eu-west-2)"
  policy      = data.aws_iam_policy_document.gha_apply_app.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_app" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_app.arn
}

# ---- Manage our url-* customer-managed policies precisely ----
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
      "arn:aws:iam::416162027738:policy/url-*",
      "arn:aws:iam::416162027738:policy/url_*"
    ]
  }
}

resource "aws_iam_policy" "gha_apply_manage_url_policies" {
  name        = "url-dev-gha-apply-manage-url-policies"
  description = "Allow apply role to manage url-* customer-managed policies"
  policy      = data.aws_iam_policy_document.gha_apply_manage_url_policies.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_manage_url_policies" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_manage_url_policies.arn
}

# Allow this role to update its own description (needed due to provider behavior)
data "aws_iam_policy_document" "gha_apply_self_desc" {
  statement {
    sid       = "UpdateOwnDescription"
    effect    = "Allow"
    actions   = ["iam:UpdateRoleDescription"]
    resources = ["arn:aws:iam::416162027738:role/url-dev-gha-apply"]
  }
}

resource "aws_iam_policy" "gha_apply_self_desc" {
  name        = "url-dev-gha-apply-self-desc"
  description = "Allow apply role to update its own description only"
  policy      = data.aws_iam_policy_document.gha_apply_self_desc.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_self_desc" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.gha_apply_self_desc.arn
}

