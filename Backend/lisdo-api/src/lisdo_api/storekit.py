from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .entitlements import KNOWN_PLANS


class StoreKitTransactionError(ValueError):
    pass


@dataclass(frozen=True)
class StoreKitProduct:
    product_id: str
    kind: str
    plan_id: str | None
    monthly_quota: int
    topup_quota: int


PRODUCTS: dict[str, StoreKitProduct] = {
    "com.yiwenwu.Lisdo.starterTrial": StoreKitProduct(
        product_id="com.yiwenwu.Lisdo.starterTrial",
        kind="nonConsumableTrial",
        plan_id="starterTrial",
        monthly_quota=1500,
        topup_quota=0,
    ),
    "com.yiwenwu.Lisdo.monthlyBasic": StoreKitProduct(
        product_id="com.yiwenwu.Lisdo.monthlyBasic",
        kind="autoRenewableSubscription",
        plan_id="monthlyBasic",
        monthly_quota=3000,
        topup_quota=0,
    ),
    "com.yiwenwu.Lisdo.monthlyPlus": StoreKitProduct(
        product_id="com.yiwenwu.Lisdo.monthlyPlus",
        kind="autoRenewableSubscription",
        plan_id="monthlyPlus",
        monthly_quota=12000,
        topup_quota=0,
    ),
    "com.yiwenwu.Lisdo.monthlyMax": StoreKitProduct(
        product_id="com.yiwenwu.Lisdo.monthlyMax",
        kind="autoRenewableSubscription",
        plan_id="monthlyMax",
        monthly_quota=50000,
        topup_quota=0,
    ),
    "com.yiwenwu.Lisdo.topUpUsage": StoreKitProduct(
        product_id="com.yiwenwu.Lisdo.topUpUsage",
        kind="consumableTopUp",
        plan_id=None,
        monthly_quota=0,
        topup_quota=10000,
    ),
}

LOCAL_STOREKIT_ENVIRONMENTS = frozenset({"Xcode", "LocalTesting"})
STOREKIT_VERIFICATION_MODES = frozenset({"client-verified", "server-jws", "disabled"})
STOREKIT_GRANT_NOTIFICATION_TYPES = frozenset({"INITIAL_BUY", "DID_RENEW", "DID_RECOVER", "SUBSCRIBED"})
STOREKIT_REVOKE_NOTIFICATION_TYPES = frozenset({"EXPIRED", "REFUND", "REVOKE"})


def parse_verified_transaction(
    body: dict[str, Any],
    *,
    verification_mode: str,
    bundle_ids: tuple[str, ...] = (),
    app_apple_id: int | None = None,
    root_certificates_dir: str | None = None,
    enable_online_checks: bool = False,
    allow_xcode_environment: bool = False,
) -> dict[str, Any]:
    if verification_mode not in STOREKIT_VERIFICATION_MODES:
        raise StoreKitTransactionError("Unsupported StoreKit verification mode.")
    if verification_mode == "disabled":
        raise StoreKitTransactionError("StoreKit verification is not configured.")
    if verification_mode == "server-jws":
        return _parse_server_jws_transaction(
            body,
            bundle_ids=bundle_ids,
            app_apple_id=app_apple_id,
            root_certificates_dir=root_certificates_dir,
            enable_online_checks=enable_online_checks,
            allow_xcode_environment=allow_xcode_environment,
        )
    return _parse_client_verified_transaction(body)


