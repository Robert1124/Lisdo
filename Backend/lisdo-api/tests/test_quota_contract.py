from __future__ import annotations

import json
import sys
import types
from typing import Any

import pytest

from conftest import (
    assert_draft_first_response,
    assert_quota_snapshot,
    assert_usage_quota_units,
    draft_generation_body,
    install_fake_app_store_server_library,
    invoke,
    unsigned_apple_identity_token,
    unsigned_storekit_transaction_jws,
)


class _FakeDynamoTable:
    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict[str, Any]] = {}

    def query(self, **kwargs: Any) -> dict[str, Any]:
        expression_values = kwargs["ExpressionAttributeValues"]
        pk = expression_values[":pk"]
        items = [dict(item) for (item_pk, _), item in self.items.items() if item_pk == pk]
        return {"Items": sorted(items, key=lambda item: item["sk"])}

    def put_item(self, **kwargs: Any) -> dict[str, Any]:
        item = dict(kwargs["Item"])
        key = (item["pk"], item["sk"])
        if kwargs.get("ConditionExpression") == "attribute_not_exists(pk) AND attribute_not_exists(sk)":
            if key in self.items:
                raise RuntimeError("conditional put failed")
        self.items[key] = item
        return {}

    def get_item(self, **kwargs: Any) -> dict[str, Any]:
        key = (kwargs["Key"]["pk"], kwargs["Key"]["sk"])
        item = self.items.get(key)
        return {"Item": dict(item)} if item is not None else {}

    def update_item(self, **kwargs: Any) -> dict[str, Any]:
        key = (kwargs["Key"]["pk"], kwargs["Key"]["sk"])
        item = self.items[key]
        values = kwargs["ExpressionAttributeValues"]
        assert values[":kind"] == "quotaGrant"
        assert item["kind"] == values[":kind"]
        assert item["bucket"] == values[":bucket"]
        assert item["consumed"] < item["quantity"]
        item["consumed"] += values[":quantity"]
        assert item["consumed"] <= item["quantity"]
        return {}


class _FakeDynamoResource:
    def __init__(self) -> None:
        self.tables: dict[str, _FakeDynamoTable] = {}

    def Table(self, table_name: str) -> _FakeDynamoTable:
        return self.tables.setdefault(table_name, _FakeDynamoTable())


def _install_fake_boto3(monkeypatch) -> _FakeDynamoResource:
    resource = _FakeDynamoResource()
    fake_boto3 = types.SimpleNamespace(resource=lambda service, region_name=None: resource)
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)
    return resource


def _dynamodb_items(table: _FakeDynamoTable, *, kind: str | None = None) -> list[dict[str, Any]]:
    items = sorted(table.items.values(), key=lambda item: item["sk"])
    if kind is None:
        return items
    return [item for item in items if item["kind"] == kind]


