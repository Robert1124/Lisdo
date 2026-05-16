# Lisdo Managed AI AWS Backend Design

## Scope

This design defines the first AWS staging backend for Lisdo Managed AI. It
supports shared iOS/macOS account entitlements, quota tracking, draft generation,
and a future Realtime token flow. It does not approve todos or bypass the
draft-first product loop.

The first deploy target is `staging`. Production is a separate stack after
StoreKit, web checkout, and operational alarms have been verified.

## Architecture

```text
iOS/macOS app
  -> API Gateway HTTP API
  -> Lambda API
  -> DynamoDB single-table ledger
  -> OpenAI API / Realtime sessions
  -> App Store Server API verification
```

AWS resources are managed by Terraform under `Infra/aws`. The first staging
stack is serverless-only: no RDS, no VPC, no NAT gateway or NAT instance, and no
always-on compute. Secret/config values are referenced by SSM Parameter Store
names and are never committed to the repository; the Lambda reads provider keys
from SSM SecureString at runtime.

## Identity

The app uses Sign in with Apple plus Lisdo backend sessions.

- `POST /v1/auth/apple` receives Apple authorization material from the app.
- The backend validates Apple identity and maps the stable Apple subject to a
  Lisdo account.
- The backend issues Lisdo session tokens for app API calls.
- iOS App Store purchases and Mac/web purchases grant entitlements to the same
  Lisdo account.

The initial staging implementation may include a dev session path for local
testing, but production request paths must require a Lisdo session.

## Entitlements

Plan and quota are account-scoped, not device-scoped.

Plans:

- `free`: BYOK/CLI only, no Lisdo provider, no iCloud sync.
- `starterTrial`: Lisdo provider and Realtime allowed, no iCloud sync.
- `monthlyBasic`: Lisdo provider and iCloud sync.
- `monthlyPlus`: same features as Monthly Basic with more quota.
- `monthlyMax`: Monthly Plus plus Realtime.

The app treats server state as authoritative once a user is logged in. Local dev
plan selection remains only for offline development.

## Quota Ledger

Quota is append-only and auditable. The first staging implementation stores the
ledger in DynamoDB with `pk` and `sk` keys so early idle cost stays close to
zero.

Logical item types:

- `account`: plan and account metadata.
- `quotaGrant`: trial, monthly, top-up, and admin credits.
- `usageEvent`: debits and refunds with idempotency keys.

Debit order:

```text
monthly non-rollover quota
  -> top-up rollover quota
```

Top-up quota is usable only while the account has an active monthly plan.

Each successful LLM or Realtime server interaction returns a quota snapshot so
iOS/macOS can update the progress bar without estimating locally.

## Draft Generation

`POST /v1/drafts/generate` accepts the app's current OpenAI-compatible
`chatRequest` wrapper and returns:

```json
{
  "draftJSON": "...strict Lisdo draft JSON...",
  "quota": { "monthlyRemaining": 0, "topUpRemaining": 0 }
}
```

The backend never creates or approves final todos. The app still parses the
draft JSON and shows review UI before saving.

For cost control, the backend does not trust the app-provided model. It maps the
account plan to a managed draft model server-side: Starter Trial and Monthly
Basic use `gpt-5-mini`, while Monthly Plus and Monthly Max use
`gpt-5.4-mini`. Realtime remains a separate future path.

## Realtime

`POST /v1/realtime/client-secret` is the server gate for future GPT Realtime.

The backend checks entitlement and quota before creating a short-lived client
secret. Staging can return a deterministic stub until the app Realtime feature is
implemented. Production should reserve a session budget, issue the short-lived
OpenAI client secret, and settle or refund usage after session close.

## StoreKit And Web Purchases

StoreKit purchase and restore flows call:

```text
POST /v1/storekit/transactions/verify
```

The backend verifies transactions with Apple and writes subscription/top-up
entitlements to the Lisdo account.

Web checkout uses Stripe Checkout Sessions for one-time purchases and
subscriptions. The website or Mac app requests a Checkout Session with an
authenticated Lisdo bearer token, then Stripe webhooks write the same entitlement
and quota tables as StoreKit. iOS will not direct users to web checkout.

## Operational Guardrails

Staging Terraform must include:

- low Lambda reserved concurrency;
- API Gateway throttling;
- CloudWatch logs;
- DynamoDB on-demand billing;
- SSM Parameter Store names for future provider/Apple settings;
- tagged resources: `project=lisdo`, `env=staging`;
- no committed secret values;
- no automatic `terraform apply` without owner approval.

## Deployment Flow

```text
terraform init -backend=false
terraform validate
terraform plan
owner reviews plan and expected cost
terraform apply
configure app staging API base URL
```

## Non-goals

- No production deployment in the first pass.
- No direct Apple Reminders or Calendar integration.
- No final todo creation on the backend.
