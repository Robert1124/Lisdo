from __future__ import annotations

import importlib
import json
import base64
import time
import sys
import enum
import types
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest

BACKEND_SRC = Path(__file__).resolve().parents[1] / "src"
if str(BACKEND_SRC) not in sys.path:
    sys.path.insert(0, str(BACKEND_SRC))

Handler = Callable[[dict[str, Any], Any], dict[str, Any]]
STRICT_DRAFT_FIELDS = {
    "recommendedCategoryId",
    "confidence",
    "title",
    "summary",
    "blocks",
    "dueDateText",
    "priority",
    "needsClarification",
    "questionsForUser",
}


def _clear_lisdo_api_modules() -> None:
    for module_name in list(sys.modules):
        if module_name == "lisdo_api" or module_name.startswith("lisdo_api."):
            del sys.modules[module_name]


def unsigned_apple_identity_token(
    *,
    subject: str = "apple-subject-1",
    audience: str = "com.yiwenwu.Lisdo",
    email: str | None = "test@example.com",
    nonce: str | None = None,
) -> str:
    header = {"alg": "none", "typ": "JWT"}
    payload: dict[str, Any] = {
        "iss": "https://appleid.apple.com",
        "sub": subject,
        "aud": audience,
        "exp": int(time.time()) + 3600,
    }
    if email is not None:
        payload["email"] = email
    if nonce is not None:
        payload["nonce"] = nonce
    return ".".join(
        [
            _base64url_json(header),
            _base64url_json(payload),
            "",
        ]
    )


def unsigned_storekit_transaction_jws(
    *,
    transaction_id: str = "1000001",
    original_transaction_id: str | None = None,
    bundle_id: str = "com.yiwenwu.Lisdo",
    product_id: str = "com.yiwenwu.Lisdo.monthlyBasic",
    environment: str = "Xcode",
    purchase_date_ms: int = 1778760000000,
    expires_date_ms: int | None = 1781438400000,
) -> str:
    payload: dict[str, Any] = {
        "transactionId": transaction_id,
        "originalTransactionId": original_transaction_id or transaction_id,
        "bundleId": bundle_id,
        "productId": product_id,
        "environment": environment,
        "purchaseDate": purchase_date_ms,
    }
    if expires_date_ms is not None:
        payload["expiresDate"] = expires_date_ms

    return ".".join(
        [
            _base64url_json({"alg": "none", "typ": "JWT"}),
            _base64url_json(payload),
            "",
        ]
    )


def unsigned_storekit_notification_jws(
    *,
    notification_type: str = "DID_RENEW",
    notification_uuid: str = "notification-1",
    signed_transaction_info: str | None = None,
    bundle_id: str = "com.yiwenwu.Lisdo",
    environment: str = "Xcode",
) -> str:
    payload: dict[str, Any] = {
        "notificationType": notification_type,
        "notificationUUID": notification_uuid,
        "data": {
            "bundleId": bundle_id,
            "environment": environment,
            "signedTransactionInfo": signed_transaction_info or unsigned_storekit_transaction_jws(environment=environment),
        },
    }
    return ".".join(
        [
            _base64url_json({"alg": "none", "typ": "JWT"}),
            _base64url_json(payload),
            "",
        ]
    )


