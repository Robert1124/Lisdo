from __future__ import annotations

import json
import hashlib
import secrets
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any
from uuid import uuid4

from .config import DevConfig
from .entitlements import is_active_monthly_plan, normalize_plan
from .storekit import StoreKitProduct

MONTHLY_BUCKET = "monthlyNonRollover"
TOPUP_BUCKET = "topUpRollover"
MAX_DISPLAY_NAME_LENGTH = 80


@dataclass
class QuotaState:
    account_id: str
    plan_id: str
    monthly_limit: int
    topup_limit: int
    monthly_consumed: int = 0
    topup_consumed: int = 0
    last_consumed_bucket: str | None = None
    last_consumptions: dict[str, int] = field(default_factory=dict)

    @property
    def monthly_remaining(self) -> int:
        return max(0, self.monthly_limit - self.monthly_consumed)

    @property
    def topup_remaining(self) -> int:
        return max(0, self.topup_limit - self.topup_consumed)

    def next_bucket(self) -> str | None:
        if self.monthly_remaining > 0:
            return MONTHLY_BUCKET
        if is_active_monthly_plan(self.plan_id) and self.topup_remaining > 0:
            return TOPUP_BUCKET
        return None

    def consume(self, bucket: str) -> None:
        if bucket == MONTHLY_BUCKET and self.monthly_remaining > 0:
            self.monthly_consumed += 1
            self.last_consumed_bucket = bucket
            self.last_consumptions = {MONTHLY_BUCKET: 1, TOPUP_BUCKET: 0}
            return
        if bucket == TOPUP_BUCKET and is_active_monthly_plan(self.plan_id) and self.topup_remaining > 0:
            self.topup_consumed += 1
            self.last_consumed_bucket = bucket
            self.last_consumptions = {MONTHLY_BUCKET: 0, TOPUP_BUCKET: 1}
            return
        raise ValueError("unknown quota bucket")

    def consume_units(self, cost_units: int) -> dict[str, int]:
        remaining_cost = max(0, cost_units)
        consumptions = {
            MONTHLY_BUCKET: 0,
            TOPUP_BUCKET: 0,
        }
        monthly_units = min(self.monthly_remaining, remaining_cost)
        if monthly_units > 0:
            self.monthly_consumed += monthly_units
            consumptions[MONTHLY_BUCKET] = monthly_units
            remaining_cost -= monthly_units

        if remaining_cost > 0 and is_active_monthly_plan(self.plan_id):
            topup_units = min(self.topup_remaining, remaining_cost)
            if topup_units > 0:
                self.topup_consumed += topup_units
                consumptions[TOPUP_BUCKET] = topup_units
                remaining_cost -= topup_units

        self.last_consumptions = consumptions
        consumed_buckets = [bucket for bucket, quantity in consumptions.items() if quantity > 0]
        self.last_consumed_bucket = consumed_buckets[-1] if consumed_buckets else None
        return consumptions

    def snapshot(self) -> dict[str, int | str]:
        return {
            "planId": self.plan_id,
            "monthlyNonRolloverRemaining": self.monthly_remaining,
            "topUpRolloverRemaining": self.topup_remaining,
            "monthlyNonRolloverConsumed": self.monthly_consumed,
            "topUpRolloverConsumed": self.topup_consumed,
        }

    def to_json(self) -> dict[str, int | str]:
        return {
            "accountId": self.account_id,
            "planId": self.plan_id,
            "monthlyNonRolloverLimit": self.monthly_limit,
            "topUpRolloverLimit": self.topup_limit,
            "monthlyNonRolloverConsumed": self.monthly_consumed,
            "topUpRolloverConsumed": self.topup_consumed,
        }


def load_state(config: DevConfig) -> QuotaState:
    if _uses_dynamodb(config):
        return _load_dynamodb_state(config)

    expected = QuotaState(
        account_id=config.account_id,
        plan_id=normalize_plan(config.plan_id),
        monthly_limit=config.monthly_quota,
        topup_limit=config.topup_quota,
    )
    path = Path(config.ledger_path)
    if not path.exists():
        return expected

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return expected

    if not _same_quota_scope(data, expected):
        return expected

    expected.monthly_consumed = _nonnegative_int(data.get("monthlyNonRolloverConsumed"))
    expected.topup_consumed = _nonnegative_int(data.get("topUpRolloverConsumed"))
    return expected


