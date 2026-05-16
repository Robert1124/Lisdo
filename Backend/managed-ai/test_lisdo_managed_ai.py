import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("lisdo_managed_ai.py")
spec = importlib.util.spec_from_file_location("lisdo_managed_ai", MODULE_PATH)
lisdo_managed_ai = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lisdo_managed_ai)


def request(method, path, body=None, headers=None):
    return lisdo_managed_ai.lambda_handler(
        {
            "httpMethod": method,
            "path": path,
            "headers": headers or {},
            "body": json.dumps(body) if body is not None else None,
        },
        None,
    )


def response_json(response):
    return json.loads(response["body"])


class ManagedAITests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.ledger_path = os.path.join(self.tempdir.name, "ledger.json")
        self.previous_ledger_path = os.environ.get("LISDO_LEDGER_PATH")
        self.previous_openai_key = os.environ.get("OPENAI_API_KEY")
        os.environ["LISDO_LEDGER_PATH"] = self.ledger_path
        os.environ.pop("OPENAI_API_KEY", None)

    def tearDown(self):
        if self.previous_ledger_path is None:
            os.environ.pop("LISDO_LEDGER_PATH", None)
        else:
            os.environ["LISDO_LEDGER_PATH"] = self.previous_ledger_path

        if self.previous_openai_key is None:
            os.environ.pop("OPENAI_API_KEY", None)
        else:
            os.environ["OPENAI_API_KEY"] = self.previous_openai_key

        self.tempdir.cleanup()

    def test_entitlement_endpoint_returns_default_free_summary(self):
        response = request("GET", "/v1/me/entitlements")

        self.assertEqual(response["statusCode"], 200)
        body = response_json(response)
        self.assertEqual(body["userId"], "dev-user")
        self.assertEqual(body["planId"], "free")
        self.assertFalse(body["entitlements"]["managedDrafts"])
        self.assertFalse(body["entitlements"]["realtimeProcessing"])
        self.assertFalse(body["entitlements"]["iCloudSync"])
        self.assertEqual(body["quota"]["monthlyRemaining"], 0)
        self.assertEqual(body["quota"]["topUpRemaining"], 0)

    def test_monthly_basic_has_icloud_but_no_realtime_and_monthly_max_has_realtime(self):
        monthly_basic = request(
            "POST",
            "/v1/dev/entitlements/set-plan",
            body={"planId": "monthlyBasic"},
        )
        self.assertEqual(monthly_basic["statusCode"], 200)
        basic_body = response_json(monthly_basic)
        self.assertTrue(basic_body["entitlements"]["managedDrafts"])
        self.assertTrue(basic_body["entitlements"]["iCloudSync"])
        self.assertFalse(basic_body["entitlements"]["realtimeProcessing"])

        monthly_max = request(
            "POST",
            "/v1/dev/entitlements/set-plan",
            body={"planId": "monthlyMax"},
        )
        self.assertEqual(monthly_max["statusCode"], 200)
        max_body = response_json(monthly_max)
        self.assertTrue(max_body["entitlements"]["managedDrafts"])
        self.assertTrue(max_body["entitlements"]["iCloudSync"])
        self.assertTrue(max_body["entitlements"]["realtimeProcessing"])

    def test_free_plan_is_blocked_from_managed_draft_generation(self):
        response = request(
            "POST",
            "/v1/drafts/generate",
            body={"chatRequest": {"messages": [{"role": "user", "content": "Buy milk"}]}},
            headers={"Authorization": "Bearer dev-token"},
        )

        self.assertEqual(response["statusCode"], 402)
        body = response_json(response)
        self.assertEqual(body["error"]["code"], "managed_drafts_unavailable")

    def test_monthly_quota_is_consumed_before_top_up_credits(self):
        set_plan = request(
            "POST",
            "/v1/dev/entitlements/set-plan",
            body={"planId": "monthlyBasic", "monthlyQuotaRemaining": 1, "topUpCredits": 2},
        )
        self.assertEqual(set_plan["statusCode"], 200)

        first = request(
            "POST",
            "/v1/drafts/generate",
            body={"chatRequest": {"messages": [{"role": "user", "content": "First task"}]}},
            headers={"Authorization": "Bearer dev-token"},
        )
        second = request(
            "POST",
            "/v1/drafts/generate",
            body={"chatRequest": {"messages": [{"role": "user", "content": "Second task"}]}},
            headers={"Authorization": "Bearer dev-token"},
        )

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["statusCode"], 200)
        summary = response_json(request("GET", "/v1/me/entitlements"))
        self.assertEqual(summary["quota"]["monthlyRemaining"], 0)
        self.assertEqual(summary["quota"]["topUpRemaining"], 1)
        self.assertEqual(summary["quota"]["monthlyConsumed"], 1)
        self.assertEqual(summary["quota"]["topUpConsumed"], 1)

    def test_no_key_returns_deterministic_valid_draft_json(self):
        request(
            "POST",
            "/v1/dev/entitlements/set-plan",
            body={"planId": "starterTrial", "monthlyQuotaRemaining": 2},
        )
        payload = {
            "chatRequest": {
                "model": "gpt-4.1-mini",
                "messages": [
                    {"role": "system", "content": "Return strict Lisdo draft JSON."},
                    {
                        "role": "user",
                        "content": "Tomorrow before 3 PM revise questionnaire and send to Yan.",
                    },
                ],
            }
        }

        first = request(
            "POST",
            "/v1/drafts/generate",
            body=payload,
            headers={"Authorization": "Bearer dev-token"},
        )
        request(
            "POST",
            "/v1/dev/entitlements/set-plan",
            body={"planId": "starterTrial", "monthlyQuotaRemaining": 2},
        )
        second = request(
            "POST",
            "/v1/drafts/generate",
            body=payload,
            headers={"Authorization": "Bearer dev-token"},
        )

        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(second["statusCode"], 200)
        first_body = response_json(first)
        second_body = response_json(second)
        self.assertEqual(first_body["draftJSON"], second_body["draftJSON"])

        draft = json.loads(first_body["draftJSON"])
        self.assertEqual(draft["recommendedCategoryId"], "work")
        self.assertIn("questionnaire", draft["title"].lower())
        self.assertIsInstance(draft["blocks"], list)
        self.assertFalse(draft["needsClarification"])
        self.assertEqual(first_body["usage"]["source"], "deterministic-local")


if __name__ == "__main__":
    unittest.main()
