# env.tf — shared env flags and OIDC ARN helper

variable "stage" {
  description = "Deployment stage (dev|prod)"
  type        = string
}

locals {
  # convenience flags
  is_dev  = var.stage == "dev"
  is_prod = var.stage == "prod"

  # Reuse the same GitHub OIDC provider ARN (do NOT create in prod)
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
