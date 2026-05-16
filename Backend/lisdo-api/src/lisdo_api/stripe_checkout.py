from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .config import DevConfig, config_for_account
from .entitlements import is_active_monthly_plan, normalize_plan
from .quota import (
    account_id_for_stripe_customer,
    apply_external_billing_grant,
    attach_stripe_customer,
    load_state,
    revoke_external_monthly_entitlement,
    stripe_customer_id_for_account,
)

STRIPE_API_VERSION = "2026-02-25.clover"


class StripeConfigurationError(RuntimeError):
    pass


class StripeCheckoutError(ValueError):
    pass


class StripeWebhookError(ValueError):
    pass


NON_STRIPE_PLAN_CHANGE_MESSAGE = (
    "This plan is not managed by Stripe. If it was purchased in the App Store, "
    "cancel auto-renewal in Apple Subscriptions first. The current App Store plan "
    "stays active until this billing period ends; after it expires, subscribe on "
    "the web and the new plan starts next billing period."
)


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

MONTHLY_PRODUCT_ORDER = {
    "monthlyBasic": 1,
    "monthlyPlus": 2,
    "monthlyMax": 3,
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
    state = load_state(config)
    has_active_monthly_quota = is_active_monthly_plan(state.plan_id) and state.monthly_limit > 0
    if product.kind == "consumableTopUp" and not has_active_monthly_quota:
        raise PermissionError("Top-up usage requires an active monthly plan.")
    if product.mode == "subscription" and has_active_monthly_quota:
        if product.plan_id == state.plan_id:
            raise StripeCheckoutError("This plan is already active.")
        if state.billing_source == "storekit":
            raise StripeCheckoutError(NON_STRIPE_PLAN_CHANGE_MESSAGE)
        raise StripeCheckoutError("Use the billing portal to change an active subscription.")

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


def create_billing_portal_session(
    config: DevConfig,
    *,
    return_url: str | None = None,
    product_id: str | None = None,
) -> dict[str, str]:
    customer_id = stripe_customer_id_for_account(config)
    if customer_id is None:
        if product_id and load_state(config).billing_source == "storekit":
            raise StripeCheckoutError(NON_STRIPE_PLAN_CHANGE_MESSAGE)
        raise StripeCheckoutError("This account does not have Stripe billing history yet.")

    stripe = _configured_stripe(_stripe_secret_key(config))
    resolved_return_url = _nonempty(return_url) or config.stripe_billing_portal_return_url
    session_args: dict[str, Any] = {
        "customer": customer_id,
        "return_url": resolved_return_url,
    }
    if product_id:
        session_args["flow_data"] = _subscription_update_flow_data(
            config,
            stripe,
            customer_id,
            product_id,
            resolved_return_url,
        )
    try:
        session = stripe.billing_portal.Session.create(**session_args)
    except Exception as exc:
        raise StripeCheckoutError("Stripe Billing Portal session could not be created.") from exc
    return {
        "status": "created",
        "id": _required_string(session, "id"),
        "url": _required_string(session, "url"),
    }


def _subscription_update_flow_data(
    config: DevConfig,
    stripe: Any,
    customer_id: str,
    product_id: str,
    return_url: str,
) -> dict[str, Any]:
    target_product = _product_for_id(product_id)
    if target_product.mode != "subscription" or target_product.plan_id is None:
        raise StripeCheckoutError("Billing portal plan switch requires a monthly subscription product.")
    subscription, item = _active_monthly_subscription_item(config, stripe, customer_id)
    subscription_id = _optional_string(subscription, "id")
    item_id = _optional_string(item, "id")
    if subscription_id is None or item_id is None:
        raise StripeCheckoutError("Stripe subscription could not be loaded.")
    return {
        "type": "subscription_update_confirm",
        "subscription_update_confirm": {
            "subscription": subscription_id,
            "items": [
                {
                    "id": item_id,
                    "price": _price_id(config, target_product),
                    "quantity": 1,
                }
            ],
        },
        "after_completion": {
            "type": "redirect",
            "redirect": {"return_url": return_url},
        },
    }


def create_subscription_change(config: DevConfig, *, product_id: str) -> dict[str, Any]:
    target_product = _product_for_id(product_id)
    if target_product.mode != "subscription" or target_product.plan_id is None:
        raise StripeCheckoutError("Only monthly subscriptions can be changed this way.")

    state = load_state(config)
    if not is_active_monthly_plan(state.plan_id) or state.monthly_limit <= 0:
        raise StripeCheckoutError("This account does not have an active monthly subscription.")
    if target_product.plan_id == state.plan_id:
        return {
            "status": "already_active",
            "productId": target_product.product_id,
            "planId": target_product.plan_id,
            "quota": state.snapshot(),
        }

    current_product = _product_for_plan(state.plan_id)
    if current_product is None:
        raise StripeCheckoutError("The active plan cannot be changed through Stripe.")

    customer_id = stripe_customer_id_for_account(config)
    if customer_id is None:
        raise StripeCheckoutError(NON_STRIPE_PLAN_CHANGE_MESSAGE)

    stripe = _configured_stripe(_stripe_secret_key(config))
    subscription, item = _active_monthly_subscription_item(config, stripe, customer_id)
    subscription_id = _required_string(subscription, "id")
    item_id = _required_string(item, "id")
    quantity = _subscription_item_quantity(item)
    metadata = {
        "accountId": config.account_id,
        "lisdoProductId": target_product.product_id,
    }

    if _monthly_rank(target_product) > _monthly_rank(current_product):
        try:
            updated_subscription = stripe.Subscription.modify(
                subscription_id,
                items=[
                    {
                        "id": item_id,
                        "price": _price_id(config, target_product),
                        "quantity": quantity,
                    }
                ],
                metadata=metadata,
                payment_behavior="pending_if_incomplete",
                proration_behavior="always_invoice",
            )
        except Exception as exc:
            raise StripeCheckoutError("Stripe subscription upgrade could not be started.") from exc
        return {
            "status": "upgrade_started",
            "productId": target_product.product_id,
            "planId": target_product.plan_id,
            "subscriptionId": _required_string(updated_subscription, "id"),
            "quota": state.snapshot(),
        }

    effective_at = _subscription_period_end(subscription, item)
    if effective_at is None:
        raise StripeCheckoutError("Stripe subscription is missing its current period end.")
    schedule_id = _subscription_schedule_id(subscription)
    try:
        if schedule_id is None:
            schedule = stripe.SubscriptionSchedule.create(from_subscription=subscription_id)
            schedule_id = _required_string(schedule, "id")
        scheduled = stripe.SubscriptionSchedule.modify(
            schedule_id,
            end_behavior="release",
            metadata=metadata,
            phases=[
                {
                    "items": [
                        {
                            "price": _price_id(config, current_product),
                            "quantity": quantity,
                        }
                    ],
                    "start_date": _subscription_period_start(subscription, item) or "now",
                    "end_date": effective_at,
                    "proration_behavior": "none",
                },
                {
                    "items": [
                        {
                            "price": _price_id(config, target_product),
                            "quantity": quantity,
                        }
                    ],
                    "start_date": effective_at,
                    "iterations": 1,
                    "proration_behavior": "none",
                    "metadata": metadata,
                },
            ],
        )
    except Exception as exc:
        raise StripeCheckoutError("Stripe subscription downgrade could not be scheduled.") from exc

    return {
        "status": "downgrade_scheduled",
        "productId": target_product.product_id,
        "planId": target_product.plan_id,
        "subscriptionScheduleId": _required_string(scheduled, "id"),
        "effectiveAt": _unix_timestamp_to_iso(effective_at) or str(effective_at),
        "quota": state.snapshot(),
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

    event_id = _required_string(event, "id")
    event_type = _required_string(event, "type")
    data = _object_value(event, "data")
    obj = _object_value(data, "object")
    if obj is None:
        raise StripeWebhookError("Stripe webhook event object is missing.")

    if event_type == "checkout.session.completed":
        return _handle_checkout_completed(config, event_type, obj)
    if event_type in {"invoice.paid", "invoice.payment_succeeded"}:
        return _handle_invoice_paid(config, event_type, obj)
    if event_type == "invoice.payment_failed":
        return _handle_invoice_payment_failed(config, event_type, obj)
    if event_type in {"customer.subscription.deleted", "customer.subscription.updated"}:
        return _handle_subscription_lifecycle(config, event_type, event_id, obj)

    return {
        "status": "ignored",
        "eventType": event_type,
    }


def _handle_checkout_completed(config: DevConfig, event_type: str, session: Any) -> dict[str, Any]:
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


def _handle_invoice_paid(config: DevConfig, event_type: str, invoice: Any) -> dict[str, Any]:
    product, period_end = _invoice_product_and_period_end(config, invoice)
    customer_id = _required_string(invoice, "customer")
    account_id = _account_id_from_invoice(config, invoice, customer_id)
    if not account_id:
        raise StripeWebhookError("Stripe invoice is missing account metadata.")
    account_config = config_for_account(config, account_id)
    attach_stripe_customer(account_config, customer_id)
    monthly_quota = product.monthly_quota
    if _optional_string(invoice, "billing_reason") == "subscription_update" and product.kind == "autoRenewableSubscription":
        current_state = load_state(account_config)
        monthly_quota = max(0, product.monthly_quota - current_state.monthly_limit)

    state = apply_external_billing_grant(
        account_config,
        source="stripe",
        external_event_id=_required_string(invoice, "id"),
        product_id=product.product_id,
        product_kind=product.kind,
        plan_id=product.plan_id,
        monthly_quota=monthly_quota,
        topup_quota=product.topup_quota,
        period_end=period_end,
        customer_id=customer_id,
        subscription_id=_subscription_id_from_invoice(invoice),
    )
    return {
        "status": "processed",
        "eventType": event_type,
        "quota": state.snapshot(),
    }


def _handle_invoice_payment_failed(config: DevConfig, event_type: str, invoice: Any) -> dict[str, Any]:
    customer_id = _required_string(invoice, "customer")
    account_id = _metadata(invoice).get("accountId") or account_id_for_stripe_customer(config, customer_id)
    if not account_id:
        return {
            "status": "ignored",
            "eventType": event_type,
            "reason": "unknown_customer",
        }
    state = load_state(config_for_account(config, account_id))
    return {
        "status": "processed",
        "eventType": event_type,
        "reason": "payment_failed",
        "quota": state.snapshot(),
    }


def _handle_subscription_lifecycle(
    config: DevConfig,
    event_type: str,
    event_id: str,
    subscription: Any,
) -> dict[str, Any]:
    customer_id = _required_string(subscription, "customer")
    account_id = _metadata(subscription).get("accountId") or account_id_for_stripe_customer(config, customer_id)
    if not account_id:
        return {
            "status": "ignored",
            "eventType": event_type,
            "reason": "unknown_customer",
        }
    account_config = config_for_account(config, account_id)
    status = _optional_string(subscription, "status")
    subscription_id = _required_string(subscription, "id")
    inactive_statuses = {"canceled", "unpaid", "incomplete_expired"}
    should_revoke = event_type == "customer.subscription.deleted" or status in inactive_statuses
    if should_revoke:
        state = revoke_external_monthly_entitlement(
            account_config,
            source="stripe",
            external_event_id=event_id,
            reason="subscription_inactive",
            customer_id=customer_id,
            subscription_id=subscription_id,
        )
        return {
            "status": "processed",
            "eventType": event_type,
            "reason": "subscription_inactive",
            "quota": state.snapshot(),
        }

    return {
        "status": "processed",
        "eventType": event_type,
        "reason": "subscription_active",
        "quota": load_state(account_config).snapshot(),
    }


def _invoice_product_and_period_end(config: DevConfig, invoice: Any) -> tuple[StripeProduct, str | None]:
    metadata_product_id = _product_id_from_invoice_metadata(invoice)
    if metadata_product_id is not None:
        product = PRODUCTS.get(metadata_product_id)
        if product is not None:
            return product, _invoice_period_end(invoice)

    price_id, period_end = _invoice_price_and_period_end(invoice)
    return _product_for_price(config, price_id), period_end


def _product_id_from_invoice_metadata(invoice: Any) -> str | None:
    for metadata in _invoice_metadata_candidates(invoice):
        product_id = metadata.get("lisdoProductId")
        if product_id:
            return product_id
    return None


def _invoice_price_and_period_end(invoice: Any) -> tuple[str, str | None]:
    for line_item in _invoice_line_items(invoice):
        price_id = _price_id_from_invoice_line(line_item)
        if price_id is not None:
            period = _object_value(line_item, "period")
            period_end = _object_value(period, "end")
            return price_id, _unix_timestamp_to_iso(period_end)
    raise StripeWebhookError("Stripe invoice line is missing a configured price.")


def _invoice_period_end(invoice: Any) -> str | None:
    for line_item in _invoice_line_items(invoice):
        period = _object_value(line_item, "period")
        period_end = _unix_timestamp_to_iso(_object_value(period, "end"))
        if period_end is not None:
            return period_end
    return None


def _invoice_line_items(invoice: Any) -> list[Any]:
    lines = _object_value(invoice, "lines")
    line_items = _object_value(lines, "data")
    if not isinstance(line_items, list):
        raise StripeWebhookError("Stripe invoice is missing line items.")
    return [line_item for line_item in line_items if line_item is not None]


def _price_id_from_invoice_line(line_item: Any) -> str | None:
    price = _object_value(line_item, "price")
    if isinstance(price, str) and price:
        return price
    price_id = _object_value(price, "id")
    if isinstance(price_id, str) and price_id:
        return price_id

    pricing = _object_value(line_item, "pricing")
    price_details = _object_value(pricing, "price_details")
    pricing_price_id = _object_value(price_details, "price")
    if isinstance(pricing_price_id, str) and pricing_price_id:
        return pricing_price_id
    return None


def _account_id_from_invoice(config: DevConfig, invoice: Any, customer_id: str) -> str | None:
    for metadata in _invoice_metadata_candidates(invoice):
        account_id = metadata.get("accountId")
        if account_id:
            return account_id
    return account_id_for_stripe_customer(config, customer_id)


def _invoice_metadata_candidates(invoice: Any) -> list[dict[str, str]]:
    candidates = [_metadata(invoice)]

    parent = _object_value(invoice, "parent")
    subscription_details = _object_value(parent, "subscription_details")
    candidates.append(_metadata(subscription_details))

    for line_item in _invoice_line_items(invoice):
        candidates.append(_metadata(line_item))
    return candidates


def _subscription_id_from_invoice(invoice: Any) -> str | None:
    subscription_id = _optional_string(invoice, "subscription")
    if subscription_id is not None:
        return subscription_id

    parent = _object_value(invoice, "parent")
    subscription_details = _object_value(parent, "subscription_details")
    subscription_id = _optional_string(subscription_details, "subscription")
    if subscription_id is not None:
        return subscription_id

    for line_item in _invoice_line_items(invoice):
        line_parent = _object_value(line_item, "parent")
        item_details = _object_value(line_parent, "subscription_item_details")
        subscription_id = _optional_string(item_details, "subscription")
        if subscription_id is not None:
            return subscription_id
    return None


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


def _product_for_plan(plan_id: str) -> StripeProduct | None:
    normalized_plan = normalize_plan(plan_id)
    for product in PRODUCTS.values():
        if product.plan_id == normalized_plan:
            return product
    return None


def _monthly_rank(product: StripeProduct) -> int:
    return MONTHLY_PRODUCT_ORDER.get(product.product_id, 0)


def _price_id(config: DevConfig, product: StripeProduct) -> str:
    value = getattr(config, product.price_config_attr)
    if not isinstance(value, str) or not value:
        raise StripeConfigurationError(f"Missing Stripe price for {product.product_id}.")
    return value


def _active_monthly_subscription_item(config: DevConfig, stripe: Any, customer_id: str) -> tuple[Any, Any]:
    configured_monthly_prices = {
        _price_id(config, product)
        for product in PRODUCTS.values()
        if product.mode == "subscription"
    }
    try:
        subscriptions = stripe.Subscription.list(
            customer=customer_id,
            status="all",
            limit=20,
            expand=["data.items.data.price"],
        )
    except Exception as exc:
        raise StripeCheckoutError("Stripe subscription could not be loaded.") from exc

    for subscription in _object_list(subscriptions, "data"):
        if _optional_string(subscription, "status") not in {"active", "trialing", "past_due", "unpaid"}:
            continue
        items = _object_value(subscription, "items")
        for item in _object_list(items, "data"):
            price_id = _price_id_from_subscription_item(item)
            if price_id in configured_monthly_prices:
                return subscription, item
    raise StripeCheckoutError(NON_STRIPE_PLAN_CHANGE_MESSAGE)


def _price_id_from_subscription_item(item: Any) -> str | None:
    price = _object_value(item, "price")
    if isinstance(price, str) and price:
        return price
    price_id = _object_value(price, "id")
    return price_id if isinstance(price_id, str) and price_id else None


def _subscription_item_quantity(item: Any) -> int:
    quantity = _object_value(item, "quantity")
    if isinstance(quantity, bool):
        return 1
    if isinstance(quantity, int) and quantity > 0:
        return quantity
    return 1


def _subscription_period_start(subscription: Any, item: Any | None = None) -> Any:
    return _object_value(subscription, "current_period_start") or _object_value(item, "current_period_start")


def _subscription_period_end(subscription: Any, item: Any | None = None) -> Any:
    return _object_value(subscription, "current_period_end") or _object_value(item, "current_period_end")


def _subscription_schedule_id(subscription: Any) -> str | None:
    schedule = _object_value(subscription, "schedule")
    if isinstance(schedule, str) and schedule:
        return schedule
    schedule_id = _object_value(schedule, "id")
    return schedule_id if isinstance(schedule_id, str) and schedule_id else None


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


def _metadata(obj: Any) -> dict[str, str]:
    metadata = _object_value(obj, "metadata")
    if isinstance(metadata, dict):
        metadata_values = metadata
    elif hasattr(metadata, "_to_dict_recursive"):
        metadata_values = metadata._to_dict_recursive()
    else:
        return {}
    return {str(key): str(value) for key, value in metadata_values.items() if value is not None}


def _account_id_from_object(obj: Any) -> str | None:
    metadata_account_id = _metadata(obj).get("accountId")
    if metadata_account_id:
        return metadata_account_id
    return _optional_string(obj, "client_reference_id")


def _required_string(obj: Any, key: str) -> str:
    value = _optional_string(obj, key)
    if value is None:
        raise StripeWebhookError(f"Stripe object is missing {key}.")
    return value


def _optional_string(obj: Any, key: str) -> str | None:
    value = _object_value(obj, key)
    if isinstance(value, str) and value:
        return value
    return None


def _object_value(obj: Any, key: str) -> Any:
    if isinstance(obj, dict):
        return obj.get(key)
    if obj is None:
        return None
    try:
        return obj[key]
    except (AttributeError, KeyError, TypeError):
        return None


def _object_list(obj: Any, key: str) -> list[Any]:
    values = _object_value(obj, key)
    if isinstance(values, list):
        return [value for value in values if value is not None]
    return []


def _nonempty(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _unix_timestamp_to_iso(value: Any) -> str | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return datetime.fromtimestamp(value, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
