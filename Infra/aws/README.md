# Lisdo AWS Staging Terraform

This stack defines the AWS staging foundation for the Lisdo managed backend. It keeps the backend draft-first: the Lambda is expected to return draft JSON for app review, not create final todos.

## What This Creates

- API Gateway HTTP API with Lambda proxy routes and a throttled `$default` stage.
- Lambda execution role and Lisdo API Lambda function package path.
- DynamoDB on-demand single-table ledger for account, quota, session, and usage records.
- CloudWatch log groups for Lambda and API access logs.
- SSM Parameter Store names for OpenAI, Apple server settings, and Stripe checkout secrets.

It intentionally does not create VPCs, subnets, NAT, RDS, or Secrets Manager resources. The early staging backend is serverless-only for idle cost control and simpler operations.

## Low-Cost Choices

The default stack has no always-on compute or database instance:

- API Gateway HTTP API and Lambda are request-based.
- DynamoDB uses `PAY_PER_REQUEST`.
- Standard SSM parameters have no monthly parameter charge within AWS standard limits.
- CloudWatch costs depend on log volume and retention.
- API Gateway stage throttling defaults to 10 requests/second with a 20 request burst.

Expected idle staging total is roughly `$0-1/month` when using standard SSM parameters and no Secrets Manager. Traffic, Lambda duration, API requests, DynamoDB reads/writes/storage, and CloudWatch logs can add cost.

## Parameter Handling

Do not commit real secrets.

Terraform outputs SSM parameter names, passes those names to the Lambda, and
grants the Lambda `ssm:GetParameter` for the configured path prefix. It does not
create `aws_ssm_parameter` resources, because real values would be stored in
Terraform state.

Default names:

```text
/lisdo/staging/openai/api-key
/lisdo/staging/apple/server-api-settings
/lisdo/staging/stripe/secret-key
/lisdo/staging/stripe/webhook-secret
```

Populate values outside Terraform before using the real OpenAI-compatible
provider:

```sh
AWS_PROFILE=lisdo-staging aws ssm put-parameter \
  --region us-east-1 \
  --name /lisdo/staging/openai/api-key \
  --type SecureString \
  --value 'replace-with-real-key-outside-git' \
  --overwrite
```

Use the same pattern for `/lisdo/staging/apple/server-api-settings`, preferably with a JSON string containing only the settings the server needs.

For Stripe web checkout, populate the two Stripe SecureStrings and set the Stripe Price IDs in `terraform.tfvars`. The Lambda creates Checkout Sessions and Stripe Billing Portal sessions, while `POST /v1/stripe/webhook` is the only path that writes web purchases into the account/quota ledger.

If you need a different path, set `parameter_prefix` in `terraform.tfvars`, for example:

```hcl
parameter_prefix = "/lisdo/staging"
```

## Lambda Package

`lambda_package_path` points at the packaged Lisdo API Lambda zip. The default is:

```text
./build/lisdo-api.zip
```

Before planning or applying a real deployment, build the Lambda-compatible zip:

```sh
make -C ../../Backend/lisdo-api package
```

Run that command from `Infra/aws`. It writes `Infra/aws/build/lisdo-api.zip`
with `lisdo_api/` and pure-Python runtime dependencies at the package root. You
can also override `lambda_package_path` in your tfvars if you publish the package
elsewhere.

The staging Lambda defaults to `LISDO_STORAGE=dynamodb` and receives the table
name through `LISDO_DYNAMODB_TABLE_NAME`.

## Usage

Create a local tfvars file from the example:

```sh
cd Infra/aws
cp terraform.tfvars.example terraform.tfvars
```

Review the values, then initialize without a remote backend:

```sh
AWS_PROFILE=lisdo-staging terraform init -backend=false
```

Validate formatting and configuration:

```sh
terraform fmt -recursive
AWS_PROFILE=lisdo-staging terraform validate
```

Generate a plan:

```sh
AWS_PROFILE=lisdo-staging terraform plan -out staging.tfplan
```

Apply only after reviewing the plan and confirming the Lambda package exists:

```sh
AWS_PROFILE=lisdo-staging terraform apply staging.tfplan
```

After apply, use `api_v1_base_url` as the Lisdo provider endpoint in the iOS
and macOS app settings. `api_base_url` is the raw API Gateway root URL.

Do not run `terraform apply` from automation until package publishing, parameter population, and state storage are intentionally designed for the staging account.
