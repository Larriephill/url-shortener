# state_bootstrap.tf
# Backend bootstrap (state bucket + dev lock table) — dev only.
# Prod uses backend-prod.hcl and does not create any bootstrap infra.

resource "aws_s3_bucket" "tf_state" {
  count  = local.is_dev ? 1 : 0
  bucket = "urlshortenerlarriephill"

  tags = {
    Project = "url-shortener"
    Stage   = "dev"
  }
}

resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  count  = local.is_dev ? 1 : 0
  bucket = aws_s3_bucket.tf_state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_encryption" {
  count  = local.is_dev ? 1 : 0
  bucket = aws_s3_bucket.tf_state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state_access_block" {
  count  = local.is_dev ? 1 : 0
  bucket = aws_s3_bucket.tf_state[0].id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_dynamodb_table" "tf_lock" {
  count        = local.is_dev ? 1 : 0
  name         = "tf-lock-dev"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = "url-shortener"
    Stage   = "dev"
  }
}

