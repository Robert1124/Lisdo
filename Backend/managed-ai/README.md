# Lisdo Managed AI Local Dev Backend

This folder defines a minimal local backend contract for Lisdo Managed AI. It is
for app integration and backend shape testing only. It is not production auth,
storage, billing, or quota enforcement.

The service keeps Lisdo's product contract draft-first: `/v1/drafts/generate`
returns a `draftJSON` string for user review. The backend does not create,
approve, or persist final todos.

## Run Locally

```sh
python3 Backend/managed-ai/lisdo_managed_ai.py --serve --port 8787
```

The server listens on `127.0.0.1` and exposes Lambda-style routing through:

```python
lambda_handler(event, context)
```

The default local ledger path is:

```text
/tmp/lisdo-managed-ai-ledger.json
```

Override it with:

```sh
export LISDO_LEDGER_PATH=/tmp/my-lisdo-ledger.json
```

## Endpoints

### `GET /v1/me/entitlements`

Returns the dev user's current local plan, entitlements, and quota summary.

```sh
curl http://127.0.0.1:8787/v1/me/entitlements
```

Default plan is `free`.

### `POST /v1/dev/entitlements/set-plan`

Sets the local dev plan and optional starting quota values.

```sh
curl -X POST http://127.0.0.1:8787/v1/dev/entitlements/set-plan \
  -H 'Content-Type: application/json' \
  -d '{"planId":"monthlyBasic","monthlyQuotaRemaining":3,"topUpCredits":2}'
```

Supported local plan IDs:

- `free`: no managed drafts, no realtime processing, no iCloud sync.
- `starterTrial`: managed drafts and realtime processing allowed, no iCloud sync.
- `monthlyBasic`: managed drafts, iCloud sync, monthly quota, no realtime processing.
- `monthlyPlus`: managed drafts, iCloud sync, larger monthly quota, no realtime processing.
- `monthlyMax`: managed drafts, iCloud sync, realtime processing, largest monthly quota.

For local convenience, `monthly` aliases to `monthlyBasic` and `monthlyPro`
aliases to `monthlyMax`. Unknown `monthly...` plan IDs are treated as
`monthlyBasic`. Other unknown plans fall back to free behavior.

### `POST /v1/drafts/generate`

Requires an Authorization bearer token. The local server only checks that a
bearer token is present; this is not production authentication.

The request body can wrap an OpenAI-compatible chat request:

```json
{
  "chatRequest": {
    "model": "gpt-4.1-mini",
    "messages": [
      { "role": "system", "content": "Return strict Lisdo draft JSON." },
      { "role": "user", "content": "Tomorrow before 3 PM revise the questionnaire and send it to Yan." }
    ]
  }
}
```

Example:

```sh
curl -X POST http://127.0.0.1:8787/v1/drafts/generate \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer dev-token' \
  -d '{"chatRequest":{"messages":[{"role":"user","content":"Buy milk and check the receipt."}]}}'
```

Response shape:

```json
{
  "draftJSON": "{\"recommendedCategoryId\":\"shopping\",...}",
  "usage": {
    "source": "deterministic-local",
    "quotaBucket": "monthly"
  }
}
```

`draftJSON` is a string containing strict Lisdo draft JSON for the app's normal
draft parser and user review flow.

## Quota Rules

- Free cannot use managed drafts.
- `starterTrial` has managed drafts and realtime processing, but no iCloud sync.
- Monthly tiers can use managed drafts.
- Top-up credits are consumed only after monthly quota is exhausted.
- Top-up credits are consumed only while the current plan is a monthly tier.

Quota is consumed when a draft request is accepted. If an upstream OpenAI request
fails, the local implementation refunds the reserved quota bucket.

## OpenAI Proxy Behavior

If `OPENAI_API_KEY` is set, the server proxies the supplied chat request to
OpenAI Chat Completions with `urllib`.

If `OPENAI_API_KEY` is not set, the server returns a deterministic valid
`draftJSON` string based on the last user message. This lets the app test the
Managed AI integration path without paid OpenAI calls.

Secrets and full source text are never intentionally logged. The local HTTP
handler logs only method and path.

## Tests

```sh
python3 -m unittest Backend/managed-ai/test_lisdo_managed_ai.py
```