def save_state(config: DevConfig, state: QuotaState) -> None:
    if _uses_dynamodb(config):
        _save_dynamodb_state(config, state)
        return

    path = Path(config.ledger_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(state.to_json(), separators=(",", ":")), encoding="utf-8")
    tmp_path.replace(path)


def authorized_account_id_for_token(config: DevConfig, token: str) -> str | None:
    if config.env != "production" and token == config.session_token:
        return config.account_id
    if not _uses_dynamodb(config):
        return None

    table = _dynamodb_table(config)
    response = table.get_item(Key={"pk": _session_pk(token), "sk": "META"})
    item = response.get("Item")
    if not isinstance(item, dict) or item.get("kind") != "sessionIndex":
        return None
    expires_at = item.get("expiresAt")
    if isinstance(expires_at, str) and expires_at <= config.now:
        return None
    account_id = item.get("accountId")
    return account_id if isinstance(account_id, str) and account_id else None


def create_apple_account_session(
    config: DevConfig,
    *,
    account_id: str,
    apple_subject: str,
    email: str | None,
    audience: str,
    display_name: str | None = None,
) -> dict[str, Any]:
    if not _uses_dynamodb(config):
        return {
            "mode": "stub",
            "account": {
                "id": config.account_id,
                "planId": normalize_plan(config.plan_id),
            },
            "session": {
                "id": config.session_id,
                "subject": config.user_id,
                "token": config.session_token,
                "tokenType": "Bearer",
                "authenticated": True,
                "expiresAt": _session_expiration(config),
            },
        }

    table = _dynamodb_table(config)
    pk = _account_pk(account_id)
    existing_items = _query_account_items(table, pk)
    existing_account = next((item for item in existing_items if item.get("kind") == "account" and item.get("sk") == "META"), None)
    plan_id = normalize_plan(existing_account.get("planId") if existing_account else "free")
    session_id = str(uuid4())
    token = secrets.token_urlsafe(32)
    expires_at = _session_expiration(config)
    user_id = f"apple:{apple_subject}"

    account_item = dict(existing_account or {})
    account_item.update(
        {
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": plan_id,
            "userId": user_id,
            "appleSubject": apple_subject,
            "appleAudience": audience,
            "updatedAt": config.now,
        }
    )
    if email:
        account_item["email"] = email
    normalized_display_name = _normalize_display_name(display_name)
    if normalized_display_name and not _normalize_display_name(account_item.get("displayName")):
        account_item["displayName"] = normalized_display_name
    table.put_item(Item=account_item)

    session_item = {
        "pk": pk,
        "sk": f"SESSION#{session_id}",
        "kind": "session",
        "sessionId": session_id,
        "tokenHash": _token_hash(token),
        "createdAt": config.now,
        "expiresAt": expires_at,
    }
    table.put_item(Item=session_item, ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)")
    table.put_item(
        Item={
            "pk": _session_pk(token),
            "sk": "META",
            "kind": "sessionIndex",
            "accountId": account_id,
            "sessionId": session_id,
            "createdAt": config.now,
            "expiresAt": expires_at,
        },
        ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
    )

    return {
        "mode": "authenticated",
        "account": {
            "id": account_id,
            "planId": plan_id,
        },
        "session": {
            "id": session_id,
            "subject": user_id,
            "token": token,
            "tokenType": "Bearer",
            "authenticated": True,
            "expiresAt": expires_at,
        },
    }


def load_account_profile(config: DevConfig) -> dict[str, str]:
    if not _uses_dynamodb(config):
        fallback_name = _normalize_display_name(config.user_id)
        return {
            "displayName": "" if fallback_name == "dev-user" else fallback_name,
            "email": "",
        }

    table = _dynamodb_table(config)
    item = table.get_item(Key={"pk": _account_pk(config.account_id), "sk": "META"}).get("Item")
    if not isinstance(item, dict):
        item = {}
    return _profile_from_account_item(item)