def test_dynamodb_storage_seeds_dev_account_and_grants_from_env(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)

    handler = load_lambda_handler(
        plan="monthlyBasic",
        monthly_quota=2,
        topup_quota=1,
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    response, body = invoke(handler, "GET", "/v1/quota")

    table = dynamodb.Table("lisdo-test-quota")
    assert response["statusCode"] == 200
    assert_quota_snapshot(body, plan_id="monthlyBasic", monthly_remaining=2, topup_remaining=1)
    assert table.items[("ACCOUNT#dev-account", "META")] == {
        "pk": "ACCOUNT#dev-account",
        "sk": "META",
        "kind": "account",
        "planId": "monthlyBasic",
        "userId": "dev-user",
        "updatedAt": "2026-05-14T12:00:00Z",
    }
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert [
        (grant["bucket"], grant["quantity"], grant["consumed"], grant["source"], grant["createdAt"])
        for grant in grants
    ] == [
        ("monthlyNonRollover", 2, 0, "dev", "2026-05-14T12:00:00Z"),
        ("topUpRollover", 1, 0, "dev", "2026-05-14T12:00:00Z"),
    ]


def test_dynamodb_auth_apple_creates_account_session_and_bearer_token_access(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )

    auth_response, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="apple-prod-user")},
        token=None,
    )
    session_token = auth_body["session"]["token"]
    quota_response, quota_body = invoke(handler, "GET", "/v1/quota", token=session_token)

    assert auth_response["statusCode"] == 200
    assert auth_body["status"] == "authenticated"
    assert auth_body["mode"] == "authenticated"
    assert auth_body["account"]["id"].startswith("apple-")
    assert auth_body["account"]["planId"] == "free"
    assert auth_body["session"]["subject"] == "apple:apple-prod-user"
    assert auth_body["session"]["tokenType"] == "Bearer"
    assert quota_response["statusCode"] == 200
    assert_quota_snapshot(quota_body, plan_id="free", monthly_remaining=0, topup_remaining=0)

    table = dynamodb.Table("lisdo-test-quota")
    assert len(_dynamodb_items(table, kind="sessionIndex")) == 1
    assert len(_dynamodb_items(table, kind="session")) == 1


def test_dynamodb_auth_apple_rejects_nonce_mismatch(
    load_lambda_handler,
    monkeypatch,
) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={
            "identityToken": unsigned_apple_identity_token(
                subject="web-nonce-user",
                audience="com.yiwenwu.Lisdo.web",
                nonce="apple-nonce",
            ),
            "nonce": "different-browser-nonce",
        },
        token=None,
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_apple_identity"
    assert "nonce" in body["error"]["message"]


def test_dynamodb_auth_apple_accepts_matching_nonce(
    load_lambda_handler,
    monkeypatch,
) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={
            "identityToken": unsigned_apple_identity_token(
                subject="web-nonce-user",
                audience="com.yiwenwu.Lisdo.web",
                nonce="browser-nonce",
            ),
            "nonce": "browser-nonce",
        },
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["status"] == "authenticated"


def test_dynamodb_account_profile_get_returns_apple_identity_and_patch_is_not_available(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )

    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={
            "identityToken": unsigned_apple_identity_token(subject="profile-user", email="yiwen@example.com"),
            "name": {"firstName": "Yiwen", "lastName": "Wu"},
        },
        token=None,
    )
    token = auth_body["session"]["token"]

    profile_response, profile_body = invoke(handler, "GET", "/v1/account/profile", token=token)
    assert profile_response["statusCode"] == 200
    assert profile_body["account"] == {
        "id": auth_body["account"]["id"],
        "planId": "free",
    }
    assert profile_body["profile"] == {
        "displayName": "Yiwen Wu",
        "email": "yiwen@example.com",
    }
    assert_quota_snapshot(profile_body["quota"], plan_id="free", monthly_remaining=0, topup_remaining=0)

    patch_response, patch_body = invoke(
        handler,
        "PATCH",
        "/v1/account/profile",
        token=token,
        body={
            "displayName": "Y. Wu",
            "avatarDataUrl": "data:image/png;base64,iVBORw0KGgo=",
        },
    )
    assert patch_response["statusCode"] == 404
    assert patch_body["error"]["code"] == "not_found"

    table = dynamodb.Table("lisdo-test-quota")
    account_item = table.items[(f"ACCOUNT#{auth_body['account']['id']}", "META")]
    assert account_item["displayName"] == "Yiwen Wu"
    assert "avatarDataUrl" not in account_item


