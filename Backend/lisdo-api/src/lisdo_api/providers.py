from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any


class ProviderError(RuntimeError):
    """Raised when an upstream draft provider fails without exposing secrets."""


DETERMINISTIC_DRAFT_JSON: dict[str, Any] = {
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

_OPENAI_API_KEY_CACHE: dict[str, str] = {}


def deterministic_draft(chat_request: dict[str, Any]) -> dict[str, Any]:
    del chat_request
    draft_json = json.loads(json.dumps(DETERMINISTIC_DRAFT_JSON))
    return {
        "draftJSON": _draft_json_text(draft_json),
        "draft": draft_from_draft_json(draft_json),
        "usage": {
            "source": "deterministic-local",
            "model": "none",
        },
    }


def generate_draft(chat_request: dict[str, Any], *args: Any, **kwargs: Any) -> dict[str, Any]:
    del args, kwargs
    api_key = _openai_api_key()
    if not api_key:
        return deterministic_draft(chat_request)

    base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    timeout = _float_env("OPENAI_TIMEOUT_SECONDS", 30.0)
    endpoint = f"{base_url}/chat/completions"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(chat_request).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, TimeoutError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise ProviderError("Provider request failed.") from exc

    draft_json = _extract_draft_json(payload)
    provider_usage = _usage_from_provider_payload(payload)
    return {
        "draftJSON": _draft_json_text(draft_json),
        "draft": draft_from_draft_json(draft_json),
        "usage": {
            "source": "openai-compatible",
            "model": payload.get("model") or chat_request.get("model") or "unknown",
            **provider_usage,
        },
    }


def draft_from_draft_json(draft_json: dict[str, Any]) -> dict[str, Any]:
    blocks: list[dict[str, Any]] = []
    for block in draft_json.get("blocks", []):
        if not isinstance(block, dict):
            continue
        block_type = block.get("type")
        content = block.get("content")
        if not isinstance(content, str):
            continue
        blocks.append(
            {
                "kind": "task" if block_type == "checkbox" else str(block_type or "note"),
                "text": content,
                "checked": bool(block.get("checked", False)),
            }
        )

    return {
        "status": "draft",
        "title": str(draft_json.get("title") or "Review captured task"),
        "recommendedCategoryId": str(draft_json.get("recommendedCategoryId") or "inbox"),
        "summary": str(draft_json.get("summary") or ""),
        "blocks": blocks,
        "needsClarification": bool(draft_json.get("needsClarification", False)),
        "questionsForUser": _string_list(draft_json.get("questionsForUser")),
    }


def _extract_draft_json(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        content = payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ProviderError("Provider response missing draft content.") from exc

    if isinstance(content, dict):
        return content
    if not isinstance(content, str):
        raise ProviderError("Provider response content is not JSON text.")

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as exc:
        raise ProviderError("Provider returned invalid draft JSON.") from exc
    if not isinstance(parsed, dict):
        raise ProviderError("Provider returned non-object draft JSON.")
    return parsed


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _usage_from_provider_payload(payload: dict[str, Any]) -> dict[str, int]:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return {}

    normalized: dict[str, int] = {}
    prompt_tokens = _nonnegative_int(usage.get("prompt_tokens"))
    completion_tokens = _nonnegative_int(usage.get("completion_tokens"))
    total_tokens = _nonnegative_int(usage.get("total_tokens"))
    if prompt_tokens is not None:
        normalized["promptTokens"] = prompt_tokens
    if completion_tokens is not None:
        normalized["completionTokens"] = completion_tokens
    if total_tokens is not None:
        normalized["totalTokens"] = total_tokens

    prompt_details = usage.get("prompt_tokens_details")
    if isinstance(prompt_details, dict):
        cached_tokens = _nonnegative_int(prompt_details.get("cached_tokens"))
        if cached_tokens is not None:
            normalized["cachedInputTokens"] = cached_tokens
    return normalized


def _draft_json_text(draft_json: dict[str, Any]) -> str:
    return json.dumps(draft_json, separators=(",", ":"))


def _float_env(name: str, default: float) -> float:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    try:
        return float(raw_value)
    except ValueError:
        return default


def _openai_api_key() -> str | None:
    direct_key = _nonempty_env("OPENAI_API_KEY")
    if direct_key is not None:
        return direct_key

    parameter_name = _nonempty_env("OPENAI_API_KEY_PARAMETER_NAME")
    if parameter_name is None:
        return None
    if parameter_name in _OPENAI_API_KEY_CACHE:
        return _OPENAI_API_KEY_CACHE[parameter_name]

    try:
        import boto3  # type: ignore[import-not-found]

        response = boto3.client("ssm").get_parameter(Name=parameter_name, WithDecryption=True)
    except Exception as exc:
        if _is_ssm_parameter_not_found(exc):
            return None
        raise ProviderError("Provider secret lookup failed.") from exc

    value = ((response.get("Parameter") or {}).get("Value") or "").strip()
    if not value:
        return None
    _OPENAI_API_KEY_CACHE[parameter_name] = value
    return value


def _nonempty_env(name: str) -> str | None:
    value = os.environ.get(name)
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _nonnegative_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return max(0, value)
    return None


def _is_ssm_parameter_not_found(exc: Exception) -> bool:
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return False
    error = response.get("Error")
    if not isinstance(error, dict):
        return False
    return error.get("Code") == "ParameterNotFound"
