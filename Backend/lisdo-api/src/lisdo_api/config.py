from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timezone
from os import environ
from pathlib import Path


def _int_env(name: str, default: int) -> int:
    raw_value = environ.get(name)
    if raw_value is None:
        return default
    try:
        return int(raw_value)
    except ValueError:
        return default


def _optional_int_env(name: str) -> int | None:
    value = _optional_env(name)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _bool_env(name: str, default: bool) -> bool:
    value = _optional_env(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "y", "on"}


def _csv_env(name: str) -> tuple[str, ...]:
    return tuple(value.strip() for value in environ.get(name, "").split(",") if value.strip())


def _optional_env(name: str) -> str | None:
    value = environ.get(name)
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class DevConfig:
    account_id: str
    session_id: str
    user_id: str
    plan_id: str
    session_token: str
    monthly_quota: int
    topup_quota: int
    ledger_path: str
    now: str
    env: str
    storage: str
    dynamodb_table_name: str | None
    apple_client_ids: tuple[str, ...]
    apple_identity_verification_mode: str
    session_ttl_days: int
    storekit_verification_mode: str
    storekit_bundle_ids: tuple[str, ...]
    storekit_app_apple_id: int | None
    storekit_root_certificates_dir: str
    storekit_enable_online_checks: bool
    storekit_allow_xcode_environment: bool
    stripe_secret_key_parameter_name: str | None
    stripe_webhook_secret_parameter_name: str | None
    stripe_checkout_success_url: str
    stripe_checkout_cancel_url: str
    stripe_billing_portal_return_url: str
    stripe_automatic_tax: bool
    stripe_price_starter_trial: str | None
    stripe_price_monthly_basic: str | None
    stripe_price_monthly_plus: str | None
    stripe_price_monthly_max: str | None
    stripe_price_top_up_usage: str | None


def load_config() -> DevConfig:
    apple_client_ids = _csv_env("LISDO_APPLE_CLIENT_IDS")
    env = environ.get("LISDO_ENV", "development").strip().lower()
    default_storekit_cert_dir = Path(__file__).resolve().parent / "certs" / "apple-root-ca"
    storekit_bundle_ids = _csv_env("LISDO_STOREKIT_BUNDLE_IDS") or apple_client_ids or ("com.yiwenwu.Lisdo",)
    return DevConfig(
        account_id=environ.get("LISDO_DEV_ACCOUNT_ID", "dev-account"),
        session_id=environ.get("LISDO_DEV_SESSION_ID", "dev-session"),
        user_id=environ.get("LISDO_DEV_USER_ID", "dev-user"),
        plan_id=environ.get("LISDO_DEV_PLAN", "free"),
        session_token=environ.get("LISDO_DEV_SESSION_TOKEN", "dev-token"),
        monthly_quota=max(0, _int_env("LISDO_DEV_MONTHLY_QUOTA", 0)),
        topup_quota=max(0, _int_env("LISDO_DEV_TOPUP_QUOTA", 0)),
        ledger_path=environ.get("LISDO_DEV_LEDGER_PATH", "/tmp/lisdo-dev-quota.json"),
        now=_optional_env("LISDO_DEV_NOW") or _utc_now_iso(),
        env=env,
        storage=environ.get("LISDO_STORAGE", "local").strip().lower(),
        dynamodb_table_name=_optional_env("LISDO_DYNAMODB_TABLE_NAME"),
        apple_client_ids=apple_client_ids,
        apple_identity_verification_mode=environ.get("LISDO_APPLE_IDENTITY_VERIFICATION_MODE", "apple-jwks")
        .strip()
        .lower(),
        session_ttl_days=max(1, _int_env("LISDO_SESSION_TTL_DAYS", 90)),
        storekit_verification_mode=environ.get("LISDO_STOREKIT_VERIFICATION_MODE", "client-verified")
        .strip()
        .lower(),
        storekit_bundle_ids=storekit_bundle_ids,
        storekit_app_apple_id=_optional_int_env("LISDO_STOREKIT_APP_APPLE_ID"),
        storekit_root_certificates_dir=_optional_env("LISDO_STOREKIT_ROOT_CERTIFICATES_DIR")
        or str(default_storekit_cert_dir),
        storekit_enable_online_checks=_bool_env("LISDO_STOREKIT_ENABLE_ONLINE_CHECKS", False),
        storekit_allow_xcode_environment=_bool_env("LISDO_STOREKIT_ALLOW_XCODE_ENVIRONMENT", env != "production"),
        stripe_secret_key_parameter_name=_optional_env("STRIPE_SECRET_KEY_PARAMETER_NAME"),
        stripe_webhook_secret_parameter_name=_optional_env("STRIPE_WEBHOOK_SECRET_PARAMETER_NAME"),
        stripe_checkout_success_url=_optional_env("STRIPE_CHECKOUT_SUCCESS_URL")
        or "https://lisdo.app/#plans?checkout=success",
        stripe_checkout_cancel_url=_optional_env("STRIPE_CHECKOUT_CANCEL_URL") or "https://lisdo.app/#plans",
        stripe_billing_portal_return_url=_optional_env("STRIPE_BILLING_PORTAL_RETURN_URL")
        or "https://lisdo.app/#plans",
        stripe_automatic_tax=_bool_env("STRIPE_AUTOMATIC_TAX_ENABLED", True),
        stripe_price_starter_trial=_optional_env("STRIPE_PRICE_STARTER_TRIAL"),
        stripe_price_monthly_basic=_optional_env("STRIPE_PRICE_MONTHLY_BASIC"),
        stripe_price_monthly_plus=_optional_env("STRIPE_PRICE_MONTHLY_PLUS"),
        stripe_price_monthly_max=_optional_env("STRIPE_PRICE_MONTHLY_MAX"),
        stripe_price_top_up_usage=_optional_env("STRIPE_PRICE_TOP_UP_USAGE"),
    )


def config_for_account(config: DevConfig, account_id: str, user_id: str | None = None) -> DevConfig:
    return replace(
        config,
        account_id=account_id,
        user_id=user_id or config.user_id,
    )


def account_response(config: DevConfig, *, plan_id: str | None = None) -> dict[str, str]:
    return {
        "id": config.account_id,
        "planId": plan_id or config.plan_id,
    }


def session_response(config: DevConfig, *, token: str | None = None, expires_at: str | None = None) -> dict[str, str | bool]:
    response: dict[str, str | bool] = {
        "id": config.session_id,
        "subject": config.user_id,
        "tokenType": "Bearer",
        "authenticated": True,
    }
    if token is not None:
        response["token"] = token
    if expires_at is not None:
        response["expiresAt"] = expires_at
    return response
