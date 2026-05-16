resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "api" {
  function_name = local.name
  description   = "Lisdo managed AI staging API. Returns draft JSON for user review."

  role             = aws_iam_role.lambda_execution.arn
  runtime          = var.lambda_runtime
  handler          = var.lambda_handler
  architectures    = [var.lambda_architecture]
  filename         = var.lambda_package_path
  source_code_hash = filebase64sha256(var.lambda_package_path)

  memory_size                    = var.lambda_memory_size_mb
  timeout                        = var.lambda_timeout_seconds
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      APPLE_SERVER_API_SETTINGS_PARAMETER_NAME = local.apple_server_api_settings_parameter_name
      LISDO_APPLE_CLIENT_IDS                   = join(",", var.apple_client_ids)
      LISDO_APPLE_IDENTITY_VERIFICATION_MODE   = var.apple_identity_verification_mode
      LISDO_DEV_ACCOUNT_ID                     = var.dev_account_id
      LISDO_DEV_MONTHLY_QUOTA                  = tostring(var.dev_monthly_quota)
      LISDO_DEV_PLAN                           = var.dev_plan
      LISDO_DEV_SESSION_ID                     = var.dev_session_id
      LISDO_DEV_SESSION_TOKEN                  = var.dev_session_token
      LISDO_DEV_TOPUP_QUOTA                    = tostring(var.dev_topup_quota)
      LISDO_DEV_USER_ID                        = var.dev_user_id
      LISDO_DYNAMODB_TABLE_NAME                = aws_dynamodb_table.ledger.name
      LISDO_ENV                                = var.env
      LISDO_SESSION_TTL_DAYS                   = tostring(var.session_ttl_days)
      LISDO_STORAGE                            = "dynamodb"
      LISDO_STOREKIT_ALLOW_XCODE_ENVIRONMENT   = tostring(var.storekit_allow_xcode_environment)
      LISDO_STOREKIT_APP_APPLE_ID              = var.storekit_app_apple_id == null ? "" : tostring(var.storekit_app_apple_id)
      LISDO_STOREKIT_BUNDLE_IDS                = join(",", var.storekit_bundle_ids)
      LISDO_STOREKIT_ENABLE_ONLINE_CHECKS      = tostring(var.storekit_enable_online_checks)
      LISDO_STOREKIT_VERIFICATION_MODE         = var.storekit_verification_mode
      OPENAI_API_KEY_PARAMETER_NAME            = local.openai_api_key_parameter_name
      PROJECT                                  = var.project
      STRIPE_AUTOMATIC_TAX_ENABLED             = tostring(var.stripe_automatic_tax_enabled)
      STRIPE_BILLING_PORTAL_RETURN_URL         = var.stripe_billing_portal_return_url
      STRIPE_CHECKOUT_CANCEL_URL               = var.stripe_checkout_cancel_url
      STRIPE_CHECKOUT_SUCCESS_URL              = var.stripe_checkout_success_url
      STRIPE_PRICE_MONTHLY_BASIC               = var.stripe_price_monthly_basic
      STRIPE_PRICE_MONTHLY_MAX                 = var.stripe_price_monthly_max
      STRIPE_PRICE_MONTHLY_PLUS                = var.stripe_price_monthly_plus
      STRIPE_PRICE_STARTER_TRIAL               = var.stripe_price_starter_trial
      STRIPE_PRICE_TOP_UP_USAGE                = var.stripe_price_top_up_usage
      STRIPE_SECRET_KEY_PARAMETER_NAME         = local.stripe_secret_key_parameter_name
      STRIPE_WEBHOOK_SECRET_PARAMETER_NAME     = local.stripe_webhook_secret_parameter_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_app,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}
