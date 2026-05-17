from __future__ import annotations

import html
import json
import logging
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any

from .config import DevConfig
from .quota import load_account_profile

LOGGER = logging.getLogger(__name__)

RESEND_EMAILS_URL = "https://api.resend.com/emails"
RESEND_USER_AGENT = "lisdo-api/1.0"
_SECRET_CACHE: dict[str, str] = {}


class EmailConfigurationError(Exception):
    pass


class EmailDeliveryError(Exception):
    pass


@dataclass(frozen=True)
class EmailResult:
    status: str
    id: str | None = None
    error: str | None = None

    def response(self) -> dict[str, str]:
        body = {"status": self.status}
        if self.id:
            body["id"] = self.id
        if self.error:
            body["error"] = self.error
        return body


def send_welcome_email(config: DevConfig, *, is_new_account: bool) -> EmailResult:
    if not is_new_account:
        return EmailResult("skipped_existing_account")
    profile = load_account_profile(config)
    recipient = _profile_email(profile)
    if recipient is None:
        return EmailResult("skipped_no_email")
    display_name = profile.get("displayName") or recipient.split("@", 1)[0]
    html_body = _email_card(
        eyebrow="Welcome",
        title="Welcome to Lisdo",
        body=(
            f"Hi {_escape(display_name)}, your Lisdo account is ready. "
            "Capture now, review before saving, and keep AI output draft-first."
        ),
        rows=[
            ("Account", recipient),
            ("Plan", "Free"),
            ("Flow", "Capture -> draft -> review -> todo"),
        ],
        cta_label="Open Personal Center",
        cta_url=config.app_base_url,
    )
    return _safe_send(
        config,
        to=recipient,
        subject="Welcome to Lisdo",
        html_body=html_body,
        idempotency_key=f"welcome:{config.account_id}",
        tags={"kind": "welcome", "account": _tag_value(config.account_id)},
    )


def send_billing_success_email(
    config: DevConfig,
    *,
    product_name: str,
    is_renewal: bool,
    event_id: str,
    invoice_id: str | None = None,
    hosted_invoice_url: str | None = None,
    invoice_pdf_url: str | None = None,
) -> EmailResult:
    profile = load_account_profile(config)
    recipient = _profile_email(profile)
    if recipient is None:
        return EmailResult("skipped_no_email")

    title = f"{product_name} renewed" if is_renewal else f"{product_name} purchase confirmed"
    subject = "Lisdo renewal receipt" if is_renewal else "Lisdo purchase receipt"
    body = (
        "Your renewal succeeded and your Lisdo quota has been refreshed."
        if is_renewal
        else "Your purchase succeeded and your Lisdo plan is ready to use."
    )
    rows = [
        ("Plan", product_name),
        ("Status", "Renewed" if is_renewal else "Paid"),
    ]
    if invoice_id:
        rows.append(("Invoice", invoice_id))
    attachments = []
    if invoice_pdf_url and invoice_id:
        attachments.append(
            {
                "filename": f"Lisdo-invoice-{invoice_id}.pdf",
                "path": invoice_pdf_url,
            }
        )
    html_body = _email_card(
        eyebrow="Receipt",
        title=title,
        body=body,
        rows=rows,
        cta_label="View invoice" if hosted_invoice_url else "Open Personal Center",
        cta_url=hosted_invoice_url or config.app_base_url,
    )
    return _safe_send(
        config,
        to=recipient,
        subject=subject,
        html_body=html_body,
        idempotency_key=f"billing:{event_id}",
        attachments=attachments,
        tags={"kind": "billing", "account": _tag_value(config.account_id)},
    )


def send_update_email(
    config: DevConfig,
    *,
    to: str,
    subject: str,
    title: str,
    body: str,
    cta_label: str = "View update",
    cta_url: str | None = None,
    idempotency_key: str | None = None,
) -> EmailResult:
    recipient = _normalize_email(to)
    if recipient is None:
        return EmailResult("skipped_no_email")
    html_body = _email_card(
        eyebrow="Update",
        title=title,
        body=body,
        rows=[],
        cta_label=cta_label,
        cta_url=cta_url or config.app_base_url,
    )
    return _safe_send(
        config,
        to=recipient,
        subject=subject,
        html_body=html_body,
        idempotency_key=idempotency_key,
        tags={"kind": "update", "account": _tag_value(config.account_id)},
    )


def _safe_send(
    config: DevConfig,
    *,
    to: str,
    subject: str,
    html_body: str,
    idempotency_key: str | None,
    tags: dict[str, str],
    attachments: list[dict[str, str]] | None = None,
) -> EmailResult:
    if not config.emails_enabled:
        return EmailResult("disabled")
    try:
        return _send_resend_email(
            config,
            to=to,
            subject=subject,
            html_body=html_body,
            idempotency_key=idempotency_key,
            tags=tags,
            attachments=attachments or [],
        )
    except EmailConfigurationError as exc:
        LOGGER.info("email_not_configured", extra={"reason": str(exc), "accountId": config.account_id})
        return EmailResult("not_configured", error=str(exc))
    except Exception as exc:
        LOGGER.warning(
            "email_delivery_failed",
            extra={"errorType": type(exc).__name__, "accountId": config.account_id},
            exc_info=True,
        )
        return EmailResult("failed", error="Email could not be sent.")