def install_fake_app_store_server_library(monkeypatch: pytest.MonkeyPatch) -> None:
    class FakeEnvironment(enum.Enum):
        SANDBOX = "Sandbox"
        PRODUCTION = "Production"
        XCODE = "Xcode"
        LOCAL_TESTING = "LocalTesting"

    class FakeVerificationException(Exception):
        pass

    class FakeSignedDataVerifier:
        def __init__(
            self,
            root_certificates: list[bytes],
            enable_online_checks: bool,
            environment: FakeEnvironment,
            bundle_id: str,
            app_apple_id: int | None = None,
        ) -> None:
            del root_certificates, enable_online_checks, app_apple_id
            self.environment = environment.value
            self.bundle_id = bundle_id

        def verify_and_decode_signed_transaction(self, signed_transaction: str) -> Any:
            payload = _decode_unsigned_jws_payload(signed_transaction)
            if payload.get("environment") != self.environment:
                raise FakeVerificationException("environment mismatch")
            if payload.get("bundleId") != self.bundle_id:
                raise FakeVerificationException("bundle mismatch")
            return types.SimpleNamespace(**payload)

        def verify_and_decode_notification(self, signed_payload: str) -> Any:
            payload = _decode_unsigned_jws_payload(signed_payload)
            data = payload.get("data")
            if not isinstance(data, dict):
                raise FakeVerificationException("notification data missing")
            if data.get("environment") != self.environment:
                raise FakeVerificationException("environment mismatch")
            if data.get("bundleId") != self.bundle_id:
                raise FakeVerificationException("bundle mismatch")
            return types.SimpleNamespace(**payload)

    package = types.ModuleType("appstoreserverlibrary")
    signed_data_module = types.ModuleType("appstoreserverlibrary.signed_data_verifier")
    signed_data_module.SignedDataVerifier = FakeSignedDataVerifier
    signed_data_module.VerificationException = FakeVerificationException

    models_package = types.ModuleType("appstoreserverlibrary.models")
    environment_module = types.ModuleType("appstoreserverlibrary.models.Environment")
    environment_module.Environment = FakeEnvironment

    monkeypatch.setitem(sys.modules, "appstoreserverlibrary", package)
    monkeypatch.setitem(sys.modules, "appstoreserverlibrary.signed_data_verifier", signed_data_module)
    monkeypatch.setitem(sys.modules, "appstoreserverlibrary.models", models_package)
    monkeypatch.setitem(sys.modules, "appstoreserverlibrary.models.Environment", environment_module)


def _decode_unsigned_jws_payload(jws: str) -> dict[str, Any]:
    parts = jws.split(".")
    assert len(parts) == 3
    payload = parts[1] + ("=" * (-len(parts[1]) % 4))
    decoded = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))
    assert isinstance(decoded, dict)
    return decoded


