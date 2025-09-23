output "table_name" {
  description = "DynamoDB table used for storing URL mappings"
  value       = aws_dynamodb_table.urls.name
}

output "api_id" {
  description = "HTTP API ID"
  value       = aws_apigatewayv2_api.http.id
}

output "api_custom_domain" {
  description = "API Gateway custom domain"
  value       = aws_apigatewayv2_domain_name.api.domain_name
}

output "api_custom_url" {
  description = "Fully qualified custom URL"
  value       = "https://${aws_apigatewayv2_domain_name.api.domain_name}"
}

output "stage_name" {
  description = "Default stage name"
  value       = "$default"
}

output "stage_arn" {
  description = "Stage ARN"
  value       = aws_apigatewayv2_stage.default.arn
}

output "lambda_version" {
  value       = aws_lambda_function.url.version
  description = "Latest published Lambda version"
}

output "lambda_alias_arn" {
  value       = var.enable_lambda_alias && length(aws_lambda_alias.live) > 0 ? aws_lambda_alias.live[0].arn : null
  description = "ARN of the 'live' alias (if enabled)"
}