def _send_resend_email(
    config: DevConfig,
    *,
    to: str,
    subject: str,
    html_body: str,
    idempotency_key: str | None,
    tags: dict[str, str],
    attachments: list[dict[str, str]],
) -> EmailResult:
    api_key = _resend_api_key(config)
    payload: dict[str, Any] = {
        "from": config.email_from,
        "to": [to],
        "subject": subject,
        "html": html_body,
        "tags": [{"name": name, "value": value} for name, value in tags.items()],
    }
    if attachments:
        payload["attachments"] = attachments
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": RESEND_USER_AGENT,
    }
    if idempotency_key:
        headers["Idempotency-Key"] = idempotency_key[:256]
    request = urllib.request.Request(RESEND_EMAILS_URL, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            raw_body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise EmailDeliveryError(f"Resend returned HTTP {exc.code}.") from exc
    except urllib.error.URLError as exc:
        raise EmailDeliveryError("Resend request failed.") from exc

    try:
        body = json.loads(raw_body) if raw_body else {}
    except json.JSONDecodeError:
        body = {}
    email_id = body.get("id") if isinstance(body, dict) else None
    return EmailResult("sent", id=email_id if isinstance(email_id, str) else None)


def _resend_api_key(config: DevConfig) -> str:
    direct_value = _nonempty(os.environ.get("RESEND_API_KEY"))
    if direct_value is not None:
        return direct_value
    parameter_name = config.resend_api_key_parameter_name
    if parameter_name is None:
        raise EmailConfigurationError("Resend API key is not configured.")
    if parameter_name in _SECRET_CACHE:
        return _SECRET_CACHE[parameter_name]
    try:
        import boto3  # type: ignore[import-not-found]

        response = boto3.client("ssm").get_parameter(Name=parameter_name, WithDecryption=True)
    except Exception as exc:
        raise EmailConfigurationError("Resend API key lookup failed.") from exc

    value = _nonempty(((response.get("Parameter") or {}).get("Value") or ""))
    if value is None:
        raise EmailConfigurationError("Resend API key is not configured.")
    _SECRET_CACHE[parameter_name] = value
    return value


def _email_card(
    *,
    eyebrow: str,
    title: str,
    body: str,
    rows: list[tuple[str, str]],
    cta_label: str,
    cta_url: str,
) -> str:
    rows_html = "".join(
        f"""
        <tr>
          <td style="padding: 14px 0; color: #6e6e73; font-size: 13px; border-top: 1px solid #e5e5e5;">{_escape(label)}</td>
          <td style="padding: 14px 0; color: #0e0e0e; font-size: 13px; font-weight: 600; text-align: right; border-top: 1px solid #e5e5e5;">{_escape(value)}</td>
        </tr>
        """
        for label, value in rows
    )
    return f"""<!doctype html>
<html>
  <body style="margin: 0; padding: 0; background: #f4f4f2; color: #0e0e0e; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background: #f4f4f2; padding: 28px 14px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 560px; background: #ffffff; border: 1px solid #e5e5e5; border-radius: 28px; overflow: hidden; box-shadow: 0 18px 44px rgba(0,0,0,0.08);">
            <tr>
              <td style="padding: 28px;">
                <div style="display: inline-block; padding: 7px 11px; border-radius: 999px; background: #f4f4f2; color: #6e6e73; font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase;">{_escape(eyebrow)}</div>
                <h1 style="margin: 18px 0 10px; color: #0e0e0e; font-size: 30px; line-height: 1.08; font-weight: 700; letter-spacing: 0;">{_escape(title)}</h1>
                <p style="margin: 0 0 22px; color: #2c2c2e; font-size: 15px; line-height: 1.55;">{_escape(body)}</p>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse: collapse;">
                  {rows_html}
                </table>
                <div style="margin-top: 24px;">
                  <a href="{_escape(cta_url)}" style="display: inline-block; background: #0e0e0e; color: #ffffff; text-decoration: none; border-radius: 999px; padding: 13px 18px; font-size: 14px; font-weight: 700;">{_escape(cta_label)}</a>
                </div>
              </td>
            </tr>
          </table>
          <p style="margin: 18px 0 0; color: #a1a1a6; font-size: 12px;">Lisdo sends AI output to draft review before anything becomes a todo.</p>
        </td>
      </tr>
    </table>
  </body>
</html>"""


def _profile_email(profile: dict[str, str]) -> str | None:
    return _normalize_email(profile.get("email"))


def _normalize_email(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if "@" not in normalized or len(normalized) > 254:
        return None
    return normalized


def _escape(value: Any) -> str:
    return html.escape(str(value), quote=True)


def _tag_value(value: str) -> str:
    return "".join(character if character.isalnum() or character in {"_", "-"} else "_" for character in value)[:256] or "unknown"


def _nonempty(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None
