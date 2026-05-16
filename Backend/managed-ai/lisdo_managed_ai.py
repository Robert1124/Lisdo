#!/usr/bin/env python3
"""Local dev backend contract for Lisdo Managed AI.

This module intentionally uses only the Python standard library so it can run
anywhere during app integration work. It is not production auth or storage.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


DEFAULT_LEDGER_PATH = "/tmp/lisdo-managed-ai-ledger.json"
DEFAULT_USER_ID = "dev-user"
OPENAI_CHAT_COMPLETIONS_URL = "https://api.openai.com/v1/chat/completions"

LEDGER_LOCK = threading.Lock()


PLAN_DEFAULTS = {
    "free": {
        "managedDrafts": False,
        "realtimeProcessing": False,
        "iCloudSync": False,
        "monthlyQuota": 0,
        "isMonthly": False,
    },
    "starterTrial": {
        "managedDrafts": True,
        "realtimeProcessing": True,
        "iCloudSync": False,
        "monthlyQuota": 25,
        "isMonthly": False,
    },
    "monthlyBasic": {
        "managedDrafts": True,
        "realtimeProcessing": False,
        "iCloudSync": True,
        "monthlyQuota": 500,
        "isMonthly": True,
    },
    "monthlyPlus": {
        "managedDrafts": True,
        "realtimeProcessing": False,
        "iCloudSync": True,
        "monthlyQuota": 1200,
        "isMonthly": True,
    },
    "monthlyMax": {
        "managedDrafts": True,
        "realtimeProcessing": True,
        "iCloudSync": True,
        "monthlyQuota": 2000,
        "isMonthly": True,
    },
}


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    del context
    method = _event_method(event)
    path = _event_path(event)

    try:
        if method == "GET" and path == "/v1/me/entitlements":
            return _json_response(200, entitlement_summary())

        if method == "POST" and path == "/v1/dev/entitlements/set-plan":
            payload = _json_body(event)
            return _json_response(200, set_plan(payload))

        if method == "POST" and path == "/v1/drafts/generate":
            return _handle_generate_draft(event)

        return _json_response(404, {"error": {"code": "not_found", "message": "Route not found."}})
    except ValueError as exc:
        return _json_response(400, {"error": {"code": "bad_request", "message": str(exc)}})


def entitlement_summary() -> dict[str, Any]:
    ledger = _read_ledger()
    return _summary_from_ledger(ledger)


def set_plan(payload: dict[str, Any]) -> dict[str, Any]:
    plan_id = payload.get("planId")
    if not isinstance(plan_id, str) or not plan_id:
        raise ValueError("planId is required.")

    plan = _plan_for(plan_id)
    monthly_remaining = payload.get("monthlyQuotaRemaining", plan["monthlyQuota"])
    top_up_credits = payload.get("topUpCredits", 0)

    if not isinstance(monthly_remaining, int) or monthly_remaining < 0:
        raise ValueError("monthlyQuotaRemaining must be a non-negative integer.")
    if not isinstance(top_up_credits, int) or top_up_credits < 0:
        raise ValueError("topUpCredits must be a non-negative integer.")

    ledger = {
        "userId": DEFAULT_USER_ID,
        "planId": plan_id,
        "monthlyRemaining": monthly_remaining,
        "topUpRemaining": top_up_credits,
        "monthlyConsumed": 0,
        "topUpConsumed": 0,
        "updatedAt": _now_timestamp(),
    }
    _write_ledger(ledger)
    return _summary_from_ledger(ledger)


def _handle_generate_draft(event: dict[str, Any]) -> dict[str, Any]:
    if not _has_bearer_token(event.get("headers") or {}):
        return _json_response(
            401,
            {"error": {"code": "missing_authorization", "message": "Authorization bearer token is required."}},
        )

    payload = _json_body(event)
    chat_request = _chat_request_from_payload(payload)
    reserve = _reserve_quota()
    if "error" in reserve:
        return _json_response(reserve["statusCode"], {"error": reserve["error"]})

    try:
        draft_json, usage = generate_draft(chat_request)
    except Exception as exc:
        _refund_quota(reserve["bucket"])
        return _json_response(
            502,
            {"error": {"code": "provider_error", "message": _safe_provider_error_message(exc)}},
        )

    usage["quotaBucket"] = reserve["bucket"]
    return _json_response(200, {"draftJSON": draft_json, "usage": usage})


def generate_draft(chat_request: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    api_key = os.environ.get("OPENAI_API_KEY")
    if api_key:
        return _proxy_openai_chat_completion(chat_request, api_key)
    return _deterministic_draft(chat_request)


def _reserve_quota() -> dict[str, Any]:
    with LEDGER_LOCK:
        ledger = _read_ledger_unlocked()
        plan = _plan_for(ledger["planId"])

        if not plan["managedDrafts"]:
            return {
                "statusCode": 402,
                "error": {
                    "code": "managed_drafts_unavailable",
                    "message": "The current plan cannot use Lisdo Managed AI drafts.",
                },
            }

        if ledger["monthlyRemaining"] > 0:
            ledger["monthlyRemaining"] -= 1
            ledger["monthlyConsumed"] += 1
            ledger["updatedAt"] = _now_timestamp()
            _write_ledger_unlocked(ledger)
            return {"bucket": "monthly"}

        if plan["isMonthly"] and ledger["topUpRemaining"] > 0:
            ledger["topUpRemaining"] -= 1
            ledger["topUpConsumed"] += 1
            ledger["updatedAt"] = _now_timestamp()
            _write_ledger_unlocked(ledger)
            return {"bucket": "topUp"}

        return {
            "statusCode": 402,
            "error": {"code": "quota_exhausted", "message": "Managed AI quota is exhausted."},
        }


def _refund_quota(bucket: str) -> None:
    with LEDGER_LOCK:
        ledger = _read_ledger_unlocked()
        if bucket == "monthly" and ledger["monthlyConsumed"] > 0:
            ledger["monthlyRemaining"] += 1
            ledger["monthlyConsumed"] -= 1
        elif bucket == "topUp" and ledger["topUpConsumed"] > 0:
            ledger["topUpRemaining"] += 1
            ledger["topUpConsumed"] -= 1
        ledger["updatedAt"] = _now_timestamp()
        _write_ledger_unlocked(ledger)


def _proxy_openai_chat_completion(chat_request: dict[str, Any], api_key: str) -> tuple[str, dict[str, Any]]:
    body = json.dumps(chat_request).encode("utf-8")
    request = urllib.request.Request(
        OPENAI_CHAT_COMPLETIONS_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"OpenAI returned HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError("OpenAI request failed") from exc

    data = json.loads(raw)
    choices = data.get("choices")
    if not isinstance(choices, list) or not choices:
        raise RuntimeError("OpenAI response did not include choices")
    message = choices[0].get("message", {})
    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("OpenAI response did not include draft content")

    usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
    return content, {"source": "openai-chat-completions", **usage}


def _deterministic_draft(chat_request: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    prompt = _last_user_prompt(chat_request)
    normalized = _normalize_space(prompt)
    title = _title_from_prompt(normalized)
    category = _category_from_prompt(normalized)
    blocks = _blocks_from_prompt(normalized)

    draft = {
        "recommendedCategoryId": category,
        "confidence": 0.72,
        "title": title,
        "summary": _summary_from_prompt(normalized),
        "blocks": blocks,
        "dueDateText": _due_date_text(normalized),
        "priority": "medium",
        "needsClarification": False,
        "questionsForUser": [],
    }
    usage = {
        "source": "deterministic-local",
        "promptCharacters": len(prompt),
        "completionCharacters": len(json.dumps(draft, separators=(",", ":"))),
    }
    return json.dumps(draft, sort_keys=True), usage


def _event_method(event: dict[str, Any]) -> str:
    return str(event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method") or "").upper()


def _event_path(event: dict[str, Any]) -> str:
    path = event.get("path") or event.get("rawPath") or "/"
    return str(path).split("?", 1)[0]


def _json_body(event: dict[str, Any]) -> dict[str, Any]:
    raw_body = event.get("body")
    if raw_body in (None, ""):
        return {}
    if isinstance(raw_body, dict):
        return raw_body
    try:
        parsed = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise ValueError("Request body must be valid JSON.") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Request body must be a JSON object.")
    return parsed


def _chat_request_from_payload(payload: dict[str, Any]) -> dict[str, Any]:
    chat_request = payload.get("chatRequest", payload)
    if not isinstance(chat_request, dict):
        raise ValueError("chatRequest must be a JSON object.")

    messages = chat_request.get("messages")
    if not isinstance(messages, list) or not messages:
        raise ValueError("chatRequest.messages must be a non-empty array.")
    return chat_request


def _has_bearer_token(headers: dict[str, Any]) -> bool:
    auth_value = ""
    for key, value in headers.items():
        if str(key).lower() == "authorization":
            auth_value = str(value)
            break
    match = re.match(r"^\s*Bearer\s+(.+?)\s*$", auth_value, flags=re.IGNORECASE)
    return bool(match and match.group(1))


def _json_response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body, sort_keys=True),
    }


def _summary_from_ledger(ledger: dict[str, Any]) -> dict[str, Any]:
    plan = _plan_for(ledger["planId"])
    return {
        "userId": ledger["userId"],
        "planId": ledger["planId"],
        "entitlements": {
            "managedDrafts": plan["managedDrafts"],
            "realtimeProcessing": plan["realtimeProcessing"],
            "iCloudSync": plan["iCloudSync"],
        },
        "quota": {
            "monthlyRemaining": ledger["monthlyRemaining"],
            "topUpRemaining": ledger["topUpRemaining"] if plan["isMonthly"] else 0,
            "monthlyConsumed": ledger["monthlyConsumed"],
            "topUpConsumed": ledger["topUpConsumed"] if plan["isMonthly"] else 0,
        },
    }


def _plan_for(plan_id: str) -> dict[str, Any]:
    aliases = {
        "monthly": "monthlyBasic",
        "monthlyPro": "monthlyMax",
    }
    plan_id = aliases.get(plan_id, plan_id)
    if plan_id in PLAN_DEFAULTS:
        return PLAN_DEFAULTS[plan_id]
    if plan_id.startswith("monthly"):
        return PLAN_DEFAULTS["monthlyBasic"]
    return PLAN_DEFAULTS["free"]


def _read_ledger() -> dict[str, Any]:
    with LEDGER_LOCK:
        return _read_ledger_unlocked()


def _read_ledger_unlocked() -> dict[str, Any]:
    path = _ledger_path()
    if not path.exists():
        return _default_ledger()
    try:
        with path.open("r", encoding="utf-8") as file:
            data = json.load(file)
    except (OSError, json.JSONDecodeError):
        return _default_ledger()
    return _normalize_ledger(data)


def _write_ledger(ledger: dict[str, Any]) -> None:
    with LEDGER_LOCK:
        _write_ledger_unlocked(ledger)


def _write_ledger_unlocked(ledger: dict[str, Any]) -> None:
    path = _ledger_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(_normalize_ledger(ledger), file, indent=2, sort_keys=True)
            file.write("\n")
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def _ledger_path() -> Path:
    return Path(os.environ.get("LISDO_LEDGER_PATH", DEFAULT_LEDGER_PATH))


def _default_ledger() -> dict[str, Any]:
    return {
        "userId": DEFAULT_USER_ID,
        "planId": "free",
        "monthlyRemaining": 0,
        "topUpRemaining": 0,
        "monthlyConsumed": 0,
        "topUpConsumed": 0,
        "updatedAt": _now_timestamp(),
    }


def _normalize_ledger(data: dict[str, Any]) -> dict[str, Any]:
    default = _default_ledger()
    if not isinstance(data, dict):
        return default

    plan_id = data.get("planId") if isinstance(data.get("planId"), str) else default["planId"]
    return {
        "userId": data.get("userId") if isinstance(data.get("userId"), str) else DEFAULT_USER_ID,
        "planId": plan_id,
        "monthlyRemaining": _non_negative_int(data.get("monthlyRemaining"), default["monthlyRemaining"]),
        "topUpRemaining": _non_negative_int(data.get("topUpRemaining"), default["topUpRemaining"]),
        "monthlyConsumed": _non_negative_int(data.get("monthlyConsumed"), default["monthlyConsumed"]),
        "topUpConsumed": _non_negative_int(data.get("topUpConsumed"), default["topUpConsumed"]),
        "updatedAt": data.get("updatedAt") if isinstance(data.get("updatedAt"), str) else default["updatedAt"],
    }


def _non_negative_int(value: Any, fallback: int) -> int:
    if isinstance(value, int) and value >= 0:
        return value
    return fallback


def _last_user_prompt(chat_request: dict[str, Any]) -> str:
    messages = chat_request.get("messages", [])
    for message in reversed(messages):
        if isinstance(message, dict) and message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                pieces = []
                for item in content:
                    if isinstance(item, dict) and isinstance(item.get("text"), str):
                        pieces.append(item["text"])
                return " ".join(pieces)
    return ""


def _normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _title_from_prompt(prompt: str) -> str:
    words = re.findall(r"[A-Za-z0-9']+", prompt)
    if not words:
        return "Review captured note"
    title = " ".join(words[:8])
    return title[:1].upper() + title[1:]


def _summary_from_prompt(prompt: str) -> str:
    if not prompt:
        return "Review the captured source text and turn it into an approved todo."
    return prompt[:180]


def _category_from_prompt(prompt: str) -> str:
    lowered = prompt.lower()
    if any(token in lowered for token in ("buy", "shopping", "grocery", "store")):
        return "shopping"
    if any(token in lowered for token in ("paper", "research", "experiment", "study")):
        return "research"
    return "work"


def _blocks_from_prompt(prompt: str) -> list[dict[str, Any]]:
    parts = [part.strip(" .") for part in re.split(r"\b(?:and|then|also)\b|[;\n]", prompt) if part.strip(" .")]
    if not parts:
        parts = ["Review captured note"]
    return [{"type": "checkbox", "content": part[:160], "checked": False} for part in parts[:5]]


def _due_date_text(prompt: str) -> str | None:
    lowered = prompt.lower()
    patterns = (
        r"tomorrow[^,.]*",
        r"today[^,.]*",
        r"next [a-z]+[^,.]*",
        r"before [0-9]{1,2}(?::[0-9]{2})?\s*(?:am|pm)?",
    )
    for pattern in patterns:
        match = re.search(pattern, lowered)
        if match:
            return match.group(0).strip()
    return None


def _safe_provider_error_message(exc: Exception) -> str:
    message = str(exc) or "Provider request failed."
    return message[:120]


def _now_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class LocalManagedAIHandler(BaseHTTPRequestHandler):
    server_version = "LisdoManagedAIDev/1.0"

    def do_GET(self) -> None:
        self._handle()

    def do_POST(self) -> None:
        self._handle()

    def log_message(self, format: str, *args: Any) -> None:
        # Avoid logging headers, bearer tokens, or source text in local dev output.
        print(f"{self.address_string()} {self.command} {self.path.split('?', 1)[0]}")

    def _handle(self) -> None:
        body = self.rfile.read(_content_length(self.headers)).decode("utf-8") if self.command == "POST" else None
        event = {
            "httpMethod": self.command,
            "path": self.path.split("?", 1)[0],
            "headers": {key: value for key, value in self.headers.items()},
            "body": body,
        }
        response = lambda_handler(event, None)
        payload = response["body"].encode("utf-8")
        self.send_response(response["statusCode"])
        for key, value in response["headers"].items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def _content_length(headers: Any) -> int:
    try:
        return int(headers.get("Content-Length", "0"))
    except ValueError:
        return 0


def serve(port: int) -> None:
    server = ThreadingHTTPServer(("127.0.0.1", port), LocalManagedAIHandler)
    print(f"Lisdo Managed AI dev server listening on http://127.0.0.1:{port}")
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description="Lisdo Managed AI local dev backend.")
    parser.add_argument("--serve", action="store_true", help="Start the local HTTP server.")
    parser.add_argument("--port", type=int, default=8787, help="Port for --serve. Defaults to 8787.")
    args = parser.parse_args()

    if args.serve:
        serve(args.port)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