def apply_storekit_transaction(config: DevConfig, transaction: dict[str, Any]) -> QuotaState:
    if not _uses_dynamodb(config):
        return load_state(config)

    product = transaction["product"]
    if not isinstance(product, StoreKitProduct):
        raise ValueError("transaction product must be a StoreKitProduct.")

    table = _dynamodb_table(config)
    pk = _account_pk(config.account_id)
    transaction_sk = f"TRANSACTION#{transaction['transactionId']}"
    existing = table.get_item(Key={"pk": pk, "sk": transaction_sk}).get("Item")
    if isinstance(existing, dict):
        return load_state(config)

    current_items = _query_account_items(table, pk)
    account_item = next((item for item in current_items if item.get("kind") == "account" and item.get("sk") == "META"), None)
    current_plan_id = normalize_plan(account_item.get("planId") if account_item else config.plan_id)

    if product.kind == "consumableTopUp" and not is_active_monthly_plan(current_plan_id):
        raise PermissionError("Top-up usage requires an active monthly plan.")

    next_plan_id = normalize_plan(product.plan_id or current_plan_id)
    _put_account_plan(table, pk, config, account_item, next_plan_id)

    if product.monthly_quota > 0:
        table.put_item(
            Item=_storekit_grant_item(
                pk,
                MONTHLY_BUCKET,
                product.monthly_quota,
                config,
                transaction,
                f"monthly#{transaction['transactionId']}",
            ),
            ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
        )

    if product.topup_quota > 0:
        table.put_item(
            Item=_storekit_grant_item(
                pk,
                TOPUP_BUCKET,
                product.topup_quota,
                config,
                transaction,
                f"topup#{transaction['transactionId']}",
            ),
            ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
        )

    table.put_item(
        Item={
            "pk": pk,
            "sk": transaction_sk,
            "kind": "storekitTransaction",
            "transactionId": transaction["transactionId"],
            "originalTransactionId": transaction["originalTransactionId"],
            "productId": transaction["productId"],
            "environment": transaction["environment"],
            "createdAt": config.now,
            "purchaseDate": transaction.get("purchaseDate"),
            "expirationDate": transaction.get("expirationDate"),
        },
        ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
    )
    return load_state(config)


def stripe_customer_id_for_account(config: DevConfig) -> str | None:
    if not _uses_dynamodb(config):
        return None
    table = _dynamodb_table(config)
    item = table.get_item(Key={"pk": _account_pk(config.account_id), "sk": "META"}).get("Item")
    if not isinstance(item, dict):
        return None
    customer_id = item.get("stripeCustomerId")
    return customer_id if isinstance(customer_id, str) and customer_id else None


def account_id_for_stripe_customer(config: DevConfig, customer_id: str) -> str | None:
    if not _uses_dynamodb(config):
        return None
    table = _dynamodb_table(config)
    item = table.get_item(Key={"pk": _stripe_customer_pk(customer_id), "sk": "META"}).get("Item")
    if not isinstance(item, dict) or item.get("kind") != "stripeCustomerIndex":
        return None
    account_id = item.get("accountId")
    return account_id if isinstance(account_id, str) and account_id else None


def attach_stripe_customer(config: DevConfig, customer_id: str) -> None:
    if not customer_id or not _uses_dynamodb(config):
        return
    table = _dynamodb_table(config)
    pk = _account_pk(config.account_id)
    account_item = table.get_item(Key={"pk": pk, "sk": "META"}).get("Item")
    if not isinstance(account_item, dict):
        account_item = None
    current_plan_id = normalize_plan(account_item.get("planId") if account_item else config.plan_id)
    updated_account = dict(account_item or {})
    updated_account["stripeCustomerId"] = customer_id
    _put_account_plan(table, pk, config, updated_account, current_plan_id)
    table.put_item(
        Item={
            "pk": _stripe_customer_pk(customer_id),
            "sk": "META",
            "kind": "stripeCustomerIndex",
            "accountId": config.account_id,
            "createdAt": config.now,
            "updatedAt": config.now,
        }
    )


