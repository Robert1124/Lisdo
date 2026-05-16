from __future__ import annotations

import pytest

from lisdo_api.entitlements import draft_model_for_plan


@pytest.mark.parametrize(
    ("plan_id", "expected_model"),
    [
        ("starterTrial", "gpt-5-mini"),
        ("monthlyBasic", "gpt-5-mini"),
        ("monthlyPlus", "gpt-5.4-mini"),
        ("monthlyMax", "gpt-5.4-mini"),
        ("free", "gpt-5-mini"),
        ("unknown", "gpt-5-mini"),
    ],
)
def test_draft_model_for_plan_uses_server_plan_model(plan_id: str, expected_model: str) -> None:
    assert draft_model_for_plan(plan_id) == expected_model
