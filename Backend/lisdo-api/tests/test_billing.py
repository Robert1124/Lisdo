from __future__ import annotations

from lisdo_api.billing import usage_cost_units


def test_usage_cost_units_charges_prompt_and_completion_tokens_for_plan_model() -> None:
    cost = usage_cost_units(
        "gpt-5.4-mini",
        {
            "promptTokens": 2_500,
            "completionTokens": 700,
            "totalTokens": 3_200,
        },
    )

    assert cost == {
        "inputTokens": 2_500,
        "outputTokens": 700,
        "totalTokens": 3_200,
        "cachedInputTokens": 0,
        "costUnits": 51,
    }


def test_usage_cost_units_applies_cached_input_discount_when_provider_reports_cached_tokens() -> None:
    cost = usage_cost_units(
        "gpt-5.4-mini",
        {
            "promptTokens": 2_500,
            "completionTokens": 700,
            "totalTokens": 3_200,
            "cachedInputTokens": 1_000,
        },
    )

    assert cost["cachedInputTokens"] == 1_000
    assert cost["costUnits"] == 44
