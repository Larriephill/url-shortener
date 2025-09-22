output "table_name" {
  description = "Name of the DynamoDB table used for storing URL mappings"
  value       = aws_dynamodb_table.urls.name
}

# API Gateway Outputs
output "api_id" {
  description = "ID of the HTTP API Gateway"
  value       = aws_apigatewayv2_api.http.id
}

output "api_custom_domain" {
  description = "Custom domain name configured for the API Gateway"
  value       = aws_apigatewayv2_domain_name.api.domain_name
}

output "api_custom_url" {
  description = "Fully qualified custom URL for the API Gateway"
  value       = "https://${aws_apigatewayv2_domain_name.api.domain_name}"
}

output "stage_name" {
  description = "Name of the default deployment stage"
  value       = "$default"
}

output "stage_arn" {
  description = "ARN of the API Gateway deployment stage"
  value       = aws_apigatewayv2_stage.default.arn
}

# Safe: returns null when CloudFront/WAF is disabled (count = 0)
output "waf_web_acl_arn" {
  value       = length(aws_wafv2_web_acl.cf) > 0 ? aws_wafv2_web_acl.cf[0].arn : null
  description = "ARN of the CloudFront-scoped WAFv2 Web ACL (null if CloudFront disabled)"
}

output "lambda_version" {
  value       = aws_lambda_function.url.version
  description = "Latest published version of the Lambda function"
}

output "lambda_alias_arn" {
  value       = var.enable_lambda_alias && length(aws_lambda_alias.live) > 0 ? aws_lambda_alias.live[0].arn : null
  description = "ARN of the 'live' alias (if enabled)"
}