def parse_server_notification(
    body: dict[str, Any],
    *,
    verification_mode: str,
    bundle_ids: tuple[str, ...] = (),
    app_apple_id: int | None = None,
    root_certificates_dir: str | None = None,
    enable_online_checks: bool = False,
    allow_xcode_environment: bool = False,
) -> dict[str, Any]:
    if verification_mode != "server-jws":
        raise StoreKitTransactionError("StoreKit server notifications require server-jws verification.")

    signed_payload = _required_string(body, "signedPayload")
    unverified_payload = _decode_jws_payload(signed_payload)
    unverified_data = _notification_data(unverified_payload)
    environment = _payload_environment(unverified_data)
    if environment in LOCAL_STOREKIT_ENVIRONMENTS and not allow_xcode_environment:
        raise StoreKitTransactionError("Local StoreKit notifications are not accepted in this environment.")

    decoded_payload = _verify_signed_notification(
        signed_payload,
        environment=environment,
        bundle_ids=bundle_ids,
        app_apple_id=app_apple_id,
        root_certificates_dir=root_certificates_dir,
        enable_online_checks=enable_online_checks,
    )
    notification_type = _payload_required_string(decoded_payload, "notificationType")
    notification_uuid = _payload_optional_string(decoded_payload, "notificationUUID") or notification_type
    decoded_data = _notification_data(decoded_payload)
    action = _notification_action(notification_type)
    signed_transaction = _payload_optional_string(decoded_data, "signedTransactionInfo")
    transaction = None
    if action in {"grant", "revoke"}:
        if signed_transaction is None:
            raise StoreKitTransactionError("StoreKit notification is missing signedTransactionInfo.")
        transaction = _parse_server_jws_transaction(
            {"signedTransactionInfo": signed_transaction},
            bundle_ids=bundle_ids,
            app_apple_id=app_apple_id,
            root_certificates_dir=root_certificates_dir,
            enable_online_checks=enable_online_checks,
            allow_xcode_environment=allow_xcode_environment,
        )

    return {
        "notificationType": notification_type,
        "notificationUUID": notification_uuid,
        "action": action,
        "transaction": transaction,
    }


def _parse_client_verified_transaction(body: dict[str, Any]) -> dict[str, Any]:
    client_verified = body.get("clientVerified")
    if client_verified is not True:
        raise StoreKitTransactionError("StoreKit transaction must be verified on device before upload.")

    product_id = _required_string(body, "productId")
    transaction_id = _required_string(body, "transactionId")
    product = _product_for_id(product_id)

    return _transaction_result(
        product=product,
        product_id=product_id,
        transaction_id=transaction_id,
        original_transaction_id=_optional_string(body, "originalTransactionId") or transaction_id,
        environment=_optional_string(body, "environment") or "unknown",
        purchase_date=_optional_string(body, "purchaseDate"),
        expiration_date=_optional_string(body, "expirationDate"),
    )


def _parse_server_jws_transaction(
    body: dict[str, Any],
    *,
    bundle_ids: tuple[str, ...],
    app_apple_id: int | None,
    root_certificates_dir: str | None,
    enable_online_checks: bool,
    allow_xcode_environment: bool,
) -> dict[str, Any]:
    signed_transaction = _required_string(body, "signedTransactionInfo")
    unverified_payload = _decode_jws_payload(signed_transaction)
    environment = _payload_environment(unverified_payload)
    if environment in LOCAL_STOREKIT_ENVIRONMENTS and not allow_xcode_environment:
        raise StoreKitTransactionError("Local StoreKit transactions are not accepted in this environment.")

    decoded_payload = _verify_signed_transaction(
        signed_transaction,
        environment=environment,
        bundle_ids=bundle_ids,
        app_apple_id=app_apple_id,
        root_certificates_dir=root_certificates_dir,
        enable_online_checks=enable_online_checks,
    )

    product_id = _payload_required_string(decoded_payload, "productId")
    transaction_id = _payload_required_string(decoded_payload, "transactionId")
    original_transaction_id = _payload_optional_string(decoded_payload, "originalTransactionId") or transaction_id
    product = _product_for_id(product_id)

    _validate_optional_match(body, "productId", product_id)
    _validate_optional_match(body, "transactionId", transaction_id)
    _validate_optional_match(body, "originalTransactionId", original_transaction_id)

    return _transaction_result(
        product=product,
        product_id=product_id,
        transaction_id=transaction_id,
        original_transaction_id=original_transaction_id,
        environment=_payload_environment(decoded_payload),
        purchase_date=_payload_millis_to_iso(decoded_payload, "purchaseDate"),
        expiration_date=_payload_millis_to_iso(decoded_payload, "expiresDate"),
    )


