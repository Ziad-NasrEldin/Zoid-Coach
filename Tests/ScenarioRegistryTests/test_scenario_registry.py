import importlib.util
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "scenario_registry.py"
TRACKER = ROOT / "docs" / "zoid-coach-product-scenario-tracker.md"
REGISTRY = ROOT / "docs" / "scenario-registry.json"


def load_module():
    spec = importlib.util.spec_from_file_location("scenario_registry", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ScenarioRegistryTests(unittest.TestCase):
    def test_sync_preserves_known_scenario_identity_and_section_65_dispositions(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)

        self.assertEqual(payload["scenario_count"], 666)
        self.assertEqual(payload["scenarios"][0]["id"], "ZC-001-001")
        self.assertEqual(
            payload["scenarios"][0]["wording"],
            "Open Zoid Coach for the first time and immediately understand that it helps connect planned work with actual computer activity.",
        )
        self.assertEqual(payload["scenarios"][0]["disposition"], "required_now")

        section_65 = [item for item in payload["scenarios"] if item["section_number"] == 65]
        self.assertEqual(len(section_65), 8)
        self.assertEqual(section_65[4]["disposition"], "superseded_candidate")
        self.assertEqual(section_65[7]["disposition"], "deferred_guardrail")
        self.assertEqual(
            [item["disposition"] for item in section_65],
            [
                "negative_invariant",
                "negative_invariant",
                "negative_invariant",
                "negative_invariant",
                "superseded_candidate",
                "negative_invariant",
                "negative_invariant",
                "deferred_guardrail",
            ],
        )

    def test_validate_accepts_the_committed_registry(self):
        result = subprocess.run(
            ["python3", str(SCRIPT), "validate"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("666 scenarios", result.stdout)

    def test_validate_reports_tracker_drift(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["wording"] = "Drifted wording."

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("tracker drift" in error.lower() for error in errors), errors)

    def test_validate_rejects_duplicate_ids(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][1]["id"] = payload["scenarios"][0]["id"]

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("duplicate scenario id" in error.lower() for error in errors), errors)

    def test_validate_rejects_invalid_counts(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenario_count"] = 665
        payload["scenarios"].pop()

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("scenario_count must be 666" in error for error in errors), errors)
        self.assertTrue(any("must contain 666 scenarios" in error for error in errors), errors)

    def test_validate_rejects_invalid_status_disposition_and_evidence(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["delivery_status"] = "done-ish"
        payload["scenarios"][1]["disposition"] = "eventually"
        payload["scenarios"][2]["evidence_paths"] = ["/absolute/private/path"]

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("delivery_status" in error for error in errors), errors)
        self.assertTrue(any("disposition" in error for error in errors), errors)
        self.assertTrue(any("evidence_paths" in error for error in errors), errors)

    def test_sync_is_deterministic(self):
        module = load_module()

        first = module.build_registry(TRACKER, ROOT)
        second = module.build_registry(TRACKER, ROOT)

        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
