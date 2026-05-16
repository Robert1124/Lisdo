from __future__ import annotations

import base64
import hashlib
import json
import time
import urllib.request
from dataclasses import dataclass
from typing import Any

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
SHA256_DIGEST_INFO_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")

_JWKS_CACHE: dict[str, Any] | None = None


class AppleIdentityTokenError(ValueError):
    pass


@dataclass(frozen=True)
class AppleIdentity:
    subject: str
    email: str | None
    audience: str


def verify_apple_identity_token(
    identity_token: str,
    *,
    client_ids: tuple[str, ...],
    verification_mode: str,
    expected_nonce: str | None = None,
    now: int | None = None,
) -> AppleIdentity:
    if not identity_token or identity_token.count(".") != 2:
        raise AppleIdentityTokenError("identityToken must be a compact JWT.")

    header, payload, signature = _jwt_parts(identity_token)
    if verification_mode == "unsigned-dev":
        claims = payload
    else:
        _verify_rs256_signature(identity_token, header, signature)
        claims = payload

    return _identity_from_claims(claims, client_ids=client_ids, expected_nonce=expected_nonce, now=now or int(time.time()))


def account_id_for_apple_subject(subject: str) -> str:
    digest = hashlib.sha256(f"apple:{subject}".encode("utf-8")).hexdigest()
    return f"apple-{digest[:32]}"


def _jwt_parts(token: str) -> tuple[dict[str, Any], dict[str, Any], bytes]:
    header_segment, payload_segment, signature_segment = token.split(".")
    try:
        header = json.loads(_base64url_decode(header_segment))
        payload = json.loads(_base64url_decode(payload_segment))
        signature = _base64url_decode(signature_segment)
    except (ValueError, json.JSONDecodeError) as exc:
        raise AppleIdentityTokenError("identityToken is not valid JWT JSON.") from exc

    if not isinstance(header, dict) or not isinstance(payload, dict):
        raise AppleIdentityTokenError("identityToken header and payload must be JSON objects.")
    return header, payload, signature


def _identity_from_claims(
    claims: dict[str, Any],
    *,
    client_ids: tuple[str, ...],
    expected_nonce: str | None,
    now: int,
) -> AppleIdentity:
    if claims.get("iss") != APPLE_ISSUER:
        raise AppleIdentityTokenError("identityToken issuer is not Apple.")

    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject.strip():
        raise AppleIdentityTokenError("identityToken is missing an Apple subject.")

    audience = claims.get("aud")
    if isinstance(audience, list):
        valid_audiences = {value for value in audience if isinstance(value, str)}
        audience_value = next(iter(valid_audiences), "")
    elif isinstance(audience, str):
        valid_audiences = {audience}
        audience_value = audience
    else:
        raise AppleIdentityTokenError("identityToken is missing an audience.")

    if client_ids and valid_audiences.isdisjoint(client_ids):
        raise AppleIdentityTokenError("identityToken audience is not configured for Lisdo.")

    expiration = claims.get("exp")
    if not isinstance(expiration, int) or expiration <= now:
        raise AppleIdentityTokenError("identityToken is expired.")

    if expected_nonce is not None:
        token_nonce = claims.get("nonce")
        if not isinstance(token_nonce, str) or token_nonce != expected_nonce:
            raise AppleIdentityTokenError("identityToken nonce does not match the browser sign-in request.")

    email = claims.get("email")
    return AppleIdentity(
        subject=subject.strip(),
        email=email.strip() if isinstance(email, str) and email.strip() else None,
        audience=audience_value,
    )


def _verify_rs256_signature(token: str, header: dict[str, Any], signature: bytes) -> None:
    if header.get("alg") != "RS256":
        raise AppleIdentityTokenError("identityToken must use RS256.")

    key_id = header.get("kid")
    if not isinstance(key_id, str):
        raise AppleIdentityTokenError("identityToken is missing a key id.")

    jwk = _apple_jwk_for_key_id(key_id)
    n = int.from_bytes(_base64url_decode(jwk["n"]), "big")
    e = int.from_bytes(_base64url_decode(jwk["e"]), "big")
    signing_input = token.rsplit(".", 1)[0].encode("ascii")
    digest_info = SHA256_DIGEST_INFO_PREFIX + hashlib.sha256(signing_input).digest()

    modulus_length = (n.bit_length() + 7) // 8
    signature_int = int.from_bytes(signature, "big")
    encoded_message = pow(signature_int, e, n).to_bytes(modulus_length, "big")
    expected_prefix = b"\x00\x01"
    separator_index = encoded_message.find(b"\x00", len(expected_prefix))

    if (
        not encoded_message.startswith(expected_prefix)
        or separator_index < 10
        or encoded_message[2:separator_index] != b"\xff" * (separator_index - 2)
        or encoded_message[separator_index + 1 :] != digest_info
    ):
        raise AppleIdentityTokenError("identityToken signature is invalid.")


def _apple_jwk_for_key_id(key_id: str) -> dict[str, str]:
    jwks = _apple_jwks()
    for key in jwks.get("keys", []):
        if isinstance(key, dict) and key.get("kid") == key_id and key.get("kty") == "RSA":
            return key
    raise AppleIdentityTokenError("identityToken key id is not currently published by Apple.")


def _apple_jwks() -> dict[str, Any]:
    global _JWKS_CACHE
    if _JWKS_CACHE is not None:
        return _JWKS_CACHE

    with urllib.request.urlopen(APPLE_JWKS_URL, timeout=5) as response:
        _JWKS_CACHE = json.loads(response.read().decode("utf-8"))
    return _JWKS_CACHE


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)
