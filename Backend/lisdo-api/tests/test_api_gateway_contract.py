from __future__ import annotations

from conftest import assert_quota_snapshot, invoke, unsigned_apple_identity_token


def test_missing_or_invalid_auth_on_protected_route_returns_uniform_json_error(
    load_lambda_handler,
) -> None:
    handler = load_lambda_handler(openai_api_key=None)

    missing_response, missing_body = invoke(handler, "GET", "/v1/bootstrap", token=None)
    invalid_response, invalid_body = invoke(handler, "GET", "/v1/bootstrap", token="wrong-token")

    assert missing_response["statusCode"] == 401
    assert invalid_response["statusCode"] == 401
    assert missing_body == invalid_body == {
        "error": {
            "code": "unauthorized",
            "message": "Missing or invalid bearer token.",
        }
    }


def test_http_api_v2_health_returns_public_healthy_json(load_lambda_handler) -> None:
    handler = load_lambda_handler(openai_api_key=None)

    response, body = invoke(handler, "GET", "/v1/health", token=None)

    assert response["statusCode"] == 200
    assert body == {
        "service": "lisdo-api",
        "status": "healthy",
        "visibility": "public",
    }


def test_bootstrap_with_dev_bearer_token_returns_account_session_entitlements_and_quota(
    load_lambda_handler,
) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=12, topup_quota=3)

    response, body = invoke(handler, "GET", "/v1/bootstrap")

    assert response["statusCode"] == 200
    assert body["account"] == {
        "id": "dev-account",
        "planId": "monthlyBasic",
    }
    assert body["session"] == {
        "id": "dev-session",
        "subject": "dev-user",
        "tokenType": "Bearer",
        "authenticated": True,
    }
    assert body["entitlements"] == {
        "byokAndCLI": True,
        "lisdoManagedDrafts": True,
        "iCloudSync": True,
        "realtimeVoice": False,
    }
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=12,
        topup_remaining=3,
    )


def test_quota_endpoint_returns_quota_snapshot(load_lambda_handler) -> None:
    handler = load_lambda_handler(plan="monthlyPlus", monthly_quota=8, topup_quota=5)

    response, body = invoke(handler, "GET", "/v1/quota")

    assert response["statusCode"] == 200
    assert_quota_snapshot(
        body,
        plan_id="monthlyPlus",
        monthly_remaining=8,
        topup_remaining=5,
    )


def test_entitlements_endpoint_returns_plan_entitlement_matrix(load_lambda_handler) -> None:
    free_handler = load_lambda_handler(plan="free")
    _, free_body = invoke(free_handler, "GET", "/v1/entitlements")

    trial_handler = load_lambda_handler(plan="starterTrial")
    _, trial_body = invoke(trial_handler, "GET", "/v1/entitlements")

    max_handler = load_lambda_handler(plan="monthlyMax")
    _, max_body = invoke(max_handler, "GET", "/v1/entitlements")

    assert free_body == {
        "byokAndCLI": True,
        "lisdoManagedDrafts": False,
        "iCloudSync": False,
        "realtimeVoice": False,
    }
    assert trial_body == {
        "byokAndCLI": True,
        "lisdoManagedDrafts": True,
        "iCloudSync": False,
        "realtimeVoice": True,
    }
    assert max_body == {
        "byokAndCLI": True,
        "lisdoManagedDrafts": True,
        "iCloudSync": True,
        "realtimeVoice": True,
    }


def test_realtime_client_secret_returns_not_configured_stub_shape_with_quota_snapshot(
    load_lambda_handler,
) -> None:
    handler = load_lambda_handler(plan="monthlyMax", monthly_quota=6, topup_quota=2, openai_api_key=None)

    response, body = invoke(handler, "POST", "/v1/realtime/client-secret")

    assert response["statusCode"] == 200
    assert body["status"] == "not_configured"
    assert body["mode"] == "stub"
    assert body["clientSecret"] == "not_configured"
    assert body["sessionId"] == "stub-realtime-session"
    assert body["expiresAt"] == "1970-01-01T00:00:00Z"
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyMax",
        monthly_remaining=6,
        topup_remaining=2,
    )


def test_public_auth_apple_route_returns_dev_session_stub(load_lambda_handler) -> None:
    handler = load_lambda_handler(plan="starterTrial", openai_api_key=None)

    response, body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={"identityToken": unsigned_apple_identity_token()},
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["status"] == "authenticated"
    assert body["mode"] == "stub"
    assert body["account"] == {
        "id": "dev-account",
        "planId": "starterTrial",
    }
    assert body["session"] == {
        "id": "dev-session",
        "subject": "dev-user",
        "token": "dev-token",
        "tokenType": "Bearer",
        "authenticated": True,
        "expiresAt": "2026-08-12T12:00:00Z",
    }


def test_public_auth_apple_route_accepts_web_services_id_audience(load_lambda_handler) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", openai_api_key=None)

    response, body = invoke(
        handler,
        "POST",
        "/v1/auth/apple",
        body={
            "identityToken": unsigned_apple_identity_token(
                subject="web-apple-user",
                audience="com.yiwenwu.Lisdo.web",
                email="web@example.com",
            )
        },
        token=None,
    )

    assert response["statusCode"] == 200
    assert body["status"] == "authenticated"
    assert body["session"]["authenticated"] is True


def test_storekit_verify_route_returns_verified_entitlements_and_quota(load_lambda_handler) -> None:
    handler = load_lambda_handler(plan="monthlyBasic", monthly_quota=4, topup_quota=1, openai_api_key=None)

    response, body = invoke(
        handler,
        "POST",
        "/v1/storekit/transactions/verify",
        body={
            "clientVerified": True,
            "transactionId": "test-transaction",
            "originalTransactionId": "test-original",
            "productId": "com.yiwenwu.Lisdo.monthlyBasic",
        },
    )

    assert response["statusCode"] == 200
    assert body["status"] == "verified"
    assert body["mode"] == "client-verified"
    assert body["entitlements"] == {
        "byokAndCLI": True,
        "lisdoManagedDrafts": True,
        "iCloudSync": True,
        "realtimeVoice": False,
    }
    assert_quota_snapshot(
        body["quota"],
        plan_id="monthlyBasic",
        monthly_remaining=4,
        topup_remaining=1,
    )
