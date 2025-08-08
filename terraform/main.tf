resource "aws_dynamodb_table" "urls" {
  name         = "urls_${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortcode"

  attribute {
    name = "shortcode"
    type = "S"
  }

  tags = {
    Project = "url-shortener"
    Stage   = var.stage
  }
}
