# Lisdo API

Minimal production-shaped AWS Lambda API skeleton for Lisdo managed backend work.

The app contract remains draft-first: `/v1/drafts/generate` returns a draft and never creates or approves a final todo.

## Local Tests

From this directory:

```bash
uv run --no-project --with pytest pytest -q
```

If `pytest` is installed in the active Python environment, this also works:

```bash
python3 -m pytest -q
```

The local test path uses only the Python standard library. The Lambda runtime
provides `boto3` for DynamoDB access, so the package does not vendor AWS SDK or
database driver dependencies. `pytest` is a dev-only dependency.

## Lambda Package

Build the Terraform default Lambda zip from this directory:

```bash
make package
```

The command writes `../../Infra/aws/build/lisdo-api.zip` with `lisdo_api/` at
the zip root, matching Terraform's default `lambda_package_path` and
`lambda_handler`.

## Environment

Local/dev defaults are deterministic:

| Variable | Default | Purpose |
| --- | --- | --- |
| `LISDO_DEV_ACCOUNT_ID` | `dev-account` | Account id returned by bootstrap/auth stubs. |
| `LISDO_DEV_SESSION_ID` | `dev-session` | Session id returned by bootstrap/auth stubs. |
| `LISDO_DEV_USER_ID` | `dev-user` | Session subject. |
| `LISDO_DEV_SESSION_TOKEN` | `dev-token` | Bearer token accepted by protected routes. |
| `LISDO_DEV_PLAN` | `free` | One of `free`, `starterTrial`, `monthlyBasic`, `monthlyPlus`, `monthlyMax`. |
| `LISDO_DEV_MONTHLY_QUOTA` | `0` | Monthly non-rollover managed draft quota units. |
| `LISDO_DEV_TOPUP_QUOTA` | `0` | Top-up rollover quota units. Usable only by active monthly plans. |
| `LISDO_DEV_LEDGER_PATH` | `/tmp/lisdo-dev-quota.json` | Local quota ledger file for tests/dev. |
| `LISDO_DEV_NOW` | current UTC time | Stable development timestamp when set. |
| `LISDO_STORAGE` | `local` | `local` uses the JSON ledger; `dynamodb` uses DynamoDB when a table name is set. |
| `LISDO_DYNAMODB_TABLE_NAME` | unset | DynamoDB single-table name when `LISDO_STORAGE=dynamodb`. |
| `OPENAI_API_KEY` | unset | Local/dev provider key. When unset, the Lambda can read `OPENAI_API_KEY_PARAMETER_NAME`. |
| `OPENAI_API_KEY_PARAMETER_NAME` | unset | SSM SecureString parameter name for the OpenAI-compatible provider key. |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | OpenAI-compatible base URL when `OPENAI_API_KEY` is set. |
| `OPENAI_TIMEOUT_SECONDS` | `30` | Provider request timeout. |
| `LISDO_STOREKIT_VERIFICATION_MODE` | `client-verified` | `server-jws` verifies StoreKit `signedTransactionInfo` on the backend. |
| `LISDO_STOREKIT_BUNDLE_IDS` | Apple client IDs or `com.yiwenwu.Lisdo` | Comma-separated bundle IDs accepted in StoreKit signed transaction payloads. |
| `LISDO_STOREKIT_APP_APPLE_ID` | unset | Numeric App Apple ID, required for Production StoreKit JWS verification. |
| `LISDO_STOREKIT_ROOT_CERTIFICATES_DIR` | packaged Apple root certs | Directory containing Apple root CA `.cer` files for Sandbox/Production JWS verification. |
| `LISDO_STOREKIT_ENABLE_ONLINE_CHECKS` | `false` | Enables Apple's online certificate revocation checks in the StoreKit verifier. |
| `LISDO_STOREKIT_ALLOW_XCODE_ENVIRONMENT` | true outside production | Allows Xcode/local StoreKit transactions for staging tests. |

Do not put API keys, session tokens, source text, or provider request bodies in logs. The current skeleton does not log request bodies.

## Routes

API Gateway HTTP API v2 events are supported. Legacy REST API v1 method/path extraction is also accepted.

Public:

- `GET /v1/health`
- `POST /v1/auth/apple`

Protected with `Authorization: Bearer <token>`:

- `GET /v1/bootstrap`
- `GET /v1/entitlements`
- `GET /v1/quota`
- `POST /v1/drafts/generate`
- `POST /v1/realtime/client-secret`
- `POST /v1/storekit/transactions/verify`

Uniform auth failures return:

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Missing or invalid bearer token."
  }
}
```

## Entitlements And Quota

- `free`: BYOK/CLI only; no managed drafts, iCloud, or realtime.
- `starterTrial`: managed drafts and realtime; no iCloud.
- `monthlyBasic`, `monthlyPlus`, `monthlyMax`: managed drafts and iCloud.
- `monthlyMax` is the only monthly plan with realtime.
- One Lisdo quota unit represents `$0.0001` of LLM variable cost.
- Managed draft usage is charged from provider token usage and rounded up to quota units.
- Monthly non-rollover quota units are consumed before top-up rollover quota units.
- Top-up rollover quota is usable only for active monthly plans.
- If actual provider usage exceeds the available quota after a successful draft call, the API returns the draft, consumes all available quota, and reports `uncoveredCostUnits`.
- Missing provider usage falls back to a minimum charge of one quota unit.
- Provider failures return the current quota snapshot without consuming quota.

## Storage

`LISDO_STORAGE=local` keeps deterministic JSON-ledger behavior for tests and
local development.

`LISDO_STORAGE=dynamodb` with `LISDO_DYNAMODB_TABLE_NAME` uses a single DynamoDB
table. Account-scoped items use `pk=ACCOUNT#<normalized-account-id>` and these
sort-key shapes:

- Account meta: `sk=META`, `kind=account`, `planId`, `userId`, `updatedAt`.
- Quota grant: `sk=GRANT#<bucket>#<timestamp>#<id>`, `kind=quotaGrant`,
  `bucket`, `quantity`, `consumed`, `source`, `createdAt`, optional
  `periodEnd`/`expiresAt`.
- Usage event: `sk=USAGE#<timestamp>#<uuid>`, `kind=usageEvent`,
  `eventType=managedDraftGenerated`, `bucket`, cost-unit `quantity`,
  `createdAt`.

If an account has no quota grants, the Lambda seeds dev account metadata and
grants from the `LISDO_DEV_*` environment variables. Successful draft generation
conditionally increments active grants in monthly-then-top-up order and then
inserts usage events for the consumed cost units.

## Draft Generation

Request:

```json
{
  "chatRequest": {
    "model": "gpt-4.1-mini",
    "messages": []
  }
}
```

The backend treats the account plan as authoritative and overrides the client
`chatRequest.model` before calling the provider:

- `starterTrial`, `monthlyBasic`: `gpt-5-mini`
- `monthlyPlus`: `gpt-5.4-mini`
- `monthlyMax`: `gpt-5.4-mini`

It also strips unsupported client-supplied tool fields, forces JSON object
output, omits unsupported sampling fields for GPT-5-family models, sets
`reasoning_effort` to `minimal`, and uses a server-managed
`max_completion_tokens` cap for those models.

When `OPENAI_API_KEY` or the SSM SecureString named by
`OPENAI_API_KEY_PARAMETER_NAME` is available, `lisdo_api.providers.generate_draft`
calls an OpenAI-compatible `/chat/completions` endpoint with `urllib`. If neither
key source is available, the route returns deterministic valid Lisdo `draftJSON`
plus a draft object and consumes quota.

Provider failures return `502 provider_error` with the current quota snapshot and do not consume quota.
