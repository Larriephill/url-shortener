# iam_ci_apply_prod.tf
# Prod-only CI role & policies. Uses same OIDC provider ARN string (no resource dependency).

# ---------- Trust (prod) ----------
data "aws_iam_policy_document" "gha_oidc_trust_apply_prod" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # restrict to environment:prod
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
  count              = local.is_prod ? 1 : 0
  name               = "url-prod-gha-apply"
  assume_role_policy = data.aws_iam_policy_document.gha_oidc_trust_apply_prod.json

  lifecycle { ignore_changes = [description] }
}

# ---------- Backend (prod state lock/table) ----------
# NOTE: We do NOT create prod backend infra here (already exists). We only grant access.
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
    resources = ["arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.me.account_id}:table/tf-lock-prod"]
  }
}

resource "aws_iam_policy" "gha_apply_backend_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-backend"
  description = "Backend (S3+DDB lock) RW for Terraform apply (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_backend_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_backend_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_backend_prod[0].arn
}

# ---------- IAM read-only ----------
data "aws_iam_policy_document" "gha_apply_iam_read_prod" {
  statement {
    sid       = "IamReadOnly"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "gha_apply_iam_read_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-iam-readonly"
  description = "IAM read-only for Terraform refresh (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_iam_read_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_iam_read_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_iam_read_prod[0].arn
}

# ---------- App deploy perms (eu-west-2) ----------
data "aws_iam_policy_document" "gha_apply_app_prod" {
  # Lambda
  statement {
    sid    = "LambdaManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup", "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "logs:ListTagsForResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
      # dashboard reads/writes
      "cloudwatch:GetDashboard",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards"
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

  # CloudWatch + Logs
  statement {
    sid    = "LogsAndCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutRetentionPolicy",
      "logs:DeleteLogGroup", "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "logs:ListTagsForResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:GetDashboard",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards"
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

resource "aws_iam_policy" "gha_apply_app_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-app"
  description = "Deploy perms for Lambda, API GW v2, DynamoDB, Logs, CW (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_app_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_app_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_app_prod[0].arn
}

# Manage url-* policies
data "aws_iam_policy_document" "gha_apply_manage_url_policies_prod" {
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

resource "aws_iam_policy" "gha_apply_manage_url_policies_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-manage-url-policies"
  description = "Allow apply role to manage url-* policies (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_manage_url_policies_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_manage_url_policies_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_manage_url_policies_prod[0].arn
}

# Allow updating own description
data "aws_iam_policy_document" "gha_apply_self_desc_prod" {
  statement {
    sid       = "UpdateOwnDescription"
    effect    = "Allow"
    actions   = ["iam:UpdateRoleDescription"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.me.account_id}:role/url-prod-gha-apply"]
  }
}

resource "aws_iam_policy" "gha_apply_self_desc_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-self-desc"
  description = "Allow apply role to update its own description only (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_self_desc_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_self_desc_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_self_desc_prod[0].arn
}

# ---------- DNS (Route53) + ACM for custom domain (prod) ----------
# Route53: list/find zone and change records
# ACM: request + describe certificate in eu-west-2

data "aws_iam_policy_document" "gha_apply_dns_acm_prod" {
  statement {
    sid    = "Route53ManageApiRecords"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"] # Route53 APIs are mostly not resource-scoped
  }

  statement {
    sid    = "AcmRequestAndDescribe"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "acm:AddTagsToCertificate",
      "acm:ListTagsForCertificate",
      # TF to delete unused certs
      "acm:DeleteCertificate",
      "acm:RemoveTagsFromCertificate"
    ]
    resources = ["*"]
    condition {
      # ACM is regional; keep it constrained
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }
}

resource "aws_iam_policy" "gha_apply_dns_acm_prod" {
  count       = local.is_prod ? 1 : 0
  name        = "url-prod-gha-apply-dns-acm"
  description = "Manage Route53 records and ACM certificates for custom API domain (prod)"
  policy      = data.aws_iam_policy_document.gha_apply_dns_acm_prod.json
}

resource "aws_iam_role_policy_attachment" "gha_apply_attach_dns_acm_prod" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.gha_apply_prod[0].name
  policy_arn = aws_iam_policy.gha_apply_dns_acm_prod[0].arn
}
