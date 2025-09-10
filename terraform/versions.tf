terraform {
  required_version = ">= 1.5, < 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Main region
variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

provider "aws" {
  region = var.aws_region
}

# Alias for CloudFront/ACM/WAF(CLOUDFRONT) in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Force Terraform to initialize the alias even if CF is disabled
data "aws_caller_identity" "use1" {
  provider = aws.us_east_1
}
