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
    subscriptions: list[dict[str, Any]] | None = None,
    session_returns_stripe_object: bool = False,
) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []
    events = list(webhook_events or [])
    subscription_items = list(subscriptions or [])

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

    class FakeSubscription:
        @staticmethod
        def list(**kwargs: Any) -> dict[str, Any]:
            calls.append({"subscriptionList": kwargs})
            return {"data": subscription_items}

        @staticmethod
        def modify(subscription_id: str, **kwargs: Any) -> dict[str, Any]:
            calls.append({"subscriptionModify": {"id": subscription_id, **kwargs}})
            return {
                "id": subscription_id,
                "status": "active",
            }

    class FakeSubscriptionSchedule:
        @staticmethod
        def create(**kwargs: Any) -> dict[str, Any]:
            calls.append({"scheduleCreate": kwargs})
            return {"id": "sched_test_123"}

        @staticmethod
        def modify(schedule_id: str, **kwargs: Any) -> dict[str, Any]:
            calls.append({"scheduleModify": {"id": schedule_id, **kwargs}})
            return {"id": schedule_id}

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
        Subscription=FakeSubscription,
        SubscriptionSchedule=FakeSubscriptionSchedule,
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


def test_stripe_subscription_upgrade_updates_immediately_and_delta_quota_arrives_on_invoice(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyBasic",
            "userId": "test-user",
            "stripeCustomerId": "cus_upgrade",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#stripe#basic",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 3000,
            "consumed": 1800,
            "source": "stripe",
            "productId": "monthlyBasic",
            "externalEventId": "basic",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "stripeCustomerId": "cus_upgrade",
            "stripeSubscriptionId": "sub_upgrade",
        }
    )
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_upgrade",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    upgrade_invoice_event = {
        "id": "evt_upgrade_invoice_paid",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_upgrade_123",
                "customer": "cus_upgrade",
                "subscription": "sub_upgrade",
                "billing_reason": "subscription_update",
                "parent": {
                    "subscription_details": {
                        "metadata": {
                            "accountId": account_id,
                            "lisdoProductId": "monthlyMax",
                        },
                        "subscription": "sub_upgrade",
                    }
                },
                "lines": {
                    "data": [
                        {
                            "period": {"end": 1781438400},
                            "pricing": {
                                "price_details": {
                                    "price": "price_monthly_max",
                                }
                            },
                        }
                    ]
                },
            }
        },
    }
    stripe_calls = _install_fake_stripe(
        monkeypatch,
        webhook_events=[upgrade_invoice_event],
        subscriptions=[
            {
                "id": "sub_upgrade",
                "status": "active",
                "current_period_start": 1778760000,
                "current_period_end": 1781438400,
                "items": {
                    "data": [
                        {
                            "id": "si_upgrade",
                            "quantity": 1,
                            "price": {"id": "price_monthly_basic"},
                        }
                    ]
                },
            }
        ],
    )
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "monthlyPlus": "price_monthly_plus",
            "monthlyMax": "price_monthly_max",
        },
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/subscription/change",
        token="dev-token",
        body={"productId": "monthlyMax"},
    )
    webhook_response, webhook_body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=upgrade_invoice_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "upgrade_started"
    assert stripe_calls[0] == {
        "subscriptionList": {
            "customer": "cus_upgrade",
            "status": "all",
            "limit": 20,
            "expand": ["data.items.data.price"],
        }
    }
    assert stripe_calls[1] == {
        "subscriptionModify": {
            "id": "sub_upgrade",
            "items": [
                {
                    "id": "si_upgrade",
                    "price": "price_monthly_max",
                    "quantity": 1,
                }
            ],
            "metadata": {
                "accountId": account_id,
                "lisdoProductId": "monthlyMax",
            },
            "payment_behavior": "pending_if_incomplete",
            "proration_behavior": "always_invoice",
        }
    }
    assert webhook_response["statusCode"] == 200
    assert_quota_snapshot(
        webhook_body["quota"],
        plan_id="monthlyMax",
        monthly_remaining=48200,
        topup_remaining=0,
        monthly_consumed=1800,
    )

    grants = _dynamodb_items(table, kind="quotaGrant")
    assert [grant["quantity"] for grant in grants] == [3000, 47000]
    assert [grant["consumed"] for grant in grants] == [1800, 0]


