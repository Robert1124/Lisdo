from __future__ import annotations

import base64
import json
from typing import Any

from . import providers
from .apple_auth import AppleIdentityTokenError, account_id_for_apple_subject, verify_apple_identity_token
from .billing import usage_cost_units
from .config import DevConfig, account_response, config_for_account, load_config, session_response
from .entitlements import draft_model_for_plan, entitlements_for_plan
from .quota import (
    MONTHLY_BUCKET,
    TOPUP_BUCKET,
    apply_storekit_transaction,
    authorized_account_id_for_token,
    create_apple_account_session,
    load_account_profile,
    load_state,
    save_state,
)
from .storekit import StoreKitTransactionError, parse_verified_transaction
from .stripe_checkout import (
    StripeCheckoutError,
    StripeConfigurationError,
    StripeWebhookError,
    create_billing_portal_session,
    create_checkout_session,
    handle_webhook,
)

JSON_HEADERS = {
    "Content-Type": "application/json; charset=utf-8",
}

GPT5_MANAGED_MAX_COMPLETION_TOKENS = 3000

PUBLIC_ROUTES = {
    ("GET", "/v1/health"),
    ("POST", "/v1/auth/apple"),
    ("POST", "/v1/stripe/webhook"),
}


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    config = load_config()
    request = _request_from_event(event)
    route = (request["method"], request["path"])

    authorized_config = config
    if route not in PUBLIC_ROUTES:
        account_id = _authorized_account_id(request["headers"], config)
        if account_id is None:
            return _error_response(401, "unauthorized", "Missing or invalid bearer token.")
        authorized_config = config_for_account(config, account_id)

    try:
        return _dispatch(route, request, authorized_config)
    except InvalidJsonBody:
        return _error_response(400, "invalid_json", "Request body must be valid JSON.")
    except InvalidRequest as exc:
        return _error_response(400, exc.code, exc.message)


def _dispatch(route: tuple[str, str], request: dict[str, Any], config: DevConfig) -> dict[str, Any]:
    if route == ("GET", "/v1/health"):
        return _json_response(
            200,
            {
                "service": "lisdo-api",
                "status": "healthy",
                "visibility": "public",
            },
        )

    if route == ("GET", "/v1/bootstrap"):
        state = load_state(config)
        return _json_response(
            200,
            {
                "account": account_response(config, plan_id=state.plan_id),
                "session": session_response(config),
                "entitlements": entitlements_for_plan(state.plan_id),
                "quota": state.snapshot(),
            },
        )

    if route == ("GET", "/v1/entitlements"):
        state = load_state(config)
        return _json_response(200, entitlements_for_plan(state.plan_id))

    if route == ("GET", "/v1/quota"):
        return _json_response(200, load_state(config).snapshot())

    if route == ("GET", "/v1/account/profile"):
        state = load_state(config)
        return _json_response(
            200,
            {
                "account": account_response(config, plan_id=state.plan_id),
                "profile": load_account_profile(config),
                "quota": state.snapshot(),
            },
        )

    if route == ("POST", "/v1/auth/apple"):
        body = _json_body(request)
        identity_token = body.get("identityToken")
        if not isinstance(identity_token, str):
            raise InvalidRequest("invalid_request", "Request body must include identityToken.")
        try:
            identity = verify_apple_identity_token(
                identity_token,
                client_ids=config.apple_client_ids,
                verification_mode=config.apple_identity_verification_mode,
                expected_nonce=_expected_nonce_from_auth_body(body),
            )
        except AppleIdentityTokenError as exc:
            raise InvalidRequest("invalid_apple_identity", str(exc)) from exc

        account_id = account_id_for_apple_subject(identity.subject)
        auth_result = create_apple_account_session(
            config,
            account_id=account_id,
            apple_subject=identity.subject,
            email=identity.email,
            audience=identity.audience,
            display_name=_display_name_from_auth_body(body),
        )
        return _json_response(
            200,
            {
                "status": "authenticated",
                **auth_result,
            },
        )

    if route == ("POST", "/v1/drafts/generate"):
        return _handle_generate_draft(request, config)

    if route == ("POST", "/v1/realtime/client-secret"):
        state = load_state(config)
        return _json_response(
            200,
            {
                "status": "not_configured",
                "mode": "stub",
                "clientSecret": "not_configured",
                "sessionId": "stub-realtime-session",
                "expiresAt": "1970-01-01T00:00:00Z",
                "quota": state.snapshot(),
            },
        )

    if route == ("POST", "/v1/storekit/transactions/verify"):
        body = _json_body(request)
        try:
            transaction = parse_verified_transaction(
                body,
                verification_mode=config.storekit_verification_mode,
                bundle_ids=config.storekit_bundle_ids,
                app_apple_id=config.storekit_app_apple_id,
                root_certificates_dir=config.storekit_root_certificates_dir,
                enable_online_checks=config.storekit_enable_online_checks,
                allow_xcode_environment=config.storekit_allow_xcode_environment,
            )
            state = apply_storekit_transaction(config, transaction)
        except StoreKitTransactionError as exc:
            raise InvalidRequest("invalid_storekit_transaction", str(exc)) from exc
        except PermissionError as exc:
            return _error_response(402, "topup_requires_monthly_plan", str(exc))

        return _json_response(
            200,
            {
                "status": "verified",
                "mode": config.storekit_verification_mode,
                "entitlements": entitlements_for_plan(state.plan_id),
                "quota": state.snapshot(),
            },
        )

    if route == ("POST", "/v1/stripe/checkout/session"):
        body = _json_body(request)
        product_id = body.get("productId")
        try:
            session = create_checkout_session(
                config,
                product_id=product_id if isinstance(product_id, str) else "",
                success_url=body.get("successUrl") if isinstance(body.get("successUrl"), str) else None,
                cancel_url=body.get("cancelUrl") if isinstance(body.get("cancelUrl"), str) else None,
            )
        except PermissionError as exc:
            return _error_response(402, "topup_requires_monthly_plan", str(exc))
        except StripeConfigurationError as exc:
            return _error_response(503, "stripe_not_configured", str(exc))
        except StripeCheckoutError as exc:
            raise InvalidRequest("invalid_stripe_checkout", str(exc)) from exc
        return _json_response(200, session)

    if route == ("POST", "/v1/stripe/billing-portal/session"):
        body = _json_body(request)
        try:
            session = create_billing_portal_session(
                config,
                return_url=body.get("returnUrl") if isinstance(body.get("returnUrl"), str) else None,
            )
        except StripeConfigurationError as exc:
            return _error_response(503, "stripe_not_configured", str(exc))
        except StripeCheckoutError as exc:
            raise InvalidRequest("invalid_stripe_portal", str(exc)) from exc
        return _json_response(200, session)

    if route == ("POST", "/v1/stripe/webhook"):
        try:
            result = handle_webhook(
                config,
                payload=_raw_body_bytes(request),
                signature=request["headers"].get("stripe-signature"),
            )
        except PermissionError as exc:
            return _json_response(
                200,
                {
                    "status": "rejected",
                    "eventType": "stripe",
                    "reason": str(exc),
                },
            )
        except StripeConfigurationError as exc:
            return _error_response(503, "stripe_not_configured", str(exc))
        except StripeWebhookError as exc:
            raise InvalidRequest("invalid_stripe_webhook", str(exc)) from exc
        return _json_response(200, result)

    return _error_response(404, "not_found", "Route not found.")