def _verify_signed_transaction(
    signed_transaction: str,
    *,
    environment: str,
    bundle_ids: tuple[str, ...],
    app_apple_id: int | None,
    root_certificates_dir: str | None,
    enable_online_checks: bool,
) -> Any:
    if not bundle_ids:
        raise StoreKitTransactionError("StoreKit bundle IDs are not configured.")
    if environment == "Production" and app_apple_id is None:
        raise StoreKitTransactionError("StoreKit appAppleId is required for Production transactions.")

    try:
        from appstoreserverlibrary.models.Environment import Environment
        from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier, VerificationException
    except ImportError as exc:
        raise StoreKitTransactionError("App Store Server Library is not packaged.") from exc

    try:
        verifier_environment = Environment(environment)
    except ValueError as exc:
        raise StoreKitTransactionError("StoreKit transaction environment is not supported.") from exc

    root_certificates = (
        []
        if environment in LOCAL_STOREKIT_ENVIRONMENTS
        else _load_root_certificates(root_certificates_dir)
    )
    failures: list[str] = []
    for bundle_id in bundle_ids:
        verifier = SignedDataVerifier(
            root_certificates,
            enable_online_checks,
            verifier_environment,
            bundle_id,
            app_apple_id,
        )
        try:
            return verifier.verify_and_decode_signed_transaction(signed_transaction)
        except VerificationException as exc:
            failures.append(str(exc))

    detail = f" ({'; '.join(failures)})" if failures else ""
    raise StoreKitTransactionError(f"StoreKit transaction could not be verified{detail}.")


def _verify_signed_notification(
    signed_payload: str,
    *,
    environment: str,
    bundle_ids: tuple[str, ...],
    app_apple_id: int | None,
    root_certificates_dir: str | None,
    enable_online_checks: bool,
) -> Any:
    if not bundle_ids:
        raise StoreKitTransactionError("StoreKit bundle IDs are not configured.")
    if environment == "Production" and app_apple_id is None:
        raise StoreKitTransactionError("StoreKit appAppleId is required for Production notifications.")

    try:
        from appstoreserverlibrary.models.Environment import Environment
        from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier, VerificationException
    except ImportError as exc:
        raise StoreKitTransactionError("App Store Server Library is not packaged.") from exc

    try:
        verifier_environment = Environment(environment)
    except ValueError as exc:
        raise StoreKitTransactionError("StoreKit notification environment is not supported.") from exc

    root_certificates = (
        []
        if environment in LOCAL_STOREKIT_ENVIRONMENTS
        else _load_root_certificates(root_certificates_dir)
    )
    failures: list[str] = []
    for bundle_id in bundle_ids:
        verifier = SignedDataVerifier(
            root_certificates,
            enable_online_checks,
            verifier_environment,
            bundle_id,
            app_apple_id,
        )
        try:
            method = getattr(verifier, "verify_and_decode_notification", None)
            if method is None:
                method = getattr(verifier, "verify_and_decode_signed_notification", None)
            if method is None:
                raise StoreKitTransactionError("App Store Server Library cannot verify notifications.")
            return method(signed_payload)
        except VerificationException as exc:
            failures.append(str(exc))

    detail = f" ({'; '.join(failures)})" if failures else ""
    raise StoreKitTransactionError(f"StoreKit notification could not be verified{detail}.")


