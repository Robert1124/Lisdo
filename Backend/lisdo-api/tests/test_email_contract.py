from __future__ import annotations

import json
import sys
from typing import Any

from conftest import invoke, unsigned_apple_identity_token
from test_quota_contract import _install_fake_boto3
from test_stripe_checkout_contract import _install_fake_stripe


class _FakeResendResponse:
    status = 200

    def __enter__(self) -> "_FakeResendResponse":
        return self

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        return None

    def read(self) -> bytes:
        return b'{"id":"email_test_123"}'


def _install_fake_resend(monkeypatch) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []

    def fake_urlopen(request: Any, timeout: float) -> _FakeResendResponse:
        calls.append(
            {
                "url": request.full_url,
                "headers": dict(request.header_items()),
                "body": json.loads(request.data.decode("utf-8")),
                "timeout": timeout,
            }
        )
        return _FakeResendResponse()

    email_module = sys.modules["lisdo_api.email"]
    monkeypatch.setattr(email_module.urllib.request, "urlopen", fake_urlopen)
    return calls


def _enable_email(monkeypatch) -> None:
    monkeypatch.setenv("RESEND_API_KEY", "re_test_lisdo")
    monkeypatch.setenv("LISDO_EMAIL_FROM", "Lisdo <hello@lisdo.test>")
    monkeypatch.setenv("LISDO_APP_BASE_URL", "https://lisdo.test/account.html")
    monkeypatch.setenv("LISDO_EMAILS_ENABLED", "true")


def test_auth_apple_sends_welcome_email_for_new_account(load_lambda_handler, monkeypatch) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    _enable_email(monkeypatch)
    resend_calls = _install_fake_resend(monkeypatch)

    response, body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={
            "identityToken": unsigned_apple_identity_token(
                subject="welcome-user",
                email="welcome@example.com",
            ),
            "displayName": "Welcome User",
        },
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["email"]["welcome"] == "sent"
    assert len(resend_calls) == 1
    call = resend_calls[0]
    assert call["url"] == "https://api.resend.com/emails"
    assert call["headers"]["Authorization"] == "Bearer re_test_lisdo"
    assert call["headers"]["User-agent"] == "lisdo-api/1.0"
    assert call["headers"]["Idempotency-key"].startswith("welcome:")
    assert call["body"]["from"] == "Lisdo <hello@lisdo.test>"
    assert call["body"]["to"] == ["welcome@example.com"]
    assert call["body"]["subject"] == "Welcome to Lisdo"
    assert "Welcome User" in call["body"]["html"]
    assert "Capture now, review before saving" in call["body"]["html"]
    assert "border-radius: 28px" in call["body"]["html"]


def test_auth_apple_does_not_resend_welcome_for_existing_account(load_lambda_handler, monkeypatch) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    _enable_email(monkeypatch)
    resend_calls = _install_fake_resend(monkeypatch)
    body = {
        "identityToken": unsigned_apple_identity_token(
            subject="existing-welcome-user",
            email="existing@example.com",
        )
    }

    invoke(handler, "POST", "/v1/auth/apple", body=body, token=None)
    response, response_body = invoke(handler, "POST", "/v1/auth/apple", body=body, token=None)

    assert response["statusCode"] == 200
    assert response_body["email"]["welcome"] == "skipped_existing_account"
    assert len(resend_calls) == 1


def test_stripe_invoice_paid_sends_purchase_email_with_invoice(load_lambda_handler, monkeypatch) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    invoice_event = {
        "id": "evt_invoice_purchase",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_purchase",
                "customer": "cus_purchase_email",
                "billing_reason": "subscription_create",
                "hosted_invoice_url": "https://stripe.test/invoice/in_purchase",
                "invoice_pdf": "https://stripe.test/invoice/in_purchase.pdf",
                "parent": {
                    "subscription_details": {
                        "subscription": "sub_purchase_email",
                        "metadata": {},
                    }
                },
                "lines": {
                    "data": [
                        {
                            "price": {"id": "price_monthly_basic"},
                            "period": {"end": 1781438400},
                            "amount": 499,
                        }
                    ]
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[invoice_event])
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyBasic": "price_monthly_basic"},
    )
    _enable_email(monkeypatch)
    resend_calls = _install_fake_resend(monkeypatch)
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="invoice-email-user", email="invoice@example.com")},
        token=None,
    )
    account_id = auth_body["account"]["id"]
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_purchase_email",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    resend_calls.clear()

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        body=invoice_event,
        headers={"stripe-signature": "sig_test"},
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["email"]["receipt"] == "sent"
    assert len(resend_calls) == 1
    payload = resend_calls[0]["body"]
    assert payload["to"] == ["invoice@example.com"]
    assert payload["subject"] == "Lisdo purchase receipt"
    assert "Monthly Basic" in payload["html"]
    assert "View invoice" in payload["html"]
    assert "https://stripe.test/invoice/in_purchase" in payload["html"]
    assert payload["attachments"] == [
        {
            "filename": "Lisdo-invoice-in_purchase.pdf",
            "path": "https://stripe.test/invoice/in_purchase.pdf",
        }
    ]


def test_stripe_subscription_cycle_sends_renewal_email(load_lambda_handler, monkeypatch) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    renewal_event = {
        "id": "evt_invoice_renewal",
        "type": "invoice.paid",
        "data": {
            "object": {
                "id": "in_renewal",
                "customer": "cus_renewal_email",
                "billing_reason": "subscription_cycle",
                "hosted_invoice_url": "https://stripe.test/invoice/in_renewal",
                "parent": {
                    "subscription_details": {
                        "subscription": "sub_renewal_email",
                        "metadata": {},
                    }
                },
                "lines": {
                    "data": [
                        {
                            "price": {"id": "price_monthly_max"},
                            "period": {"end": 1781438400},
                            "amount": 1499,
                        }
                    ]
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[renewal_event])
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyMax": "price_monthly_max"},
    )
    _enable_email(monkeypatch)
    resend_calls = _install_fake_resend(monkeypatch)
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="renewal-email-user", email="renewal@example.com")},
        token=None,
    )
    account_id = auth_body["account"]["id"]
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_renewal_email",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    resend_calls.clear()

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        body=renewal_event,
        headers={"stripe-signature": "sig_test"},
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["email"]["receipt"] == "sent"
    assert resend_calls[0]["body"]["subject"] == "Lisdo renewal receipt"
    assert "Monthly Max renewed" in resend_calls[0]["body"]["html"]