def _handle_generate_draft(request: dict[str, Any], config: DevConfig) -> dict[str, Any]:
    body = _json_body(request)
    chat_request = body.get("chatRequest")
    if not isinstance(chat_request, dict):
        raise InvalidRequest("invalid_request", "Request body must include chatRequest object.")

    state = load_state(config)
    entitlements = entitlements_for_plan(state.plan_id)
    if not entitlements["lisdoManagedDrafts"]:
        return _json_response(
            402,
            {
                "error": {
                    "code": "managed_drafts_unavailable",
                    "message": "This plan does not include managed draft generation.",
                },
                "quota": state.snapshot(),
            },
        )

    if state.next_bucket() is None:
        return _json_response(
            402,
            {
                "error": {
                    "code": "quota_exhausted",
                    "message": "No managed draft quota is available for this account.",
                },
                "quota": state.snapshot(),
            },
        )

    managed_request = _managed_draft_chat_request(chat_request, state.plan_id)
    try:
        provider_result = providers.generate_draft(managed_request)
    except Exception:
        return _json_response(
            502,
            {
                "error": {
                    "code": "provider_error",
                    "message": "Draft provider failed to generate a draft.",
                },
                "quota": state.snapshot(),
            },
        )

    cost = usage_cost_units(managed_request["model"], provider_result.get("usage"))
    consumptions = state.consume_units(cost["costUnits"])
    uncovered_cost_units = max(0, cost["costUnits"] - sum(consumptions.values()))
    save_state(config, state)
    return _json_response(
        200,
        _draft_response(
            provider_result,
            quota_snapshot=state.snapshot(),
            cost=cost,
            quota_buckets=consumptions,
            uncovered_cost_units=uncovered_cost_units,
        ),
    )


def _display_name_from_auth_body(body: dict[str, Any]) -> str | None:
    display_name = body.get("displayName")
    if isinstance(display_name, str) and display_name.strip():
        return display_name

    name = body.get("name")
    if not isinstance(name, dict):
        return None
    parts = [
        name.get("firstName"),
        name.get("middleName"),
        name.get("lastName"),
    ]
    normalized = " ".join(part.strip() for part in parts if isinstance(part, str) and part.strip())
    return normalized or None


