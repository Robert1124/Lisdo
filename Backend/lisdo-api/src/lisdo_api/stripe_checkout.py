from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .config import DevConfig, config_for_account
from .entitlements import normalize_plan
from .quota import (
    account_id_for_stripe_customer,
    apply_external_billing_grant,
    attach_stripe_customer,
    load_state,
    stripe_customer_id_for_account,
)

STRIPE_API_VERSION = "2026-02-25.clover"


class StripeConfigurationError(RuntimeError):
    pass


class StripeCheckoutError(ValueError):
    pass


class StripeWebhookError(ValueError):
    pass


@dataclass(frozen=True)
class StripeProduct:
    product_id: str
    mode: str
    kind: str
    plan_id: str | None
    monthly_quota: int
    topup_quota: int
    price_config_attr: str


PRODUCTS: dict[str, StripeProduct] = {
    "starterTrial": StripeProduct(
        product_id="starterTrial",
        mode="payment",
        kind="nonConsumableTrial",
        plan_id="starterTrial",
        monthly_quota=1500,
        topup_quota=0,
        price_config_attr="stripe_price_starter_trial",
    ),
    "monthlyBasic": StripeProduct(
        product_id="monthlyBasic",
        mode="subscription",
        kind="autoRenewableSubscription",
        plan_id="monthlyBasic",
        monthly_quota=3000,
        topup_quota=0,
        price_config_attr="stripe_price_monthly_basic",
    ),
    "monthlyPlus": StripeProduct(
        product_id="monthlyPlus",
        mode="subscription",
        kind="autoRenewableSubscription",
        plan_id="monthlyPlus",
        monthly_quota=12000,
        topup_quota=0,
        price_config_attr="stripe_price_monthly_plus",
    ),
    "monthlyMax": StripeProduct(
        product_id="monthlyMax",
        mode="subscription",
        kind="autoRenewableSubscription",
        plan_id="monthlyMax",
        monthly_quota=50000,
        topup_quota=0,
        price_config_attr="stripe_price_monthly_max",
    ),
    "topUpUsage": StripeProduct(
        product_id="topUpUsage",
        mode="payment",
        kind="consumableTopUp",
        plan_id=None,
        monthly_quota=0,
        topup_quota=10000,
        price_config_attr="stripe_price_top_up_usage",
    ),
}

_SECRET_CACHE: dict[str, str] = {}


def create_checkout_session(
    config: DevConfig,
    *,
    product_id: str,
    success_url: str | None = None,
    cancel_url: str | None = None,
) -> dict[str, str]:
    product = _product_for_id(product_id)
    if product.kind == "consumableTopUp" and load_state(config).next_bucket() is None:
        raise PermissionError("Top-up usage requires an active monthly plan.")

    stripe = _configured_stripe(_stripe_secret_key(config))
    metadata = {
        "accountId": config.account_id,
        "lisdoProductId": product.product_id,
    }
    session_args: dict[str, Any] = {
        "mode": product.mode,
        "line_items": [{"price": _price_id(config, product), "quantity": 1}],
        "success_url": _nonempty(success_url) or config.stripe_checkout_success_url,
        "cancel_url": _nonempty(cancel_url) or config.stripe_checkout_cancel_url,
        "client_reference_id": config.account_id,
        "metadata": metadata,
        "allow_promotion_codes": True,
        "automatic_tax": {"enabled": config.stripe_automatic_tax},
    }

    customer_id = stripe_customer_id_for_account(config)
    if customer_id is not None:
        session_args["customer"] = customer_id

    if product.mode == "subscription":
        session_args["subscription_data"] = {"metadata": metadata}
    else:
        session_args["payment_intent_data"] = {"metadata": metadata}
        if customer_id is None:
            session_args["customer_creation"] = "always"

    try:
        session = stripe.checkout.Session.create(**session_args)
    except Exception as exc:  # Stripe's SDK raises a broad StripeError hierarchy.
        raise StripeCheckoutError("Stripe Checkout session could not be created.") from exc

    session_id = _required_string(session, "id")
    session_url = _required_string(session, "url")
    return {
        "status": "created",
        "id": session_id,
        "url": session_url,
    }


