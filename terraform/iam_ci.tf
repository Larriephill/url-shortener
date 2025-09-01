data "aws_iam_policy_document" "gha_oidc_trust" {
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

resource "aws_iam_role" "gha_plan" {
  name               = "url-dev-gha-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust.json
}

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
    resources = [
      aws_s3_bucket.tf_state.arn
    ]
  }

  statement {
    sid = "DynamoDbLockWrite"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.tf_lock.arn
    ]
  }

  statement {
    sid     = "S3BackendObjectsRead"
    actions = ["s3:GetObject", "s3:ListBucketMultipartUploads"]
    resources = [
      "${aws_s3_bucket.tf_state.arn}/*"
    ]
  }
}



resource "aws_iam_policy" "gha_plan_backend" {
  name        = "url-dev-gha-plan-backend"
  description = "Read S3 backend + DDB lock permissions for plan"
  policy      = data.aws_iam_policy_document.gha_plan_backend.json
}

resource "aws_iam_role_policy_attachment" "gha_plan_attach" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = aws_iam_policy.gha_plan_backend.arn
}


# Attach AWS managed ReadOnlyAccess so plan can read all resources it needs

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
