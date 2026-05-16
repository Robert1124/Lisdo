from __future__ import annotations

import json
import sys
import types
from typing import Any

from conftest import assert_quota_snapshot, invoke, unsigned_apple_identity_token
from test_quota_contract import _dynamodb_items, _install_fake_boto3


class _FakeStripeError(Exception):
    pass


class _FakeStripeSignatureError(Exception):
    pass


class _FakeStripeObject:
    def __init__(self, values: dict[str, Any]) -> None:
        self._values = values

    def __getitem__(self, key: str) -> Any:
        return self._values[key]


def _install_fake_stripe(
    monkeypatch,
    *,
    webhook_events: list[dict[str, Any]] | None = None,
    session_returns_stripe_object: bool = False,
) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []
    events = list(webhook_events or [])

    class FakeSession:
        @staticmethod
        def create(**kwargs: Any) -> dict[str, Any] | _FakeStripeObject:
            calls.append(kwargs)
            session = {
                "id": "cs_test_123",
                "url": "https://checkout.stripe.test/cs_test_123",
            }
            if session_returns_stripe_object:
                return _FakeStripeObject(session)
            return session

    class FakePortalSession:
        @staticmethod
        def create(**kwargs: Any) -> dict[str, Any]:
            calls.append({"portal": kwargs})
            return {
                "id": "bps_test_123",
                "url": "https://billing.stripe.test/session/bps_test_123",
            }

    class FakeWebhook:
        @staticmethod
        def construct_event(payload: bytes | str, sig_header: str, secret: str) -> dict[str, Any]:
            calls.append({"webhookPayload": payload, "stripeSignature": sig_header, "webhookSecret": secret})
            if not events:
                raise _FakeStripeSignatureError("missing fake event")
            return events.pop(0)

    fake_stripe = types.SimpleNamespace(
        api_key=None,
        api_version=None,
        checkout=types.SimpleNamespace(Session=FakeSession),
        billing_portal=types.SimpleNamespace(Session=FakePortalSession),
        Webhook=FakeWebhook,
        error=types.SimpleNamespace(
            StripeError=_FakeStripeError,
            SignatureVerificationError=_FakeStripeSignatureError,
        ),
    )
    monkeypatch.setitem(sys.modules, "stripe", fake_stripe)
    return calls


