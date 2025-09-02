output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.urls.name
}

# outputs.tf
output "api_custom_domain" { value = aws_apigatewayv2_domain_name.api.domain_name }
output "api_custom_url" { value = "https://${aws_apigatewayv2_domain_name.api.domain_name}" }
output "api_id" { value = aws_apigatewayv2_api.http.id }
output "stage_name" { value = "$default" }