def test_stripe_subscription_downgrade_is_scheduled_for_next_period(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyMax",
            "userId": "test-user",
            "stripeCustomerId": "cus_downgrade",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#stripe#max",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 50000,
            "consumed": 1200,
            "source": "stripe",
            "productId": "monthlyMax",
            "externalEventId": "max",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "stripeCustomerId": "cus_downgrade",
            "stripeSubscriptionId": "sub_downgrade",
        }
    )
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_downgrade",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    stripe_calls = _install_fake_stripe(
        monkeypatch,
        subscriptions=[
            {
                "id": "sub_downgrade",
                "status": "active",
                "items": {
                    "data": [
                        {
                            "id": "si_downgrade",
                            "quantity": 1,
                            "current_period_start": 1778760000,
                            "current_period_end": 1781438400,
                            "price": {"id": "price_monthly_max"},
                        }
                    ]
                },
            }
        ],
    )
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "monthlyPlus": "price_monthly_plus",
            "monthlyMax": "price_monthly_max",
        },
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/subscription/change",
        token="dev-token",
        body={"productId": "monthlyBasic"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "downgrade_scheduled"
    assert body["effectiveAt"] == "2026-06-14T12:00:00Z"
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyMax",
        monthly_remaining=48800,
        topup_remaining=0,
        monthly_consumed=1200,
    )
    assert stripe_calls[1] == {"scheduleCreate": {"from_subscription": "sub_downgrade"}}
    assert stripe_calls[2] == {
        "scheduleModify": {
            "id": "sched_test_123",
            "end_behavior": "release",
            "metadata": {
                "accountId": account_id,
                "lisdoProductId": "monthlyBasic",
            },
            "phases": [
                {
                    "items": [
                        {
                            "price": "price_monthly_max",
                            "quantity": 1,
                        }
                    ],
                    "start_date": 1778760000,
                    "end_date": 1781438400,
                    "proration_behavior": "none",
                },
                {
                    "items": [
                        {
                            "price": "price_monthly_basic",
                            "quantity": 1,
                        }
                    ],
                    "start_date": 1781438400,
                    "iterations": 1,
                    "proration_behavior": "none",
                    "metadata": {
                        "accountId": account_id,
                        "lisdoProductId": "monthlyBasic",
                    },
                },
            ],
        }
    }


def test_stripe_subscription_change_rejects_non_stripe_managed_monthly_plan(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyMax",
            "userId": "test-user",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#storekit#max",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 50000,
            "consumed": 0,
            "source": "storekit",
            "productId": "monthlyMax",
            "externalEventId": "max",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "originalTransactionId": "1000001",
        }
    )
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "monthlyPlus": "price_monthly_plus",
            "monthlyMax": "price_monthly_max",
        },
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/subscription/change",
        token="dev-token",
        body={"productId": "monthlyBasic"},
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_stripe_subscription_change"
    assert "not managed by Stripe" in body["error"]["message"]
    assert "App Store" in body["error"]["message"]


def test_stripe_checkout_rejects_storekit_monthly_plan_with_next_period_guidance(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyMax",
            "userId": "test-user",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#storekit#max",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 50000,
            "consumed": 0,
            "source": "storekit",
            "productId": "monthlyMax",
            "externalEventId": "max",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "originalTransactionId": "1000001",
        }
    )
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "monthlyPlus": "price_monthly_plus",
            "monthlyMax": "price_monthly_max",
        },
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/checkout/session",
        token="dev-token",
        body={"productId": "monthlyBasic"},
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_stripe_checkout"
    assert "App Store" in body["error"]["message"]
    assert "new plan starts next billing period" in body["error"]["message"]


def test_stripe_billing_portal_session_can_deep_link_to_plan_switch(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyBasic",
            "userId": "test-user",
            "stripeCustomerId": "cus_portal",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#stripe#basic",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 3000,
            "consumed": 0,
            "source": "stripe",
            "productId": "monthlyBasic",
            "externalEventId": "basic",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "stripeCustomerId": "cus_portal",
            "stripeSubscriptionId": "sub_portal",
        }
    )
    stripe_calls = _install_fake_stripe(
        monkeypatch,
        subscriptions=[
            {
                "id": "sub_portal",
                "status": "active",
                "items": {
                    "data": [
                        {
                            "id": "si_portal",
                            "price": {"id": "price_monthly_basic"},
                        }
                    ]
                },
            }
        ],
    )
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "monthlyPlus": "price_monthly_plus",
            "monthlyMax": "price_monthly_max",
        },
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/billing-portal/session",
        token="dev-token",
        body={"productId": "monthlyPlus", "returnUrl": "https://lisdo.app/account"},
    )

    assert response["statusCode"] == 200
    assert body["url"] == "https://billing.stripe.test/session/bps_test_123"
    assert stripe_calls[0] == {
        "subscriptionList": {
            "customer": "cus_portal",
            "status": "all",
            "limit": 20,
            "expand": ["data.items.data.price"],
        }
    }
    assert stripe_calls[1] == {
        "portal": {
            "customer": "cus_portal",
            "return_url": "https://lisdo.app/account",
            "flow_data": {
                "type": "subscription_update_confirm",
                "subscription_update_confirm": {
                    "subscription": "sub_portal",
                    "items": [
                        {
                            "id": "si_portal",
                            "price": "price_monthly_plus",
                            "quantity": 1,
                        }
                    ],
                },
                "after_completion": {
                    "type": "redirect",
                    "redirect": {"return_url": "https://lisdo.app/account"},
                },
            },
        }
    }


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
    assert first_body["quota"]["billingSource"] == "stripe"
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