def test_dynamodb_storekit_monthly_purchase_updates_plan_and_grants_quota(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="monthly-user")},
        token=None,
    )
    token = auth_body["session"]["token"]

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=token,
        body={
            "clientVerified": True,
            "transactionId": "1000001",
            "originalTransactionId": "1000001",
            "productId": "com.yiwenwu.Lisdo.monthlyPlus",
            "environment": "Sandbox",
            "expirationDate": "2026-06-14T12:00:00Z",
        },
    )
    replay_response, replay_body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=token,
        body={
            "clientVerified": True,
            "transactionId": "1000001",
            "originalTransactionId": "1000001",
            "productId": "com.yiwenwu.Lisdo.monthlyPlus",
            "environment": "Sandbox",
            "expirationDate": "2026-06-14T12:00:00Z",
        },
    )

    assert response["statusCode"] == 200
    assert body["status"] == "verified"
    assert body["entitlements"]["iCloudSync"] is True
    assert_quota_snapshot(body["quota"], plan_id="monthlyPlus", monthly_remaining=12000, topup_remaining=0)
    assert replay_response["statusCode"] == 200
    assert replay_body["quota"] == body["quota"]

    table = dynamodb.Table("lisdo-test-quota")
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert len(grants) == 1
    assert grants[0]["source"] == "storekit"
    assert grants[0]["periodEnd"] == "2026-06-14T12:00:00Z"


def test_dynamodb_storekit_server_jws_purchase_updates_plan_and_grants_quota(
    load_lambda_handler,
    monkeypatch,
) -> None:
    install_fake_app_store_server_library(monkeypatch)
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        storekit_verification_mode="server-jws",
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="server-jws-user")},
        token=None,
    )
    token = auth_body["session"]["token"]

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=token,
        body={
            "signedTransactionInfo": unsigned_storekit_transaction_jws(
                transaction_id="jws-1000001",
                product_id="com.yiwenwu.Lisdo.monthlyPlus",
                environment="Xcode",
                expires_date_ms=1781438400000,
            )
        },
    )

    assert response["statusCode"] == 200
    assert body["status"] == "verified"
    assert body["mode"] == "server-jws"
    assert body["entitlements"]["iCloudSync"] is True
    assert_quota_snapshot(body["quota"], plan_id="monthlyPlus", monthly_remaining=12000, topup_remaining=0)

    table = dynamodb.Table("lisdo-test-quota")
    grants = _dynamodb_items(table, kind="quotaGrant")
    transactions = _dynamodb_items(table, kind="storekitTransaction")
    assert len(grants) == 1
    assert grants[0]["periodEnd"] == "2026-06-14T12:00:00Z"
    assert transactions[0]["transactionId"] == "jws-1000001"
    assert transactions[0]["environment"] == "Xcode"


def test_dynamodb_storekit_server_jws_requires_signed_transaction_info(
    load_lambda_handler,
    monkeypatch,
) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        storekit_verification_mode="server-jws",
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="missing-jws-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=auth_body["session"]["token"],
        body={
            "clientVerified": True,
            "transactionId": "metadata-only",
            "productId": "com.yiwenwu.Lisdo.monthlyBasic",
        },
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_storekit_transaction"
    assert "signedTransactionInfo" in body["error"]["message"]


def test_dynamodb_storekit_server_jws_rejects_unmatched_bundle(
    load_lambda_handler,
    monkeypatch,
) -> None:
    install_fake_app_store_server_library(monkeypatch)
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
        storekit_verification_mode="server-jws",
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="bad-bundle-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=auth_body["session"]["token"],
        body={
            "signedTransactionInfo": unsigned_storekit_transaction_jws(
                transaction_id="bad-bundle-1",
                bundle_id="com.example.OtherApp",
            )
        },
    )

    assert response["statusCode"] == 400
    assert body["error"]["code"] == "invalid_storekit_transaction"
    assert "could not be verified" in body["error"]["message"]


def test_dynamodb_storekit_topup_requires_active_monthly_plan(
    load_lambda_handler,
    monkeypatch,
) -> None:
    _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="free",
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    _, auth_body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token(subject="topup-user")},
        token=None,
    )

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        token=auth_body["session"]["token"],
        body={
            "clientVerified": True,
            "transactionId": "topup-1",
            "productId": "com.yiwenwu.Lisdo.topUpUsage",
        },
    )

    assert response["statusCode"] == 402
    assert body["error"]["code"] == "topup_requires_monthly_plan"


