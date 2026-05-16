from __future__ import annotations

import json
from typing import Any

from lisdo_api import providers


class _FakeHTTPResponse:
    def __init__(self, payload: dict[str, Any]) -> None:
        self._payload = payload

    def __enter__(self) -> "_FakeHTTPResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self._payload).encode("utf-8")


def test_generate_draft_returns_compact_draft_json_text(monkeypatch) -> None:
    draft_json = {
        "recommendedCategoryId": "research",
        "confidence": 0.74,
        "title": "Summarize paper notes",
        "summary": "Review the notes and turn the open questions into research steps.",
        "blocks": [
            {
                "type": "checkbox",
                "content": "Identify the main research questions",
                "checked": False,
            }
        ],
        "dueDateText": "Friday",
        "priority": "medium",
        "needsClarification": False,
        "questionsForUser": [],
    }
    provider_payload = {
        "model": "provider-model",
        "choices": [
            {
                "message": {
                    "content": json.dumps(draft_json),
                }
            }
        ],
        "usage": {
            "prompt_tokens": 321,
            "completion_tokens": 45,
            "total_tokens": 366,
            "prompt_tokens_details": {
                "cached_tokens": 100,
            },
        },
    }

    def urlopen(request: Any, *, timeout: float) -> _FakeHTTPResponse:
        assert timeout == 30.0
        return _FakeHTTPResponse(provider_payload)

    monkeypatch.setenv("OPENAI_API_KEY", "test-provider-key")
    monkeypatch.delenv("OPENAI_TIMEOUT_SECONDS", raising=False)
    monkeypatch.setattr(providers.urllib.request, "urlopen", urlopen)

    result = providers.generate_draft({"model": "requested-model", "messages": []})

    assert isinstance(result["draftJSON"], str)
    assert result["draftJSON"] == json.dumps(draft_json, separators=(",", ":"))
    assert json.loads(result["draftJSON"]) == draft_json
    assert result["draft"]["status"] == "draft"
    assert result["draft"]["title"] == "Summarize paper notes"
    assert result["usage"] == {
        "source": "openai-compatible",
        "model": "provider-model",
        "promptTokens": 321,
        "completionTokens": 45,
        "totalTokens": 366,
        "cachedInputTokens": 100,
    }