def apply_external_billing_grant(
    config: DevConfig,
    *,
    source: str,
    external_event_id: str,
    product_id: str,
    product_kind: str,
    plan_id: str | None,
    monthly_quota: int,
    topup_quota: int,
    period_end: str | None = None,
    customer_id: str | None = None,
    subscription_id: str | None = None,
) -> QuotaState:
    if not _uses_dynamodb(config):
        return load_state(config)

    table = _dynamodb_table(config)
    pk = _account_pk(config.account_id)
    event_sk = f"{source.upper()}#{external_event_id}"
    if isinstance(table.get_item(Key={"pk": pk, "sk": event_sk}).get("Item"), dict):
        return load_state(config)

    current_items = _query_account_items(table, pk)
    account_item = next((item for item in current_items if item.get("kind") == "account" and item.get("sk") == "META"), None)
    current_plan_id = normalize_plan(account_item.get("planId") if account_item else config.plan_id)

    if product_kind == "consumableTopUp" and not is_active_monthly_plan(current_plan_id):
        raise PermissionError("Top-up usage requires an active monthly plan.")

    next_plan_id = normalize_plan(plan_id or current_plan_id)
    updated_account = dict(account_item or {})
    if customer_id:
        updated_account["stripeCustomerId"] = customer_id
    _put_account_plan(table, pk, config, updated_account, next_plan_id)

    if customer_id:
        table.put_item(
            Item={
                "pk": _stripe_customer_pk(customer_id),
                "sk": "META",
                "kind": "stripeCustomerIndex",
                "accountId": config.account_id,
                "createdAt": config.now,
                "updatedAt": config.now,
            }
        )

    if monthly_quota > 0:
        table.put_item(
            Item=_external_billing_grant_item(
                pk,
                MONTHLY_BUCKET,
                monthly_quota,
                source,
                config,
                product_id,
                external_event_id,
                period_end,
                customer_id,
                subscription_id,
            ),
            ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
        )

    if topup_quota > 0:
        table.put_item(
            Item=_external_billing_grant_item(
                pk,
                TOPUP_BUCKET,
                topup_quota,
                source,
                config,
                product_id,
                external_event_id,
                period_end,
                customer_id,
                subscription_id,
            ),
            ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
        )

    event_item = {
        "pk": pk,
        "sk": event_sk,
        "kind": f"{source}BillingEvent",
        "source": source,
        "externalEventId": external_event_id,
        "productId": product_id,
        "createdAt": config.now,
    }
    if customer_id:
        event_item["stripeCustomerId"] = customer_id
    if subscription_id:
        event_item["stripeSubscriptionId"] = subscription_id
    if period_end:
        event_item["periodEnd"] = period_end
    table.put_item(Item=event_item, ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)")
    return load_state(config)


def _uses_dynamodb(config: DevConfig) -> bool:
    return config.storage == "dynamodb"


def _profile_from_account_item(item: dict[str, Any]) -> dict[str, str]:
    email = item.get("email")
    display_name = _normalize_display_name(item.get("displayName"))
    if not display_name and isinstance(email, str) and "@" in email:
        display_name = email.split("@", 1)[0]
    return {
        "displayName": display_name,
        "email": email.strip() if isinstance(email, str) else "",
    }


