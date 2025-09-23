resource "aws_dynamodb_table" "urls" {
  name         = "urls_${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortcode"

  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true } # SSE is on by default for most regions; this makes it explicit.

  attribute {
    name = "shortcode"
    type = "S"
  }
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }


  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}
