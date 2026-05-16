from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_CEILING
from typing import Any

LISDO_QUOTA_UNIT_USD = Decimal("0.0001")


@dataclass(frozen=True)
class ModelPricing:
    input_usd_per_million: Decimal
    output_usd_per_million: Decimal
    cached_input_usd_per_million: Decimal | None = None

    @property
    def effective_cached_input_usd_per_million(self) -> Decimal:
        return self.cached_input_usd_per_million or self.input_usd_per_million


MODEL_PRICING: dict[str, ModelPricing] = {
    "gpt-5-mini": ModelPricing(Decimal("0.25"), Decimal("2.00"), Decimal("0.025")),
    "gpt-5.4-mini": ModelPricing(Decimal("0.75"), Decimal("4.50"), Decimal("0.075")),
    "gpt-5.4": ModelPricing(Decimal("2.50"), Decimal("15.00"), Decimal("0.25")),
}


def usage_cost_units(model: str, usage: dict[str, Any] | None) -> dict[str, int]:
    prompt_tokens = _token_count(_first_present(usage, "promptTokens", "prompt_tokens"))
    completion_tokens = _token_count(_first_present(usage, "completionTokens", "completion_tokens"))
    total_tokens = _token_count(_first_present(usage, "totalTokens", "total_tokens"))
    cached_tokens = min(_cached_tokens(usage), prompt_tokens)

    if prompt_tokens == 0 and completion_tokens == 0:
        return {
            "inputTokens": 0,
            "outputTokens": 0,
            "totalTokens": total_tokens,
            "cachedInputTokens": cached_tokens,
            "costUnits": 1,
        }

    pricing = MODEL_PRICING.get(model, MODEL_PRICING["gpt-5-mini"])
    billable_input_tokens = max(0, prompt_tokens - cached_tokens)
    input_cost = _million_token_cost(billable_input_tokens, pricing.input_usd_per_million)
    cached_input_cost = _million_token_cost(cached_tokens, pricing.effective_cached_input_usd_per_million)
    output_cost = _million_token_cost(completion_tokens, pricing.output_usd_per_million)
    cost_units = int(((input_cost + cached_input_cost + output_cost) / LISDO_QUOTA_UNIT_USD).to_integral_value(rounding=ROUND_CEILING))

    return {
        "inputTokens": prompt_tokens,
        "outputTokens": completion_tokens,
        "totalTokens": total_tokens or prompt_tokens + completion_tokens,
        "cachedInputTokens": cached_tokens,
        "costUnits": max(1, cost_units),
    }


def _million_token_cost(tokens: int, usd_per_million: Decimal) -> Decimal:
    return (Decimal(tokens) * usd_per_million) / Decimal(1_000_000)


def _first_present(usage: dict[str, Any] | None, *keys: str) -> Any:
    if not isinstance(usage, dict):
        return None
    for key in keys:
        if key in usage:
            return usage[key]
    return None


def _cached_tokens(usage: dict[str, Any] | None) -> int:
    if not isinstance(usage, dict):
        return 0
    cached = _first_present(usage, "cachedInputTokens", "cached_input_tokens")
    if cached is not None:
        return _token_count(cached)
    prompt_details = usage.get("prompt_tokens_details")
    if isinstance(prompt_details, dict):
        return _token_count(prompt_details.get("cached_tokens"))
    return 0


def _token_count(value: Any) -> int:
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return max(0, value)
    return 0