def _normalize_display_name(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    normalized = " ".join(value.strip().split())
    return normalized[:MAX_DISPLAY_NAME_LENGTH]


def _session_expiration(config: DevConfig) -> str:
    try:
        now = datetime.fromisoformat(config.now.replace("Z", "+00:00"))
    except ValueError:
        now = datetime.now(timezone.utc)
    return (now + timedelta(days=config.session_ttl_days)).astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _session_pk(token: str) -> str:
    return f"SESSION#{_token_hash(token)}"


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _put_account_plan(
    table: Any,
    pk: str,
    config: DevConfig,
    existing_account: dict[str, Any] | None,
    plan_id: str,
) -> None:
    item = dict(existing_account or {})
    item.update(
        {
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": normalize_plan(plan_id),
            "updatedAt": config.now,
        }
    )
    item.setdefault("userId", config.user_id)
    table.put_item(Item=item)


def _storekit_grant_item(
    pk: str,
    bucket: str,
    quantity: int,
    config: DevConfig,
    transaction: dict[str, Any],
    grant_id: str,
) -> dict[str, Any]:
    item = {
        "pk": pk,
        "sk": f"GRANT#{bucket}#{grant_id}",
        "kind": "quotaGrant",
        "bucket": bucket,
        "quantity": quantity,
        "consumed": 0,
        "source": "storekit",
        "productId": transaction["productId"],
        "transactionId": transaction["transactionId"],
        "createdAt": config.now,
    }
    expiration_date = transaction.get("expirationDate")
    if isinstance(expiration_date, str) and expiration_date:
        item["periodEnd"] = expiration_date
    return item


def _external_billing_grant_item(
    pk: str,
    bucket: str,
    quantity: int,
    source: str,
    config: DevConfig,
    product_id: str,
    external_event_id: str,
    period_end: str | None,
    customer_id: str | None,
    subscription_id: str | None,
) -> dict[str, Any]:
    item = {
        "pk": pk,
        "sk": f"GRANT#{bucket}#{source}#{external_event_id}",
        "kind": "quotaGrant",
        "bucket": bucket,
        "quantity": quantity,
        "consumed": 0,
        "source": source,
        "productId": product_id,
        "externalEventId": external_event_id,
        "createdAt": config.now,
    }
    if period_end:
        item["periodEnd"] = period_end
    if customer_id:
        item["stripeCustomerId"] = customer_id
    if subscription_id:
        item["stripeSubscriptionId"] = subscription_id
    return item


def _load_dynamodb_state(config: DevConfig) -> QuotaState:
    table = _dynamodb_table(config)
    pk = _account_pk(config.account_id)
    items = _query_account_items(table, pk)
    account_item = next(
        (item for item in items if item.get("kind") == "account" and item.get("sk") == "META"),
        None,
    )
    if account_item is None and not any(item.get("kind") == "quotaGrant" for item in items):
        _seed_dynamodb_dev_account(table, config, pk)
        items = _query_account_items(table, pk)
        account_item = next(
            (item for item in items if item.get("kind") == "account" and item.get("sk") == "META"),
            None,
        )
    plan_id = normalize_plan(account_item.get("planId") if account_item else config.plan_id)
    totals: dict[str, tuple[int, int]] = {}
    for grant in _active_dynamodb_grants(items, config.now):
        bucket = grant.get("bucket")
        if bucket not in {MONTHLY_BUCKET, TOPUP_BUCKET}:
            continue
        quantity, consumed = totals.get(bucket, (0, 0))
        totals[bucket] = (
            quantity + _nonnegative_int(grant.get("quantity")),
            consumed + _nonnegative_int(grant.get("consumed")),
        )

    monthly_limit, monthly_consumed = totals.get(MONTHLY_BUCKET, (0, 0))
    topup_limit, topup_consumed = totals.get(TOPUP_BUCKET, (0, 0))
    return QuotaState(
        account_id=config.account_id,
        plan_id=plan_id,
        monthly_limit=monthly_limit,
        topup_limit=topup_limit,
        monthly_consumed=monthly_consumed,
        topup_consumed=topup_consumed,
    )


def _save_dynamodb_state(config: DevConfig, state: QuotaState) -> None:
    consumptions = {bucket: quantity for bucket, quantity in state.last_consumptions.items() if quantity > 0}
    if not consumptions and state.last_consumed_bucket is not None:
        consumptions[state.last_consumed_bucket] = 1
    if not consumptions:
        return

    table = _dynamodb_table(config)
    pk = _account_pk(config.account_id)
    for bucket, quantity in consumptions.items():
        _save_dynamodb_bucket_consumption(table, pk, config, bucket, quantity)


def _save_dynamodb_bucket_consumption(table: Any, pk: str, config: DevConfig, bucket: str, quantity: int) -> None:
    remaining_quantity = quantity
    grants = [
        grant
        for grant in _active_dynamodb_grants(_query_account_items(table, pk), config.now)
        if grant.get("bucket") == bucket
        and _nonnegative_int(grant.get("consumed")) < _nonnegative_int(grant.get("quantity"))
    ]
    for grant in sorted(grants, key=lambda item: str(item.get("sk", ""))):
        grant_remaining = _nonnegative_int(grant.get("quantity")) - _nonnegative_int(grant.get("consumed"))
        chunk = min(grant_remaining, remaining_quantity)
        if chunk <= 0:
            continue
        _increment_dynamodb_grant(table, pk, grant, bucket, chunk, config)
        _record_dynamodb_usage_event(table, pk, bucket, chunk, config)
        remaining_quantity -= chunk
        if remaining_quantity == 0:
            return

    raise RuntimeError("No quota grant available for selected bucket.")


def _increment_dynamodb_grant(
    table: Any,
    pk: str,
    grant: dict[str, Any],
    bucket: str,
    quantity: int,
    config: DevConfig,
) -> None:
    table.update_item(
        Key={"pk": pk, "sk": grant["sk"]},
        UpdateExpression="ADD #consumed :quantity",
        ConditionExpression=(
            "attribute_exists(pk) AND #kind = :kind AND #bucket = :bucket "
            "AND #consumed <= :maxConsumedBeforeIncrement "
            "AND (attribute_not_exists(#periodEnd) OR #periodEnd > :now) "
            "AND (attribute_not_exists(#expiresAt) OR #expiresAt > :now)"
        ),
        ExpressionAttributeNames={
            "#bucket": "bucket",
            "#consumed": "consumed",
            "#expiresAt": "expiresAt",
            "#kind": "kind",
            "#periodEnd": "periodEnd",
        },
        ExpressionAttributeValues={
            ":quantity": quantity,
            ":maxConsumedBeforeIncrement": max(0, _nonnegative_int(grant.get("quantity")) - quantity),
            ":kind": "quotaGrant",
            ":bucket": bucket,
            ":now": config.now,
        },
    )


def _record_dynamodb_usage_event(
    table: Any,
    pk: str,
    bucket: str,
    quantity: int,
    config: DevConfig,
) -> None:
    table.put_item(
        Item={
            "pk": pk,
            "sk": f"USAGE#{config.now}#{uuid4()}",
            "kind": "usageEvent",
            "eventType": "managedDraftGenerated",
            "bucket": bucket,
            "quantity": quantity,
            "createdAt": config.now,
        },
        ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)",
    )


