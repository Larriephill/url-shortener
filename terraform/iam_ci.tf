#############################
# CI "plan" permissions (dev)
#############################

locals {
  state_bucket_name        = "urlshortenerlarriephill"
  state_bucket_arn         = "arn:aws:s3:::${local.state_bucket_name}"
  state_bucket_objects_arn = "${local.state_bucket_arn}/*"

  # -> tf-lock-dev when stage=dev
  lock_table_name = "tf-lock-${var.stage}"
  lock_table_arn  = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:table/${local.lock_table_name}"
}

# OIDC trust for jobs running on the dev branch / PRs.
data "aws_iam_policy_document" "gha_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"
      # Use the shared OIDC provider ARN from env.tf
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Allow dev branch and PRs (both repo casings)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:larriephill/url-shortener:ref:refs/heads/dev",
        "repo:Larriephill/url-shortener:ref:refs/heads/dev",
        "repo:larriephill/url-shortener:pull_request",
        "repo:Larriephill/url-shortener:pull_request",
      ]
    }
  }
}

# DEV-ONLY plan role
resource "aws_iam_role" "gha_plan" {
  count              = local.is_dev ? 1 : 0
  name               = "url-dev-gha-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust.json
}

# What the CI plan job needs to read (S3 backend + DDB lock + various reads)
data "aws_iam_policy_document" "gha_plan_backend" {
  statement {
    sid     = "ApiGatewayV2Read"
    actions = ["apigateway:GET"]
    resources = [
      "arn:aws:apigateway:${data.aws_region.current.name}::/apis*"
    ]
  }

  statement {
    sid       = "CloudWatchLogsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid = "IamRead"
    actions = [
      "iam:GetRole",
      "iam:GetPolicy",
      "iam:ListPolicyVersions",
      "iam:GetOpenIDConnectProvider"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/url-*",
      "arn:aws:iam::${data.aws_caller_identity.me.account_id}:oidc-provider/token.actions.githubusercontent.com"
    ]
  }

  statement {
    sid = "DynamoDbDescribe"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups"
    ]
    resources = [
      "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:table/*"
    ]
  }

  # --- Backend S3 bucket (LIST + GET metadata) ---
  statement {
    sid = "S3BackendRead"
    actions = [
      "s3:GetBucketPolicy",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetBucketTagging",
      "s3:GetEncryptionConfiguration",
      "s3:GetPublicAccessBlock",
      "s3:ListBucket"
    ]
    resources = [local.state_bucket_arn]
  }

  # --- DDB lock table write (dev only but ARN resolves via local.lock_table_arn) ---
  statement {
    sid = "DynamoDbLockWrite"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [local.lock_table_arn]
  }

  # --- Read state objects in the bucket ---
  statement {
    sid       = "S3BackendObjectsRead"
    actions   = ["s3:GetObject", "s3:ListBucketMultipartUploads"]
    resources = [local.state_bucket_objects_arn]
  }
}

# DEV-ONLY plan policy
resource "aws_iam_policy" "gha_plan_backend" {
  count       = local.is_dev ? 1 : 0
  name        = "url-dev-gha-plan-backend"
  description = "Read S3 backend + DDB lock permissions for plan"
  policy      = data.aws_iam_policy_document.gha_plan_backend.json
}

resource "aws_iam_role_policy_attachment" "gha_plan_attach" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_plan[0].name
  policy_arn = aws_iam_policy.gha_plan_backend[0].arn
}

# DEV-ONLY — give plan role AWS managed ReadOnlyAccess to read other things during refresh
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  count      = local.is_dev ? 1 : 0
  role       = aws_iam_role.gha_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