def test_stripe_one_time_checkout_webhook_grants_topup_for_active_monthly_account(
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
        stripe_prices={
            "monthlyBasic": "price_monthly_basic",
            "topUpUsage": "price_topup",
        },
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="stripe-topup-webhook-user")},
        token=None,
    )
    account_id = auth_body["account"]["id"]
    invoice_event = {
        "id": "evt_invoice_paid_topup_base",
        "type": "invoice.paid",
        "data": {
            "object": {
                "id": "in_topup_base",
                "customer": "cus_topup",
                "subscription": "sub_topup",
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
    topup_event = {
        "id": "evt_checkout_topup_completed",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": "cs_topup_123",
                "mode": "payment",
                "payment_status": "paid",
                "customer": "cus_topup",
                "client_reference_id": account_id,
                "metadata": {
                    "accountId": account_id,
                    "lisdoProductId": "topUpUsage",
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[invoice_event, topup_event])

    invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=invoice_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )
    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=topup_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "processed"
    assert_quota_snapshot(body["quota"], plan_id="monthlyBasic", monthly_remaining=3000, topup_remaining=10000)
    table = dynamodb.Table("lisdo-test-quota")
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert [grant["bucket"] for grant in grants] == ["monthlyNonRollover", "topUpRollover"]


def test_stripe_invoice_payment_failed_is_processed_without_granting_quota(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": f"ACCOUNT#{account_id}",
            "sk": "META",
            "kind": "account",
            "planId": "monthlyBasic",
            "userId": "test-user",
            "stripeCustomerId": "cus_failed",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_failed",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    failed_event = {
        "id": "evt_invoice_failed_1",
        "type": "invoice.payment_failed",
        "data": {
            "object": {
                "id": "in_failed_1",
                "customer": "cus_failed",
                "metadata": {},
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[failed_event])
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyBasic": "price_monthly_basic"},
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=failed_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body == {
        "status": "processed",
        "eventType": "invoice.payment_failed",
        "reason": "payment_failed",
        "quota": {
            "planId": "monthlyBasic",
            "monthlyNonRolloverRemaining": 0,
            "topUpRolloverRemaining": 0,
            "monthlyNonRolloverConsumed": 0,
            "topUpRolloverConsumed": 0,
        },
    }
    assert _dynamodb_items(table, kind="quotaGrant") == []


def test_stripe_subscription_deleted_reverts_monthly_plan_but_keeps_topup_record(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    account_id = "dev-account"
    pk = f"ACCOUNT#{account_id}"
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": "monthlyBasic",
            "userId": "test-user",
            "stripeCustomerId": "cus_deleted",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#monthlyNonRollover#stripe#basic",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 3000,
            "consumed": 250,
            "source": "stripe",
            "productId": "monthlyBasic",
            "externalEventId": "basic",
            "createdAt": "2026-05-14T12:00:00Z",
            "periodEnd": "2026-06-14T12:00:00Z",
            "stripeCustomerId": "cus_deleted",
            "stripeSubscriptionId": "sub_deleted",
        }
    )
    table.put_item(
        Item={
            "pk": pk,
            "sk": "GRANT#topUpRollover#stripe#topup",
            "kind": "quotaGrant",
            "bucket": "topUpRollover",
            "quantity": 10000,
            "consumed": 0,
            "source": "stripe",
            "productId": "topUpUsage",
            "externalEventId": "topup",
            "createdAt": "2026-05-14T12:00:00Z",
            "stripeCustomerId": "cus_deleted",
        }
    )
    table.put_item(
        Item={
            "pk": "STRIPE_CUSTOMER#cus_deleted",
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": account_id,
            "createdAt": "2026-05-14T12:00:00Z",
            "updatedAt": "2026-05-14T12:00:00Z",
        }
    )
    deleted_event = {
        "id": "evt_subscription_deleted_1",
        "type": "customer.subscription.deleted",
        "data": {
            "object": {
                "id": "sub_deleted",
                "customer": "cus_deleted",
                "status": "canceled",
                "metadata": {
                    "accountId": account_id,
                    "lisdoProductId": "monthlyBasic",
                },
            }
        },
    }
    _install_fake_stripe(monkeypatch, webhook_events=[deleted_event])
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        stripe_secret_key="sk_test_lisdo",
        stripe_webhook_secret="whsec_test_lisdo",
        stripe_prices={"monthlyBasic": "price_monthly_basic"},
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/stripe/webhook",
        token=None,
        body=deleted_event,
        headers={"Stripe-Signature": "t=123,v1=fake"},
    )

    assert response["statusCode"] == 200
    assert body["status"] == "processed"
    assert body["eventType"] == "customer.subscription.deleted"
    assert body["reason"] == "subscription_inactive"
    assert_quota_snapshot(body["quota"], plan_id="free", monthly_remaining=0, topup_remaining=10000)
    assert table.items[(pk, "META")]["planId"] == "free"
    assert table.items[(pk, "GRANT#monthlyNonRollover#stripe#basic")]["expiresAt"] == "2026-05-14T12:00:00Z"


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
