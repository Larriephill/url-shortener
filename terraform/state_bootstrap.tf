# --- Remote state bucket & lock table (bootstrap) ---

resource "aws_s3_bucket" "tf_state" {
  bucket = "urlshortenerlarriephill"
  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#  Block public access

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "tf_lock" {
  name         = "tf-lock-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Project = "url-shortener",
    Stage   = var.stage
  }
}

output "tf_state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "tf_lock_table" { value = aws_dynamodb_table.tf_lock.name }
