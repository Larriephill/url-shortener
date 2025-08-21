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

    # Only this repository (permit both casings)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values = [
        "larriephill/url-shortener",
        "Larriephill/url-shortener",
      ]
    }

    # Only this workflow name (matches `name:` in ci.yml)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:workflow"
      values   = ["ci-dev"]
    }

    # Allow branch runs on dev and pull_request runs (both casings)
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

# Minimal permissions for Terraform remote backend (S3+DDB lock)
data "aws_iam_policy_document" "gha_plan_backend" {
  statement {
    sid     = "S3ListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::urlshortenerlarriephill"
    ]
  }

  statement {
    sid     = "S3GetState"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::urlshortenerlarriephill/*"
    ]
  }

  # DDB table used for state locking during plan
  statement {
    sid    = "DDBStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:eu-west-2:416162027738:table/tf-lock-dev"
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