def _managed_draft_chat_request(chat_request: dict[str, Any], plan_id: str) -> dict[str, Any]:
    messages = chat_request.get("messages")
    if not isinstance(messages, list) or not messages:
        raise InvalidRequest("invalid_request", "chatRequest.messages must be a non-empty array.")

    model = draft_model_for_plan(plan_id)
    managed_request: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "response_format": {"type": "json_object"},
    }
    if _uses_reasoning_effort(model):
        managed_request["reasoning_effort"] = "minimal"
    elif not _uses_fixed_sampling(model):
        managed_request["temperature"] = _bounded_float(chat_request.get("temperature"), default=0.1, minimum=0.0, maximum=0.4)

    max_tokens = _positive_int(chat_request.get("max_completion_tokens"))
    if max_tokens is None:
        max_tokens = _positive_int(chat_request.get("max_tokens"))
    if _uses_max_completion_tokens(model):
        managed_request["max_completion_tokens"] = GPT5_MANAGED_MAX_COMPLETION_TOKENS
    elif max_tokens is not None:
        managed_request["max_tokens"] = min(max_tokens, 1200)
    return managed_request


def _uses_reasoning_effort(model: str) -> bool:
    normalized = model.lower()
    return normalized.startswith("gpt-5")


def _uses_fixed_sampling(model: str) -> bool:
    normalized = model.lower()
    return normalized.startswith("gpt-5")


def _uses_max_completion_tokens(model: str) -> bool:
    normalized = model.lower()
    return normalized.startswith("gpt-5")


def _draft_response(
    provider_result: dict[str, Any],
    *,
    quota_snapshot: dict[str, Any],
    cost: dict[str, int],
    quota_buckets: dict[str, int],
    uncovered_cost_units: int,
) -> dict[str, Any]:
    body = dict(provider_result)
    usage = dict(body.get("usage") if isinstance(body.get("usage"), dict) else {})
    usage.update(cost)
    usage["quotaBuckets"] = {
        MONTHLY_BUCKET: quota_buckets.get(MONTHLY_BUCKET, 0),
        TOPUP_BUCKET: quota_buckets.get(TOPUP_BUCKET, 0),
    }
    usage["uncoveredCostUnits"] = uncovered_cost_units
    body["usage"] = usage
    body["quota"] = quota_snapshot
    return body


def _request_from_event(event: dict[str, Any]) -> dict[str, Any]:
    headers = {
        str(key).lower(): str(value)
        for key, value in (event.get("headers") or {}).items()
        if value is not None
    }

    if event.get("version") == "2.0":
        http_context = (event.get("requestContext") or {}).get("http") or {}
        method = str(http_context.get("method") or "").upper()
        path = str(event.get("rawPath") or http_context.get("path") or "/")
    else:
        method = str(event.get("httpMethod") or "").upper()
        path = str(event.get("path") or "/")

    return {
        "method": method,
        "path": path,
        "headers": headers,
        "body": event.get("body"),
        "isBase64Encoded": bool(event.get("isBase64Encoded", False)),
    }


def _authorized_account_id(headers: dict[str, str], config: DevConfig) -> str | None:
    authorization = headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    return authorized_account_id_for_token(config, token)


def _json_body(request: dict[str, Any]) -> dict[str, Any]:
    raw_body = request.get("body")
    if raw_body in (None, ""):
        return {}
    if not isinstance(raw_body, str):
        raise InvalidJsonBody
    if request.get("isBase64Encoded"):
        try:
            raw_body = base64.b64decode(raw_body).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise InvalidJsonBody from exc
    try:
        parsed = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise InvalidJsonBody from exc
    if not isinstance(parsed, dict):
        raise InvalidJsonBody
    return parsed


def _raw_body_bytes(request: dict[str, Any]) -> bytes:
    raw_body = request.get("body")
    if raw_body in (None, ""):
        return b""
    if not isinstance(raw_body, str):
        raise InvalidJsonBody
    if request.get("isBase64Encoded"):
        try:
            return base64.b64decode(raw_body)
        except ValueError as exc:
            raise InvalidJsonBody from exc
    return raw_body.encode("utf-8")


def _json_response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": JSON_HEADERS,
        "body": json.dumps(body, separators=(",", ":")),
    }


def _error_response(status_code: int, code: str, message: str) -> dict[str, Any]:
    return _json_response(
        status_code,
        {
            "error": {
                "code": code,
                "message": message,
            }
        },
    )


class InvalidJsonBody(Exception):
    pass


def _bounded_float(value: Any, *, default: float, minimum: float, maximum: float) -> float:
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return min(max(float(value), minimum), maximum)
    return default


def _positive_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value > 0:
        return value
    return None


def _expected_nonce_from_auth_body(body: dict[str, Any]) -> str | None:
    nonce = body.get("nonce")
    if not isinstance(nonce, str):
        return None
    nonce = nonce.strip()
    return nonce or None


class InvalidRequest(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(code)
        self.code = code
        self.message = message
