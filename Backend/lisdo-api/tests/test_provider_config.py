from __future__ import annotations

import importlib
import json
import sys
import types
from typing import Any

from conftest import STRICT_DRAFT_FIELDS, draft_generation_body


class _FakeSSMClient:
    def __init__(self, value: str | None) -> None:
        self.value = value
        self.calls: list[dict[str, Any]] = []

    def get_parameter(self, **kwargs: Any) -> dict[str, Any]:
        self.calls.append(kwargs)
        if self.value is None:
            raise _FakeParameterNotFound
        return {"Parameter": {"Value": self.value}}


class _FakeParameterNotFound(Exception):
    response = {"Error": {"Code": "ParameterNotFound"}}


class _FakeHTTPResponse:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    def __enter__(self) -> "_FakeHTTPResponse":
        return self

    def __exit__(self, *args: Any) -> None:
        del args

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


def _install_fake_boto3(monkeypatch, client: _FakeSSMClient) -> None:
    fake_boto3 = types.SimpleNamespace(client=lambda service: client)
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)


def _reload_providers(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    sys.modules.pop("lisdo_api.providers", None)
    return importlib.import_module("lisdo_api.providers")


def test_generate_draft_reads_openai_key_from_ssm_parameter(monkeypatch) -> None:
    ssm = _FakeSSMClient("ssm-openai-key")
    _install_fake_boto3(monkeypatch, ssm)
    monkeypatch.setenv("OPENAI_API_KEY_PARAMETER_NAME", "/lisdo/staging/openai/api-key")
    providers = _reload_providers(monkeypatch)

    captured_request: dict[str, Any] = {}
    draft_json = {
        "recommendedCategoryId": "inbox",
        "confidence": 0.7,
        "title": "Review captured task",
        "summary": "Review before saving.",
        "blocks": [{"type": "checkbox", "content": "Review before saving.", "checked": False}],
        "dueDateText": None,
        "priority": None,
        "needsClarification": False,
        "questionsForUser": [],
    }

    def urlopen(request: Any, *, timeout: float) -> _FakeHTTPResponse:
        captured_request["authorization"] = request.get_header("Authorization")
        captured_request["timeout"] = timeout
        return _FakeHTTPResponse(
            {
                "model": "gpt-test",
                "choices": [{"message": {"content": json.dumps(draft_json)}}],
            }
        )

    monkeypatch.setattr(providers.urllib.request, "urlopen", urlopen)

    result = providers.generate_draft(draft_generation_body()["chatRequest"])

    assert ssm.calls == [
        {
            "Name": "/lisdo/staging/openai/api-key",
            "WithDecryption": True,
        }
    ]
    assert captured_request == {"authorization": "Bearer ssm-openai-key", "timeout": 30.0}
    assert set(json.loads(result["draftJSON"])) == STRICT_DRAFT_FIELDS
    assert result["usage"] == {"source": "openai-compatible", "model": "gpt-test"}


def test_missing_ssm_openai_key_falls_back_to_deterministic_draft(monkeypatch) -> None:
    ssm = _FakeSSMClient(None)
    _install_fake_boto3(monkeypatch, ssm)
    monkeypatch.setenv("OPENAI_API_KEY_PARAMETER_NAME", "/lisdo/staging/openai/api-key")
    providers = _reload_providers(monkeypatch)

    result = providers.generate_draft(draft_generation_body()["chatRequest"])

    assert ssm.calls == [
        {
            "Name": "/lisdo/staging/openai/api-key",
            "WithDecryption": True,
        }
    ]
    assert result["usage"] == {"source": "deterministic-local", "model": "none"}
    assert set(json.loads(result["draftJSON"])) == STRICT_DRAFT_FIELDS