def create_billing_portal_session(config: DevConfig, *, return_url: str | None = None) -> dict[str, str]:
    customer_id = stripe_customer_id_for_account(config)
    if customer_id is None:
        raise StripeCheckoutError("This account does not have Stripe billing history yet.")

    stripe = _configured_stripe(_stripe_secret_key(config))
    try:
        session = stripe.billing_portal.Session.create(
            customer=customer_id,
            return_url=_nonempty(return_url) or config.stripe_billing_portal_return_url,
        )
    except Exception as exc:
        raise StripeCheckoutError("Stripe Billing Portal session could not be created.") from exc
    return {
        "status": "created",
        "id": _required_string(session, "id"),
        "url": _required_string(session, "url"),
    }


def handle_webhook(config: DevConfig, *, payload: bytes, signature: str | None) -> dict[str, Any]:
    webhook_secret = _stripe_webhook_secret(config)
    if not signature:
        raise StripeWebhookError("Missing Stripe-Signature header.")

    stripe = _configured_stripe(_stripe_secret_key(config))
    try:
        event = stripe.Webhook.construct_event(payload, signature, webhook_secret)
    except Exception as exc:
        raise StripeWebhookError("Stripe webhook signature could not be verified.") from exc

    event_type = _required_string(event, "type")
    data = event.get("data")
    obj = data.get("object") if isinstance(data, dict) else None
    if not isinstance(obj, dict):
        raise StripeWebhookError("Stripe webhook event object is missing.")

    if event_type == "checkout.session.completed":
        return _handle_checkout_completed(config, event_type, obj)
    if event_type == "invoice.paid":
        return _handle_invoice_paid(config, event_type, obj)

    return {
        "status": "ignored",
        "eventType": event_type,
    }


def _handle_checkout_completed(config: DevConfig, event_type: str, session: dict[str, Any]) -> dict[str, Any]:
    account_id = _account_id_from_object(session)
    if account_id is None:
        raise StripeWebhookError("Stripe checkout session is missing account metadata.")
    account_config = config_for_account(config, account_id)

    customer_id = _optional_string(session, "customer")
    if customer_id is not None:
        attach_stripe_customer(account_config, customer_id)

    product_id = _metadata(session).get("lisdoProductId")
    mode = _optional_string(session, "mode")
    if mode != "payment":
        return {
            "status": "processed",
            "eventType": event_type,
            "quota": load_state(account_config).snapshot(),
        }
    if _optional_string(session, "payment_status") != "paid":
        return {
            "status": "ignored",
            "eventType": event_type,
            "reason": "payment_not_paid",
        }

    product = _product_for_id(product_id)
    state = apply_external_billing_grant(
        account_config,
        source="stripe",
        external_event_id=_required_string(session, "id"),
        product_id=product.product_id,
        product_kind=product.kind,
        plan_id=product.plan_id,
        monthly_quota=product.monthly_quota,
        topup_quota=product.topup_quota,
        customer_id=customer_id,
    )
    return {
        "status": "processed",
        "eventType": event_type,
        "quota": state.snapshot(),
    }


def _handle_invoice_paid(config: DevConfig, event_type: str, invoice: dict[str, Any]) -> dict[str, Any]:
    price_id, period_end = _invoice_price_and_period_end(invoice)
    product = _product_for_price(config, price_id)
    customer_id = _required_string(invoice, "customer")
    account_id = _metadata(invoice).get("accountId") or account_id_for_stripe_customer(config, customer_id)
    if not account_id:
        raise StripeWebhookError("Stripe invoice is missing account metadata.")
    account_config = config_for_account(config, account_id)
    attach_stripe_customer(account_config, customer_id)

    state = apply_external_billing_grant(
        account_config,
        source="stripe",
        external_event_id=_required_string(invoice, "id"),
        product_id=product.product_id,
        product_kind=product.kind,
        plan_id=product.plan_id,
        monthly_quota=product.monthly_quota,
        topup_quota=product.topup_quota,
        period_end=period_end,
        customer_id=customer_id,
        subscription_id=_optional_string(invoice, "subscription"),
    )
    return {
        "status": "processed",
        "eventType": event_type,
        "quota": state.snapshot(),
    }


