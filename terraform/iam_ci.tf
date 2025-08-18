# Trust policy for CI plan role (read-only)

data "aws_iam_policy_document" "gha_oidc_trust" {
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

    # Only this repository
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = ["larriephill/url-shortener"]
    }

    # Only this workflow name (matches 'name:' at top of ci.yml)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:workflow"
      values   = ["ci-dev"]
    }

    # Allow branch runs on dev and pull_request runs
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:larriephill/url-shortener:ref:refs/heads/dev",
        "repo:larriephill/url-shortener:pull_request"
      ]
    }
  }
}



resource "aws_iam_role" "gha_plan" {
  name               = "url-dev-gha-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust.json
  tags = {
    Project = "url-shortener",
    Stage   = var.stage
  }
}

# Permissions:
# 1) ReadOnlyAccess so 'terraform plan' can read AWS resources
# 2) Backend state access (S3 + DynamoDB lock)
resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_backend" {
  statement {
    sid     = "StateBucketRW"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      "arn:aws:s3:::url-shortener-tfstate-larriephill-dev",  # bucket
      "arn:aws:s3:::url-shortener-tfstate-larriephill-dev/*" # objects
    ]
  }
  statement {
    sid       = "DynamoLockRW"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.tf_lock.arn]
  }
}

resource "aws_iam_policy" "tf_backend" {
  name   = "url-dev-tf-backend-access"
  policy = data.aws_iam_policy_document.tf_backend.json
}

resource "aws_iam_role_policy_attachment" "attach_backend" {
  role       = aws_iam_role.gha_plan.name
  policy_arn = aws_iam_policy.tf_backend.arn
}

output "gha_plan_role_arn" { value = aws_iam_role.gha_plan.arn }
