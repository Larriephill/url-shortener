# iam_oidc.tf
# Create the GitHub OIDC provider ONLY in dev.
# Prod reuses the same provider by ARN and does not try to recreate it.

resource "aws_iam_openid_connect_provider" "github" {
  count          = local.is_dev ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    # GitHub Actions OIDC thumbprints
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}