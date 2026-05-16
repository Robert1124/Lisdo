from __future__ import annotations

MONTHLY_PLANS = frozenset({"monthlyBasic", "monthlyPlus", "monthlyMax"})
KNOWN_PLANS = frozenset({"free", "starterTrial", *MONTHLY_PLANS})
DRAFT_MODEL_BY_PLAN = {
    "starterTrial": "gpt-5-mini",
    "monthlyBasic": "gpt-5-mini",
    "monthlyPlus": "gpt-5.4-mini",
    "monthlyMax": "gpt-5.4-mini",
}


def normalize_plan(plan_id: str) -> str:
    if plan_id in KNOWN_PLANS:
        return plan_id
    return "free"


def is_active_monthly_plan(plan_id: str) -> bool:
    return normalize_plan(plan_id) in MONTHLY_PLANS


def entitlements_for_plan(plan_id: str) -> dict[str, bool]:
    normalized = normalize_plan(plan_id)
    is_monthly = normalized in MONTHLY_PLANS

    return {
        "byokAndCLI": True,
        "lisdoManagedDrafts": normalized != "free",
        "iCloudSync": is_monthly,
        "realtimeVoice": normalized == "starterTrial" or normalized == "monthlyMax",
    }


def draft_model_for_plan(plan_id: str) -> str:
    return DRAFT_MODEL_BY_PLAN.get(normalize_plan(plan_id), "gpt-5-mini")
