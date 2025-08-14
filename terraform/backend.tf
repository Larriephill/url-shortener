terraform {
  backend "s3" {
    bucket         = "urlshortenerlarriephill"
    key            = "state/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "tf-lock-dev"
    encrypt        = true
  }
}
