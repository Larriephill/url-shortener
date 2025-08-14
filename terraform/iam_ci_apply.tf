
# Trusts only repo + dev branch

data "aws_iam_policy_document" "gha_oidc_trust_apply" {
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
        "repo:larriephill/url-shortener:ref:refs/heads/dev"
      ]
    }
  }
}

resource "aws_iam_role" "gha_apply" {
  name               = "url-dev-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust_apply.json
  tags               = { Project = "url-shortener", Stage = var.stage }
}

# Allow Terraform to change resources in dev

resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Also allow backend state access

data "aws_iam_policy_document" "tf_backend_apply" {
  statement {
    sid     = "StateBucketRW"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      "arn:aws:s3:::urlshortenerlarriephill",
      "arn:aws:s3:::urlshortenerlarriephill*"
    ]
  }
  statement {
    sid       = "DynamoLockRW"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }
}

resource "aws_iam_policy" "tf_backend_apply" {
  name   = "url-dev-tf-backend-access-apply"
  policy = data.aws_iam_policy_document.tf_backend_apply.json
}

resource "aws_iam_role_policy_attachment" "apply_backend" {
  role       = aws_iam_role.gha_apply.name
  policy_arn = aws_iam_policy.tf_backend_apply.arn
}

output "gha_apply_role_arn" {
  value = aws_iam_role.gha_apply.arn
}