def _transaction_result(
    *,
    product: StoreKitProduct,
    product_id: str,
    transaction_id: str,
    original_transaction_id: str,
    environment: str,
    purchase_date: str | None,
    expiration_date: str | None,
) -> dict[str, Any]:
    return {
        "product": product,
        "productId": product_id,
        "transactionId": transaction_id,
        "originalTransactionId": original_transaction_id,
        "environment": environment,
        "purchaseDate": purchase_date,
        "expirationDate": expiration_date,
    }


def _product_for_id(product_id: str) -> StoreKitProduct:
    product = PRODUCTS.get(product_id)
    if product is None:
        raise StoreKitTransactionError("StoreKit product is not configured for Lisdo.")

    plan_id = product.plan_id
    if plan_id is not None and plan_id not in KNOWN_PLANS:
        raise StoreKitTransactionError("StoreKit product maps to an unknown plan.")
    return product


def _load_root_certificates(root_certificates_dir: str | None) -> list[bytes]:
    if root_certificates_dir is None:
        raise StoreKitTransactionError("StoreKit root certificates are not configured.")
    cert_dir = Path(root_certificates_dir)
    certificates = [path.read_bytes() for path in sorted(cert_dir.glob("*.cer")) if path.is_file()]
    if not certificates:
        raise StoreKitTransactionError("StoreKit root certificates are not configured.")
    return certificates


def _decode_jws_payload(jws: str) -> dict[str, Any]:
    parts = jws.split(".")
    if len(parts) != 3:
        raise StoreKitTransactionError("StoreKit signedTransactionInfo is not a valid JWS.")
    try:
        payload = parts[1] + ("=" * (-len(parts[1]) % 4))
        decoded = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise StoreKitTransactionError("StoreKit signedTransactionInfo payload is invalid.") from exc
    if not isinstance(decoded, dict):
        raise StoreKitTransactionError("StoreKit signedTransactionInfo payload is invalid.")
    return decoded


def _payload_value(payload: Any, key: str) -> Any:
    if isinstance(payload, dict):
        return payload.get(key)
    return getattr(payload, key, None)


def _payload_required_string(payload: Any, key: str) -> str:
    value = _payload_value(payload, key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    if isinstance(value, int):
        return str(value)
    raise StoreKitTransactionError(f"StoreKit transaction is missing {key}.")


def _payload_optional_string(payload: Any, key: str) -> str | None:
    value = _payload_value(payload, key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    if isinstance(value, int):
        return str(value)
    return None


def _payload_environment(payload: Any) -> str:
    value = _payload_value(payload, "environment")
    if hasattr(value, "value"):
        value = value.value
    if isinstance(value, str) and value.strip():
        return value.strip()
    raise StoreKitTransactionError("StoreKit transaction is missing environment.")


def _notification_data(payload: Any) -> Any:
    data = _payload_value(payload, "data")
    if data is None:
        raise StoreKitTransactionError("StoreKit notification data is missing.")
    return data


def _notification_action(notification_type: str) -> str:
    if notification_type in STOREKIT_GRANT_NOTIFICATION_TYPES:
        return "grant"
    if notification_type in STOREKIT_REVOKE_NOTIFICATION_TYPES:
        return "revoke"
    return "ignored"


def _payload_millis_to_iso(payload: Any, key: str) -> str | None:
    value = _payload_value(payload, key)
    if value is None:
        return None
    if isinstance(value, str):
        stripped = value.strip()
        if stripped.isdigit():
            value = int(stripped)
        else:
            return stripped or None
    if not isinstance(value, int | float):
        return None
    seconds = float(value) / 1000
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _validate_optional_match(body: dict[str, Any], key: str, expected: str) -> None:
    value = _optional_string(body, key)
    if value is not None and value != expected:
        raise StoreKitTransactionError(f"StoreKit transaction {key} does not match signed payload.")


def _required_string(body: dict[str, Any], key: str) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise StoreKitTransactionError(f"StoreKit transaction is missing {key}.")
    return value.strip()


def _optional_string(body: dict[str, Any], key: str) -> str | None:
    value = body.get(key)
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None