def _dynamodb_table(config: DevConfig) -> Any:
    if not config.dynamodb_table_name:
        raise RuntimeError("LISDO_DYNAMODB_TABLE_NAME is required when LISDO_STORAGE=dynamodb.")

    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError("DynamoDB storage requires boto3 in the Lambda runtime.") from exc

    return boto3.resource("dynamodb").Table(config.dynamodb_table_name)


def _query_account_items(table: Any, pk: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    query_args: dict[str, Any] = {
        "KeyConditionExpression": "pk = :pk",
        "ExpressionAttributeValues": {":pk": pk},
    }
    while True:
        response = table.query(**query_args)
        items.extend(response.get("Items", []))
        last_evaluated_key = response.get("LastEvaluatedKey")
        if not last_evaluated_key:
            break
        query_args["ExclusiveStartKey"] = last_evaluated_key
    return sorted(items, key=lambda item: str(item.get("sk", "")))


def _seed_dynamodb_dev_account(table: Any, config: DevConfig, pk: str) -> None:
    table.put_item(
        Item={
            "pk": pk,
            "sk": "META",
            "kind": "account",
            "planId": normalize_plan(config.plan_id),
            "userId": config.user_id,
            "updatedAt": config.now,
        }
    )
    if config.monthly_quota > 0:
        table.put_item(Item=_seed_dynamodb_grant(pk, MONTHLY_BUCKET, config.monthly_quota, config, "dev-monthly"))
    if config.topup_quota > 0:
        table.put_item(Item=_seed_dynamodb_grant(pk, TOPUP_BUCKET, config.topup_quota, config, "dev-topup"))


def _seed_dynamodb_grant(pk: str, bucket: str, quantity: int, config: DevConfig, grant_id: str) -> dict[str, Any]:
    return {
        "pk": pk,
        "sk": f"GRANT#{bucket}#{config.now}#{grant_id}",
        "kind": "quotaGrant",
        "bucket": bucket,
        "quantity": quantity,
        "consumed": 0,
        "source": "dev",
        "createdAt": config.now,
    }


def _active_dynamodb_grants(items: list[dict[str, Any]], now: str) -> list[dict[str, Any]]:
    return [
        item
        for item in items
        if item.get("kind") == "quotaGrant" and _dynamodb_grant_is_active(item, now)
    ]


def _dynamodb_grant_is_active(item: dict[str, Any], now: str) -> bool:
    for key in ("periodEnd", "expiresAt"):
        value = item.get(key)
        if isinstance(value, str) and value <= now:
            return False
    return True


def _account_pk(account_id: str) -> str:
    normalized = account_id.strip().lower() or "dev-account"
    return f"ACCOUNT#{normalized}"


def _stripe_customer_pk(customer_id: str) -> str:
    return f"STRIPE_CUSTOMER#{customer_id.strip()}"


def _same_quota_scope(data: dict[str, Any], state: QuotaState) -> bool:
    return (
        data.get("accountId") == state.account_id
        and data.get("planId") == state.plan_id
        and data.get("monthlyNonRolloverLimit") == state.monthly_limit
        and data.get("topUpRolloverLimit") == state.topup_limit
    )


def _nonnegative_int(value: Any) -> int:
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return max(0, value)
    if isinstance(value, Decimal):
        return max(0, int(value))
    return 0