def test_stripe_checkout_session_uses_account_session_and_price_metadata(load_lambda_handler, monkeypatch) -> None:
    _install_fake_boto3(monkeypatch)
    stripe_calls = _install_fake_stripe(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={"monthlyBasic": "price_monthly_basic"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-checkout-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/checkout/session",
        token=auth_body["session"]["token"],
        body={"productId": "monthlyBasic"},
    )

    assert response["statusCode"] == 200
    assert body == {
        "status": "created",
        "id": "cs_test_123",
        "url": "https://checkout.stripe.test/cs_test_123",
    }
    assert stripe_calls == [
        {
            "mode": "subscription",
            "line_items": [{"price": "price_monthly_basic", "quantity": 1}],
            "success_url": "https://lisdo.test/billing/success",
            "cancel_url": "https://lisdo.test/billing/cancel",
            "client_reference_id": auth_body["account"]["id"],
            "metadata": {
                "accountId": auth_body["account"]["id"],
                "lisdoProductId": "monthlyBasic",
            },
            "subscription_data": {
                "metadata": {
                    "accountId": auth_body["account"]["id"],
                    "lisdoProductId": "monthlyBasic",
                }
            },
            "allow_promotion_codes": True,
            "automatic_tax": {"enabled": True},
        }
    ]


def test_stripe_checkout_session_accepts_stripe_sdk_object_response(load_lambda_handler, monkeypatch) -> None:
    _install_fake_boto3(monkeypatch)
    _install_fake_stripe(monkeypatch, session_returns_stripe_object=True)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={"monthlyMax": "price_monthly_max"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-object-checkout-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/checkout/session",
        token=auth_body["session"]["token"],
        body={"productId": "monthlyMax"},
    )

    assert response["statusCode"] == 200
    assert body == {
        "status": "created",
        "id": "cs_test_123",
        "url": "https://checkout.stripe.test/cs_test_123",
    }


def test_stripe_topup_checkout_requires_active_monthly_plan(load_lambda_handler, monkeypatch) -> None:
    _install_fake_boto3(monkeypatch)
    _install_fake_stripe(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={"topUpUsage": "price_topup"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-free-topup-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/checkout/session",
        token=auth_body["session"]["token"],
        body={"productId": "topUpUsage"},
    )

    assert response["statusCode"] == 402
    assert body["error"]["code"] == "topup_requires_monthly_plan"


def test_stripe_checkout_does_not_create_duplicate_active_monthly_subscription(
    load_lambda_handler,
    monkeypatch,
) -> None:
    _install_fake_boto3(monkeypatch)
    stripe_calls = _install_fake_stripe(monkeypatch)
    handler = load_lambda_handler(
        plan="monthlyMax",
        monthly_quota=50,
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={"monthlyMax": "price_monthly_max"},
    )
    invoke(handler, "GET", "/v1/quota", token="dev-token")

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/checkout/session",
        token="dev-token",
        body={"productId": "monthlyMax"},
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_stripe_checkout"
    assert "already active" in body["error"]["message"]
    assert stripe_calls == []


def test_stripe_subscription_invoice_webhook_grants_plan_quota_and_is_idempotent(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyBasic": "price_monthly_basic"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-webhook-user")},
        token=None,
    )
    account_id = auth_body["account"]["id"]
    webhook_event = {
        "id": "evt_invoice_paid_1",
        "type": "invoice.paid",
        "data": {
            "object": {
                "id": "in_123",
                "customer": "cus_123",
                "subscription": "sub_123",
                "metadata": {"accountId": account_id},
                "lines": {
                    "data": [
                        {
                            "price": {"id": "price_monthly_basic"},
                            "period": {"end": 1781438400},
                        }
                    ]
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[webhook_event, webhook_event])

    first_response, first_body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=webhook_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )
    replay_response, replay_body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=webhook_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert first_response["statusCode"] == 200
    assert first_body["status"] == "processed"
    assert first_body["eventType"] == "invoice.paid"
    assert_quota_snapshot(first_body["quota"], plan_id="monthlyBasic", monthly_remaining=3000, topup_remaining=0)
    assert replay_response["statusCode"] == 200
    assert replay_body["quota"] == first_body["quota"]

    table = dynamodb.Table("lisdo-test-quota")
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert len(grants) == 1
    assert grants[0]["source"] == "stripe"
    assert grants[0]["periodEnd"] == "2026-06-14T12:00:00Z"


def test_stripe_subscription_invoice_webhook_accepts_current_invoice_shape(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyMax": "price_monthly_max"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-current-invoice-user")},
        token=None,
    )
    account_id = auth_body["account"]["id"]
    webhook_event = {
        "id": "evt_invoice_payment_succeeded_1",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_2026_123",
                "customer": "cus_2026",
                "metadata": {},
                "parent": {
                    "subscription_details": {
                        "metadata": {
                            "accountId": account_id,
                            "lisdoProductId": "monthlyMax",
                        },
                        "subscription": "sub_2026",
                    },
                    "type": "subscription_details",
                },
                "lines": {
                    "data": [
                        {
                            "metadata": {
                                "accountId": account_id,
                                "lisdoProductId": "monthlyMax",
                            },
                            "period": {"end": 1781438400},
                            "pricing": {
                                "price_details": {
                                    "price": "price_monthly_max",
                                    "product": "prod_monthly_max",
                                },
                                "type": "price_details",
                            },
                            "parent": {
                                "subscription_item_details": {
                                    "subscription": "sub_2026",
                                    "subscription_item": "si_2026",
                                },
                                "type": "subscription_item_details",
                            },
                        }
                    ]
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[webhook_event])

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=webhook_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "processed"
    assert body["eventType"] == "invoice.payment_succeeded"
    assert_quota_snapshot(body["quota"], plan_id="monthlyMax", monthly_remaining=50000, topup_remaining=0)
    table = dynamodb.Table("lisdo-test-quota")
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert len(grants) == 1
    assert grants[0]["stripeSubscriptionId"] == "sub_2026"
    assert grants[0]["periodEnd"] == "2026-06-14T12:00:00Z"


def test_stripe_one_time_checkout_webhook_grants_starter_trial(load_lambda_handler, monkeypatch) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"starterTrial": "price_starter_trial"},
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-starter-user")},
        token=None,
    )
    webhook_event = {
        "id": "evt_checkout_completed_1",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": "cs_starter_123",
                "mode": "payment",
                "payment_status": "paid",
                "customer": "cus_starter",
                "client_reference_id": auth_body["account"]["id"],
                "metadata": {
                    "accountId": auth_body["account"]["id"],
                    "lisdoProductId": "starterTrial",
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[webhook_event])

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=webhook_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "processed"
    assert_quota_snapshot(body["quota"], plan_id="starterTrial", monthly_remaining=1500, topup_remaining=0)
    table = dynamodb.Table("lisdo-test-quota")
    account_item = table.items[(f"ACCOUNT#{auth_body['account']['id']}", "META")]
    assert account_item["stripeCustomerId"] == "cus_starter"
    assert table.items[("STRIPE_CUSTOMER#cus_starter", "META")]["accountId"] == auth_body["account"]["id"]
