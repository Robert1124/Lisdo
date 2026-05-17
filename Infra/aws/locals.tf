data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.env}-managed-ai"

  parameter_prefix = trimsuffix(var.parameter_prefix != "" ? var.parameter_prefix : "/${var.project}/${var.env}", "/")

  apple_server_api_settings_parameter_name = "${local.parameter_prefix}/apple/server-api-settings"
  openai_api_key_parameter_name            = "${local.parameter_prefix}/openai/api-key"
  resend_api_key_parameter_name            = var.resend_api_key_parameter_name != "" ? var.resend_api_key_parameter_name : "${local.parameter_prefix}/resend/api-key"
  stripe_secret_key_parameter_name         = var.stripe_secret_key_parameter_name != "" ? var.stripe_secret_key_parameter_name : "${local.parameter_prefix}/stripe/secret-key"
  stripe_webhook_secret_parameter_name     = var.stripe_webhook_secret_parameter_name != "" ? var.stripe_webhook_secret_parameter_name : "${local.parameter_prefix}/stripe/webhook-secret"
  ssm_parameter_arn_prefix                 = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}"

  common_tags = {
    Environment = var.env
    ManagedBy   = "terraform"
    Project     = var.project
    Service     = "managed-ai"
  }
}
