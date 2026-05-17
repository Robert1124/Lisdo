output "api_base_url" {
  description = "Base URL for the Lisdo managed backend HTTP API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_v1_base_url" {
  description = "Versioned base URL to paste into the Lisdo app provider settings."
  value       = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/v1"
}

output "dynamodb_table_name" {
  description = "DynamoDB single-table ledger used by the Lisdo managed backend."
  value       = aws_dynamodb_table.ledger.name
}

output "openai_api_key_parameter_name" {
  description = "SSM Parameter Store name for the future OpenAI API key."
  value       = local.openai_api_key_parameter_name
}

output "apple_server_api_settings_parameter_name" {
  description = "SSM Parameter Store name for future Apple server API settings."
  value       = local.apple_server_api_settings_parameter_name
}

output "resend_api_key_parameter_name" {
  description = "SSM Parameter Store name for the Resend API key."
  value       = local.resend_api_key_parameter_name
}

output "parameter_names" {
  description = "SSM Parameter Store names used by the staging backend. Values are never managed by Terraform."
  value = {
    apple_server_api_settings = local.apple_server_api_settings_parameter_name
    openai_api_key            = local.openai_api_key_parameter_name
    resend_api_key            = local.resend_api_key_parameter_name
    stripe_secret_key         = local.stripe_secret_key_parameter_name
    stripe_webhook_secret     = local.stripe_webhook_secret_parameter_name
  }
}