def _base64url_json(value: dict[str, Any]) -> str:
    data = json.dumps(value, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


@pytest.fixture
def load_lambda_handler(monkeypatch: pytest.MonkeyPatch, tmp_path) -> Callable[..., Handler]:
    def _load(
        *,
        plan: str = "free",
        monthly_quota: int = 0,
        topup_quota: int = 0,
        openai_api_key: str | None = "test-openai-key",
        openai_api_key_parameter_name: str | None = None,
        storage: str = "local",
        dynamodb_table_name: str | None = None,
        storekit_verification_mode: str = "client-verified",
        stripe_secret_key: str | None = None,
        stripe_webhook_secret: str | None = None,
        stripe_prices: dict[str, str] | None = None,
    ) -> Handler:
        monkeypatch.setenv("LISDO_DEV_ACCOUNT_ID", "dev-account")
        monkeypatch.setenv("LISDO_DEV_SESSION_ID", "dev-session")
        monkeypatch.setenv("LISDO_DEV_USER_ID", "dev-user")
        monkeypatch.setenv("LISDO_DEV_PLAN", plan)
        monkeypatch.setenv("LISDO_DEV_MONTHLY_QUOTA", str(monthly_quota))
        monkeypatch.setenv("LISDO_DEV_TOPUP_QUOTA", str(topup_quota))
        monkeypatch.setenv("LISDO_DEV_LEDGER_PATH", str(tmp_path / "lisdo-dev-quota.json"))
        monkeypatch.setenv("LISDO_DEV_NOW", "2026-05-14T12:00:00Z")
        monkeypatch.setenv("LISDO_STORAGE", storage)
        if dynamodb_table_name is None:
            monkeypatch.delenv("LISDO_DYNAMODB_TABLE_NAME", raising=False)
        else:
            monkeypatch.setenv("LISDO_DYNAMODB_TABLE_NAME", dynamodb_table_name)
        monkeypatch.setenv(
            "LISDO_APPLE_CLIENT_IDS",
            "com.yiwenwu.Lisdo,com.yiwenwu.Lisdo.macOS,com.yiwenwu.Lisdo.web",
        )
        monkeypatch.setenv("LISDO_APPLE_IDENTITY_VERIFICATION_MODE", "unsigned-dev")
        monkeypatch.setenv("LISDO_STOREKIT_VERIFICATION_MODE", storekit_verification_mode)
        monkeypatch.setenv("LISDO_STOREKIT_BUNDLE_IDS", "com.yiwenwu.Lisdo,com.yiwenwu.Lisdo.macOS")
        monkeypatch.setenv("LISDO_STOREKIT_ALLOW_XCODE_ENVIRONMENT", "true")
        monkeypatch.setenv("LISDO_SESSION_TTL_DAYS", "90")

        if openai_api_key is None:
            monkeypatch.delenv("OPENAI_API_KEY", raising=False)
        else:
            monkeypatch.setenv("OPENAI_API_KEY", openai_api_key)
        if openai_api_key_parameter_name is None:
            monkeypatch.delenv("OPENAI_API_KEY_PARAMETER_NAME", raising=False)
        else:
            monkeypatch.setenv("OPENAI_API_KEY_PARAMETER_NAME", openai_api_key_parameter_name)

        if stripe_secret_key is None:
            monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
        else:
            monkeypatch.setenv("STRIPE_SECRET_KEY", stripe_secret_key)
        if stripe_webhook_secret is None:
            monkeypatch.delenv("STRIPE_WEBHOOK_SECRET", raising=False)
        else:
            monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", stripe_webhook_secret)

        stripe_price_envs = {
            "starterTrial": "STRIPE_PRICE_STARTER_TRIAL",
            "monthlyBasic": "STRIPE_PRICE_MONTHLY_BASIC",
            "monthlyPlus": "STRIPE_PRICE_MONTHLY_PLUS",
            "monthlyMax": "STRIPE_PRICE_MONTHLY_MAX",
            "topUpUsage": "STRIPE_PRICE_TOP_UP_USAGE",
        }
        for product_id, env_name in stripe_price_envs.items():
            value = (stripe_prices or {}).get(product_id)
            if value is None:
                monkeypatch.delenv(env_name, raising=False)
            else:
                monkeypatch.setenv(env_name, value)
        monkeypatch.setenv("STRIPE_CHECKOUT_SUCCESS_URL", "https://lisdo.test/billing/success")
        monkeypatch.setenv("STRIPE_CHECKOUT_CANCEL_URL", "https://lisdo.test/billing/cancel")

        _clear_lisdo_api_modules()
        module = importlib.import_module("lisdo_api.lambda_handler")
        handler = getattr(module, "lambda_handler", None)
        assert callable(handler), "lisdo_api.lambda_handler.lambda_handler must be callable"
        return handler

    return _load


@pytest.fixture
def install_provider(monkeypatch: pytest.MonkeyPatch) -> Callable[..., list[dict[str, Any]]]:
    def _install(
        *,
        raises: Exception | None = None,
        usage: dict[str, Any] | None = None,
    ) -> list[dict[str, Any]]:
        provider_module = importlib.import_module("lisdo_api.providers")
        calls: list[dict[str, Any]] = []

        def generate_draft(chat_request: dict[str, Any], *args: Any, **kwargs: Any) -> dict[str, Any]:
            calls.append({"chatRequest": chat_request, "args": args, "kwargs": kwargs})
            if raises is not None:
                raise raises
            draft_json = {
                "recommendedCategoryId": "work",
                "confidence": 0.82,
                "title": "Review questionnaire",
                "summary": "Review the questionnaire and send it to Yan.",
                "blocks": [
                    {
                        "type": "checkbox",
                        "content": "Review the questionnaire and send it to Yan.",
                        "checked": False,
                    }
                ],
                "dueDateText": None,
                "priority": "medium",
                "needsClarification": False,
                "questionsForUser": [],
            }
            return {
                "draftJSON": json.dumps(draft_json, separators=(",", ":")),
                "draft": {
                    "status": "draft",
                    "title": "Review questionnaire",
                    "recommendedCategoryId": "work",
                    "summary": "Review the questionnaire and send it to Yan.",
                    "blocks": [
                        {
                            "kind": "task",
                            "text": "Review the questionnaire and send it to Yan.",
                        }
                    ],
                    "needsClarification": False,
                    "questionsForUser": [],
                },
                "usage": {
                    "source": "pytest-provider",
                    "model": "pytest-model",
                    **(usage or {}),
                },
            }

        monkeypatch.setattr(provider_module, "generate_draft", generate_draft)
        return calls

    return _install


def api_gateway_v2_event(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    return {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": path,
        "rawQueryString": "",
        "cookies": [],
        "headers": headers or {},
        "requestContext": {
            "accountId": "offline",
            "apiId": "offline",
            "domainName": "localhost",
            "domainPrefix": "localhost",
            "http": {
                "method": method,
                "path": path,
                "protocol": "HTTP/1.1",
                "sourceIp": "127.0.0.1",
                "userAgent": "pytest",
            },
            "requestId": "pytest-request",
            "routeKey": "$default",
            "stage": "$default",
            "time": "14/May/2026:12:00:00 +0000",
            "timeEpoch": 1778760000000,
        },
        "body": json.dumps(body) if body is not None else None,
        "isBase64Encoded": False,
    }


def invoke(
    handler: Handler,
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    token: str | None = "dev-token",
    headers: dict[str, str] | None = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    request_headers = dict(headers or {})
    if token is not None:
        request_headers["Authorization"] = f"Bearer {token}"
    event = api_gateway_v2_event(method, path, body=body, headers=request_headers)
    assert "httpMethod" not in event
    assert "path" not in event

    response = handler(event, None)
    assert isinstance(response, dict)
    assert isinstance(response.get("statusCode"), int)
    assert isinstance(response.get("body"), str)

    response_headers = {str(key).lower(): str(value) for key, value in response.get("headers", {}).items()}
    assert "content-type" in response_headers
    assert "application/json" in response_headers["content-type"]
    return response, json.loads(response["body"])


def draft_generation_body(text: str = "Review the questionnaire and send it to Yan.") -> dict[str, Any]:
    return {
        "chatRequest": {
            "model": "gpt-4.1-mini",
            "messages": [
                {
                    "role": "system",
                    "content": "Return strict Lisdo draft JSON for user review.",
                },
                {
                    "role": "user",
                    "content": text,
                },
            ],
        }
    }


def assert_quota_snapshot(
    quota: dict[str, Any],
    *,
    plan_id: str,
    monthly_remaining: int,
    topup_remaining: int,
    monthly_consumed: int = 0,
    topup_consumed: int = 0,
    billing_source: str | None = None,
) -> None:
    expected = {
        "planId": plan_id,
        "monthlyNonRolloverRemaining": monthly_remaining,
        "topUpRolloverRemaining": topup_remaining,
        "monthlyNonRolloverConsumed": monthly_consumed,
        "topUpRolloverConsumed": topup_consumed,
    }
    actual = dict(quota)
    if billing_source is None:
        actual.pop("billingSource", None)
    else:
        expected["billingSource"] = billing_source
    assert actual == expected


def assert_draft_first_response(body: dict[str, Any]) -> None:
    assert body["draft"]["status"] == "draft"
    parsed_draft_json = assert_strict_draft_json_text(body["draftJSON"])
    assert body["draft"]["title"] == parsed_draft_json["title"]
    assert "todo" not in body
    assert "todoId" not in body
    assert "finalTodo" not in body


def assert_usage_quota_units(
    usage: dict[str, Any],
    *,
    input_tokens: int,
    output_tokens: int,
    cost_units: int,
    monthly_consumed: int,
    topup_consumed: int,
    uncovered: int = 0,
) -> None:
    assert usage["inputTokens"] == input_tokens
    assert usage["outputTokens"] == output_tokens
    assert usage["costUnits"] == cost_units
    assert usage["quotaBuckets"] == {
        "monthlyNonRollover": monthly_consumed,
        "topUpRollover": topup_consumed,
    }
    assert usage["uncoveredCostUnits"] == uncovered


def assert_strict_draft_json_text(draft_json_text: Any) -> dict[str, Any]:
    assert isinstance(draft_json_text, str)
    parsed = json.loads(draft_json_text)
    assert isinstance(parsed, dict)
    assert STRICT_DRAFT_FIELDS.issubset(parsed)
    assert isinstance(parsed["recommendedCategoryId"], str)
    assert isinstance(parsed["title"], str)
    assert isinstance(parsed["summary"], str)
    assert isinstance(parsed["blocks"], list)
    assert isinstance(parsed["needsClarification"], bool)
    assert isinstance(parsed["questionsForUser"], list)
    return parsed
