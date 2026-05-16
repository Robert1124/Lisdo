variable "aws_region" {
  description = "AWS region for the staging stack."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI/profile name for Terraform operations."
  type        = string
  default     = "lisdo-staging"
}

variable "project" {
  description = "Project tag/name prefix."
  type        = string
  default     = "lisdo"
}

variable "env" {
  description = "Deployment environment."
  type        = string
  default     = "staging"
}

variable "parameter_prefix" {
  description = "SSM Parameter Store path prefix for backend settings. Empty uses /<project>/<env>."
  type        = string
  default     = ""

  validation {
    condition     = var.parameter_prefix == "" || (startswith(var.parameter_prefix, "/") && length(trim(var.parameter_prefix, "/")) > 0)
    error_message = "parameter_prefix must be empty or an absolute SSM path such as /lisdo/staging."
  }
}

variable "lambda_package_path" {
  description = "Path to the Lambda deployment zip. The file must exist before terraform plan/apply."
  type        = string
  default     = "./build/lisdo-api.zip"
}

variable "lambda_runtime" {
  description = "Lambda runtime for the Lisdo API package."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler inside the deployment package."
  type        = string
  default     = "lisdo_api.lambda_handler.lambda_handler"
}

variable "lambda_architecture" {
  description = "Lambda CPU architecture."
  type        = string
  default     = "arm64"
}

variable "lambda_memory_size_mb" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 30
}

variable "lambda_reserved_concurrency" {
  description = "Optional Lambda reserved concurrency. Leave null for new accounts with low concurrency quotas; API Gateway throttling still protects staging."
  type        = number
  default     = null
  nullable    = true
}

variable "dev_account_id" {
  description = "Stable UUID for the seeded staging dev account."
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "dev_session_id" {
  description = "Stable identifier returned by staging auth/bootstrap stubs."
  type        = string
  default     = "dev-session"
}

variable "dev_user_id" {
  description = "Stable subject returned by staging auth/bootstrap stubs."
  type        = string
  default     = "dev-user"
}

variable "dev_session_token" {
  description = "Bearer token accepted by the staging Lambda before real Sign in with Apple sessions are wired."
  type        = string
  default     = "dev-token"
  sensitive   = true
}

variable "dev_plan" {
  description = "Initial plan for the seeded staging dev account."
  type        = string
  default     = "free"
}

variable "dev_monthly_quota" {
  description = "Initial monthly quota grant for the seeded staging dev account."
  type        = number
  default     = 0
}

variable "dev_topup_quota" {
  description = "Initial top-up quota grant for the seeded staging dev account."
  type        = number
  default     = 0
}

variable "apple_client_ids" {
  description = "Bundle identifiers accepted as Sign in with Apple ID token audiences."
  type        = list(string)
  default = [
    "com.yiwenwu.Lisdo",
    "com.yiwenwu.Lisdo.macOS",
    "com.yiwenwu.Lisdo.web"
  ]
}

variable "apple_identity_verification_mode" {
  description = "Apple identity-token verification mode. Use apple-jwks for deployed environments."
  type        = string
  default     = "apple-jwks"
}

variable "session_ttl_days" {
  description = "Backend account session lifetime in days after Sign in with Apple."
  type        = number
  default     = 90
}

variable "storekit_verification_mode" {
  description = "StoreKit transaction verification mode. server-jws verifies StoreKit signedTransactionInfo in Lambda."
  type        = string
  default     = "server-jws"
}

variable "storekit_bundle_ids" {
  description = "Bundle identifiers accepted in StoreKit signed transaction payloads."
  type        = list(string)
  default = [
    "com.yiwenwu.Lisdo",
    "com.yiwenwu.Lisdo.macOS"
  ]
}

variable "storekit_app_apple_id" {
  description = "Numeric App Apple ID required by Apple's verifier for Production StoreKit transactions. Leave null for staging/Xcode/Sandbox."
  type        = number
  default     = null
}

variable "storekit_enable_online_checks" {
  description = "Whether Apple's StoreKit verifier performs online revocation checks."
  type        = bool
  default     = false
}

variable "storekit_allow_xcode_environment" {
  description = "Whether staging accepts Xcode/local StoreKit transactions."
  type        = bool
  default     = true
}

variable "api_route_keys" {
  description = "HTTP API route keys routed to the Lambda proxy integration."
  type        = list(string)
  default = [
    "GET /v1/health",
    "GET /v1/bootstrap",
    "GET /v1/entitlements",
    "GET /v1/quota",
    "GET /v1/account/profile",
    "POST /v1/auth/apple",
    "POST /v1/drafts/generate",
    "POST /v1/realtime/client-secret",
    "POST /v1/storekit/transactions/verify",
    "POST /v1/stripe/billing-portal/session",
    "POST /v1/stripe/checkout/session",
    "POST /v1/stripe/webhook",
    "$default"
  ]
}

variable "stripe_secret_key_parameter_name" {
  description = "Optional SSM SecureString parameter name for the Stripe secret key. Empty uses /<project>/<env>/stripe/secret-key."
  type        = string
  default     = ""
}

variable "stripe_webhook_secret_parameter_name" {
  description = "Optional SSM SecureString parameter name for the Stripe webhook signing secret. Empty uses /<project>/<env>/stripe/webhook-secret."
  type        = string
  default     = ""
}

variable "stripe_checkout_success_url" {
  description = "Default Stripe Checkout success URL."
  type        = string
  default     = "https://lisdo.robertw.me/account.html?checkout=success"
}

variable "stripe_checkout_cancel_url" {
  description = "Default Stripe Checkout cancel URL."
  type        = string
  default     = "https://lisdo.robertw.me/account.html"
}

variable "stripe_billing_portal_return_url" {
  description = "Default Stripe Billing Portal return URL."
  type        = string
  default     = "https://lisdo.robertw.me/account.html"
}

variable "stripe_automatic_tax_enabled" {
  description = "Whether Stripe Checkout sessions enable Stripe Tax automatic tax calculation."
  type        = bool
  default     = true
}

variable "stripe_price_starter_trial" {
  description = "Stripe Price ID for the one-time Starter Trial purchase."
  type        = string
  default     = "price_1TXVy2DtC3pOtIXh1qs3n24D"
}

variable "stripe_price_monthly_basic" {
  description = "Stripe Price ID for Monthly Basic."
  type        = string
  default     = "price_1TXVyVDtC3pOtIXhyqWYAfrU"
}

variable "stripe_price_monthly_plus" {
  description = "Stripe Price ID for Monthly Plus."
  type        = string
  default     = "price_1TXVzGDtC3pOtIXhANnbaAtR"
}

variable "stripe_price_monthly_max" {
  description = "Stripe Price ID for Monthly Max."
  type        = string
  default     = "price_1TXVzmDtC3pOtIXhVwMgWl5o"
}

variable "stripe_price_top_up_usage" {
  description = "Stripe Price ID for the consumable top-up usage purchase."
  type        = string
  default     = "price_1TXW0ADtC3pOtIXhMY4HfRSJ"
}

variable "api_cors_allow_origins" {
  description = "Allowed CORS origins for the staging HTTP API."
  type        = list(string)
  default     = ["*"]
}

variable "api_throttling_burst_limit" {
  description = "HTTP API stage burst throttling limit."
  type        = number
  default     = 20
}

variable "api_throttling_rate_limit" {
  description = "HTTP API stage steady-state request rate limit."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}