def _invoice_price_and_period_end(invoice: dict[str, Any]) -> tuple[str, str | None]:
    lines = invoice.get("lines")
    line_items = lines.get("data") if isinstance(lines, dict) else None
    if not isinstance(line_items, list):
        raise StripeWebhookError("Stripe invoice is missing line items.")
    for line_item in line_items:
        if not isinstance(line_item, dict):
            continue
        price = line_item.get("price")
        price_id = price.get("id") if isinstance(price, dict) else None
        if isinstance(price_id, str) and price_id:
            period = line_item.get("period")
            period_end = period.get("end") if isinstance(period, dict) else None
            return price_id, _unix_timestamp_to_iso(period_end)
    raise StripeWebhookError("Stripe invoice line is missing a configured price.")


def _product_for_id(product_id: Any) -> StripeProduct:
    if not isinstance(product_id, str):
        raise StripeCheckoutError("A Lisdo productId is required.")
    product = PRODUCTS.get(product_id)
    if product is None:
        raise StripeCheckoutError("Stripe product is not configured for Lisdo.")
    if product.plan_id is not None and normalize_plan(product.plan_id) != product.plan_id:
        raise StripeConfigurationError("Stripe product maps to an unknown Lisdo plan.")
    return product


def _product_for_price(config: DevConfig, price_id: str) -> StripeProduct:
    for product in PRODUCTS.values():
        configured_price_id = getattr(config, product.price_config_attr)
        if isinstance(configured_price_id, str) and configured_price_id == price_id:
            return product
    raise StripeWebhookError("Stripe price is not configured for Lisdo.")


def _price_id(config: DevConfig, product: StripeProduct) -> str:
    value = getattr(config, product.price_config_attr)
    if not isinstance(value, str) or not value:
        raise StripeConfigurationError(f"Missing Stripe price for {product.product_id}.")
    return value


def _configured_stripe(secret_key: str) -> Any:
    try:
        import stripe  # type: ignore[import-not-found]
    except ImportError as exc:
        raise StripeConfigurationError("Stripe SDK is not packaged.") from exc
    stripe.api_key = secret_key
    stripe.api_version = STRIPE_API_VERSION
    return stripe


def _stripe_secret_key(config: DevConfig) -> str:
    return _secret_value(
        env_name="STRIPE_SECRET_KEY",
        parameter_name=config.stripe_secret_key_parameter_name,
        missing_message="Stripe secret key is not configured.",
    )


def _stripe_webhook_secret(config: DevConfig) -> str:
    return _secret_value(
        env_name="STRIPE_WEBHOOK_SECRET",
        parameter_name=config.stripe_webhook_secret_parameter_name,
        missing_message="Stripe webhook secret is not configured.",
    )


def _secret_value(*, env_name: str, parameter_name: str | None, missing_message: str) -> str:
    direct_value = _nonempty(os.environ.get(env_name))
    if direct_value is not None:
        return direct_value
    if parameter_name is None:
        raise StripeConfigurationError(missing_message)
    if parameter_name in _SECRET_CACHE:
        return _SECRET_CACHE[parameter_name]

    try:
        import boto3  # type: ignore[import-not-found]

        response = boto3.client("ssm").get_parameter(Name=parameter_name, WithDecryption=True)
    except Exception as exc:
        raise StripeConfigurationError("Stripe secret lookup failed.") from exc

    value = _nonempty(((response.get("Parameter") or {}).get("Value") or ""))
    if value is None:
        raise StripeConfigurationError(missing_message)
    _SECRET_CACHE[parameter_name] = value
    return value


def _metadata(obj: dict[str, Any]) -> dict[str, str]:
    metadata = obj.get("metadata")
    if not isinstance(metadata, dict):
        return {}
    return {str(key): str(value) for key, value in metadata.items() if value is not None}


def _account_id_from_object(obj: dict[str, Any]) -> str | None:
    metadata_account_id = _metadata(obj).get("accountId")
    if metadata_account_id:
        return metadata_account_id
    return _optional_string(obj, "client_reference_id")


def _required_string(obj: dict[str, Any], key: str) -> str:
    value = _optional_string(obj, key)
    if value is None:
        raise StripeWebhookError(f"Stripe object is missing {key}.")
    return value


def _optional_string(obj: dict[str, Any], key: str) -> str | None:
    value = obj.get(key)
    if isinstance(value, str) and value:
        return value
    return None


def _nonempty(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _unix_timestamp_to_iso(value: Any) -> str | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return datetime.fromtimestamp(value, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