def test_dynamodb_storage_loads_plan_and_quota_from_account_items(
    load_lambda_handler,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": "ACCOUNT#dev-account",
            "sk": "META",
            "kind": "account",
            "planId": "monthlyPlus",
            "userId": "existing-user",
            "updatedAt": "2026-05-01T00:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": "ACCOUNT#dev-account",
            "sk": "GRANT#monthlyNonRollover#2026-05#existing",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 5,
            "consumed": 2,
            "source": "storekit",
            "createdAt": "2026-05-01T00:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": "ACCOUNT#dev-account",
            "sk": "GRANT#topUpRollover#2026-05#existing",
            "kind": "quotaGrant",
            "bucket": "topUpRollover",
            "quantity": 4,
            "consumed": 1,
            "source": "manual",
            "createdAt": "2026-05-01T00:00:00Z",
        }
    )

    handler = load_lambda_handler(
        plan="free",
        monthly_quota=99,
        topup_quota=99,
        openai_api_key=None,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    response, body = invoke(handler, "GET", "/v1/quota")

    assert response["statusCode"] == 200
    assert_quota_snapshot(
        body,
        plan_id="monthlyPlus",
        monthly_remaining=3,
        topup_remaining=3,
        monthly_consumed=2,
        topup_consumed=1,
    )
    assert len(_dynamodb_items(table, kind="quotaGrant")) == 2


def test_dynamodb_storage_requires_table_name(load_lambda_handler) -> None:
    handler = load_lambda_handler(
        plan="monthlyBasic",
        monthly_quota=1,
        storage="dynamodb",
    )

    with pytest.raises(RuntimeError, match="LISDO_DYNAMODB_TABLE_NAME"):
        invoke(handler, "GET", "/v1/quota")


def test_dynamodb_stored_plan_drives_bootstrap_entitlements_and_draft_generation(
    load_lambda_handler,
    install_provider,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    table = dynamodb.Table("lisdo-test-quota")
    table.put_item(
        Item={
            "pk": "ACCOUNT#dev-account",
            "sk": "META",
            "kind": "account",
            "planId": "monthlyPlus",
            "userId": "existing-user",
            "updatedAt": "2026-05-01T00:00:00Z",
        }
    )
    table.put_item(
        Item={
            "pk": "ACCOUNT#dev-account",
            "sk": "GRANT#monthlyNonRollover#2026-05#existing",
            "kind": "quotaGrant",
            "bucket": "monthlyNonRollover",
            "quantity": 1,
            "consumed": 0,
            "source": "storekit",
            "createdAt": "2026-05-01T00:00:00Z",
        }
    )
    handler = load_lambda_handler(
        plan="free",
        monthly_quota=0,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )

    bootstrap_response, bootstrap_body = invoke(handler, "GET", "/v1/bootstrap")
    provider_calls = install_provider()
    draft_response, draft_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert bootstrap_response["statusCode"] == 200
    assert bootstrap_body["account"]["planId"] == "monthlyPlus"
    assert bootstrap_body["entitlements"]["lisdoManagedDrafts"] is True
    assert_quota_snapshot(
        bootstrap_body["quota"],
        plan_id="monthlyPlus",
        monthly_remaining=1,
        topup_remaining=0,
    )
    assert draft_response["statusCode"] == 200
    assert_draft_first_response(draft_body)
    assert_usage_quota_units(
        draft_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert_quota_snapshot(
        draft_body["quota"],
        plan_id="monthlyPlus",
        monthly_remaining=0,
        topup_remaining=0,
        monthly_consumed=1,
    )
    assert len(provider_calls) == 1


def test_dynamodb_generate_draft_consumes_monthly_then_topup_and_records_usage_events(
    load_lambda_handler,
    install_provider,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="monthlyBasic",
        monthly_quota=1,
        topup_quota=1,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    provider_calls = install_provider()

    first_response, first_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())
    second_response, second_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    table = dynamodb.Table("lisdo-test-quota")
    assert first_response["statusCode"] == 200
    assert_draft_first_response(first_body)
    assert_usage_quota_units(
        first_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert_quota_snapshot(
        first_body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert second_response["statusCode"] == 200
    assert_usage_quota_units(
        second_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=0,
        topup_consumed=1,
    )
    assert_quota_snapshot(
        second_body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=0,
        monthly_consumed=1,
        topup_consumed=1,
    )
    grants = _dynamodb_items(table, kind="quotaGrant")
    assert [(grant["bucket"], grant["consumed"]) for grant in grants] == [
        ("monthlyNonRollover", 1),
        ("topUpRollover", 1),
    ]
    usage_events = _dynamodb_items(table, kind="usageEvent")
    assert sorted((event["eventType"], event["bucket"], event["quantity"]) for event in usage_events) == [
        ("managedDraftGenerated", "monthlyNonRollover", 1),
        ("managedDraftGenerated", "topUpRollover", 1),
    ]
    assert len(provider_calls) == 2


def test_dynamodb_provider_failure_does_not_consume_quota_or_record_usage(
    load_lambda_handler,
    install_provider,
    monkeypatch,
) -> None:
    dynamodb = _install_fake_boto3(monkeypatch)
    handler = load_lambda_handler(
        plan="monthlyPlus",
        monthly_quota=1,
        topup_quota=1,
        storage="dynamodb",
        dynamodb_table_name="lisdo-test-quota",
    )
    provider_calls = install_provider(raises=RuntimeError("upstream unavailable"))

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    table = dynamodb.Table("lisdo-test-quota")
    assert response["statusCode"] == 502
    assert body["error"]["code"] == "provider_error"
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyPlus",
        monthly_remaining=1,
        topup_remaining=1,
        monthly_consumed=0,
        topup_consumed=0,
    )
    assert [(grant["bucket"], grant["consumed"]) for grant in _dynamodb_items(table, kind="quotaGrant")] == [
        ("monthlyNonRollover", 0),
        ("topUpRollover", 0),
    ]
    assert _dynamodb_items(table, kind="usageEvent") == []
    assert len(provider_calls) == 1


def test_free_account_is_denied_draft_generation_and_response_includes_quota_snapshot(
    load_lambda_handler,
) -> None:
    handler = load_lambda_handler(plan="free", monthly_quota=0, topup_quota=0)

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert response["statusCode"] == 402
    assert body["error"]["code"] == "managed_drafts_unavailable"
    assert "managed draft" in body["error"]["message"]
    assert_quota_snapshot(
        body["quota"],
        plan_id="free",
        monthly_remaining=0,
        topup_remaining=0,
    )


def test_monthly_plan_consumes_monthly_quota_before_top_up_rollover_quota(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=1, topup_quota=2)
    provider_calls = install_provider()

    first_response, first_body = invoke(
        handler,
        "POST",
        "/v1/drafts/generate",
        body=draft_generation_body("First managed draft."),
    )
    second_response, second_body = invoke(
        handler,
        "POST",
        "/v1/drafts/generate",
        body=draft_generation_body("Second managed draft."),
    )
    quota_response, quota_body = invoke(handler, "GET", "/v1/quota")

    assert first_response["statusCode"] == 200
    assert_draft_first_response(first_body)
    assert_usage_quota_units(
        first_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert_quota_snapshot(
        first_body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=2,
        monthly_consumed=1,
        topup_consumed=0,
    )

    assert second_response["statusCode"] == 200
    assert_draft_first_response(second_body)
    assert_usage_quota_units(
        second_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=0,
        topup_consumed=1,
    )
    assert_quota_snapshot(
        second_body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=1,
        monthly_consumed=1,
        topup_consumed=1,
    )

    assert quota_response["statusCode"] == 200
    assert_quota_snapshot(
        quota_body,
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=1,
        monthly_consumed=1,
        topup_consumed=1,
    )
    assert len(provider_calls) == 2


def test_successful_draft_charges_cost_units_from_openai_token_usage(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=3, topup_quota=5)
    provider_calls = install_provider(
        usage={
            "promptTokens": 200,
            "completionTokens": 26,
            "totalTokens": 226,
        }
    )

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())
    quota_response, quota_body = invoke(handler, "GET", "/v1/quota")

    assert response["statusCode"] == 200
    assert_draft_first_response(body)
    assert_usage_quota_units(
        body["usage"],
        input_tokens=200,
        output_tokens=26,
        cost_units=2,
        monthly_consumed=2,
        topup_consumed=0,
    )
    assert body["usage"]["totalTokens"] == 226
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=1,
        topup_remaining=5,
        monthly_consumed=2,
        topup_consumed=0,
    )
    assert quota_response["statusCode"] == 200
    assert_quota_snapshot(
        quota_body,
        plan_id="monthlyBasic",
        monthly_remaining=1,
        topup_remaining=5,
        monthly_consumed=2,
        topup_consumed=0,
    )
    assert len(provider_calls) == 1


def test_paid_monthly_plan_spans_cost_units_across_monthly_and_topup(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=1, topup_quota=5)
    provider_calls = install_provider(
        usage={
            "promptTokens": 0,
            "completionTokens": 200,
            "totalTokens": 200,
        }
    )

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert response["statusCode"] == 200
    assert_draft_first_response(body)
    assert_usage_quota_units(
        body["usage"],
        input_tokens=0,
        output_tokens=200,
        cost_units=4,
        monthly_consumed=1,
        topup_consumed=3,
    )
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=2,
        monthly_consumed=1,
        topup_consumed=3,
    )
    assert len(provider_calls) == 1


def test_successful_draft_returns_with_uncovered_units_when_actual_cost_exceeds_available_quota(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=2, topup_quota=1)
    provider_calls = install_provider(
        usage={
            "promptTokens": 0,
            "completionTokens": 250,
            "totalTokens": 250,
        }
    )

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert response["statusCode"] == 200
    assert_draft_first_response(body)
    assert_usage_quota_units(
        body["usage"],
        input_tokens=0,
        output_tokens=250,
        cost_units=5,
        monthly_consumed=2,
        topup_consumed=1,
        uncovered=2,
    )
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=0,
        monthly_consumed=2,
        topup_consumed=1,
    )
    assert len(provider_calls) == 1


def test_starter_trial_never_consumes_topup_units_even_when_actual_cost_exceeds_monthly(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="starterTrial", monthly_quota=1, topup_quota=5)
    provider_calls = install_provider(
        usage={
            "promptTokens": 0,
            "completionTokens": 150,
            "totalTokens": 150,
        }
    )

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())
    second_response, second_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert response["statusCode"] == 200
    assert_draft_first_response(body)
    assert_usage_quota_units(
        body["usage"],
        input_tokens=0,
        output_tokens=150,
        cost_units=3,
        monthly_consumed=1,
        topup_consumed=0,
        uncovered=2,
    )
    assert_quota_snapshot(
        body["quota"],
        plan_id="starterTrial",
        monthly_remaining=0,
        topup_remaining=5,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert second_response["statusCode"] == 402
    assert second_body["error"]["code"] == "quota_exhausted"
    assert len(provider_calls) == 1


def test_managed_draft_generation_uses_server_plan_model_and_sanitizes_client_request(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyPlus", monthly_quota=1)
    provider_calls = install_provider()
    body = draft_generation_body()
    body["chatRequest"]["model"] = "client-requested-expensive-model"
    body["chatRequest"]["temperature"] = 2.0
    body["chatRequest"]["max_tokens"] = 9999
    body["chatRequest"]["tools"] = [{"type": "web_search"}]

    response, _ = invoke(handler, "POST", "/v1/drafts/generate", body=body)

    assert response["statusCode"] == 200
    assert len(provider_calls) == 1
    assert provider_calls[0]["chatRequest"] == {
        "model": "gpt-5.4-mini",
        "messages": body["chatRequest"]["messages"],
        "response_format": {"type": "json_object"},
        "reasoning_effort": "low",
        "max_completion_tokens": 3000,
    }


def test_no_openai_key_returns_deterministic_draft_json_and_consumes_quota(
    load_lambda_handler,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=1, topup_quota=0, openai_api_key=None)

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert response["statusCode"] == 200
    assert_draft_first_response(body)
    expected_draft_json = {
        "recommendedCategoryId": "inbox",
        "confidence": 0.5,
        "title": "Review captured task",
        "summary": "Review the captured text and confirm the task details before saving.",
        "blocks": [
            {
                "type": "checkbox",
                "content": "Review the captured text",
                "checked": False,
            }
        ],
        "dueDateText": None,
        "priority": None,
        "needsClarification": False,
        "questionsForUser": [],
    }
    assert isinstance(body["draftJSON"], str)
    assert body["draftJSON"] == json.dumps(expected_draft_json, separators=(",", ":"))
    assert json.loads(body["draftJSON"]) == expected_draft_json
    assert body["draft"] == {
        "status": "draft",
        "title": "Review captured task",
        "recommendedCategoryId": "inbox",
        "summary": "Review the captured text and confirm the task details before saving.",
        "blocks": [
            {
                "kind": "task",
                "text": "Review the captured text",
                "checked": False,
            }
        ],
        "needsClarification": False,
        "questionsForUser": [],
    }
    assert body["usage"]["source"] == "deterministic-local"
    assert_usage_quota_units(
        body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=0,
        topup_remaining=0,
        monthly_consumed=1,
    )


def test_starter_trial_can_use_monthly_quota_but_not_top_up_rollover_quota(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="starterTrial", monthly_quota=1, topup_quota=2)
    provider_calls = install_provider()

    first_response, first_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())
    second_response, second_body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())

    assert first_response["statusCode"] == 200
    assert_usage_quota_units(
        first_body["usage"],
        input_tokens=0,
        output_tokens=0,
        cost_units=1,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert_quota_snapshot(
        first_body["quota"],
        plan_id="starterTrial",
        monthly_remaining=0,
        topup_remaining=2,
        monthly_consumed=1,
        topup_consumed=0,
    )

    assert second_response["statusCode"] == 402
    assert second_body["error"]["code"] == "quota_exhausted"
    assert_quota_snapshot(
        second_body["quota"],
        plan_id="starterTrial",
        monthly_remaining=0,
        topup_remaining=2,
        monthly_consumed=1,
        topup_consumed=0,
    )
    assert len(provider_calls) == 1


def test_provider_failure_does_not_consume_or_refunds_quota_and_includes_quota_snapshot(
    load_lambda_handler,
    install_provider,
) -> None:
    handler = load_lambda_handler(plan="monthlyPlus", monthly_quota=1, topup_quota=1)
    provider_calls = install_provider(raises=RuntimeError("upstream unavailable"))

    response, body = invoke(handler, "POST", "/v1/drafts/generate", body=draft_generation_body())
    quota_response, quota_body = invoke(handler, "GET", "/v1/quota")

    assert response["statusCode"] == 502
    assert body["error"]["code"] == "provider_error"
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyPlus",
        monthly_remaining=1,
        topup_remaining=1,
        monthly_consumed=0,
        topup_consumed=0,
    )

    assert quota_response["statusCode"] == 200
    assert_quota_snapshot(
        quota_body,
        plan_id="monthlyPlus",
        monthly_remaining=1,
        topup_remaining=1,
        monthly_consumed=0,
        topup_consumed=0,
    )
    assert len(provider_calls) == 1
