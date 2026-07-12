import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "Scripts" / "notification-delivery-acceptance.py"
MAPPING = REPO / ".audit" / "runs" / "notification-delivery-health" / "acceptance-mapping.json"


class NotificationDeliveryAcceptanceTests(unittest.TestCase):
    def run_script(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(SCRIPT), *arguments],
            cwd=REPO,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_prepare_builds_three_isolated_private_fixture_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "notification-acceptance"
            result = self.run_script("prepare", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)

            manifest = json.loads((root / "acceptance-manifest.json").read_text())
            self.assertEqual(
                set(manifest["scenarios"]),
                {"delivery-replacement-restart", "scheduling-failure", "denied-repair"},
            )
            failure = json.loads(
                (root / "scheduling-failure" / "QA Control" / "os-fixture-request.json").read_text()
            )
            self.assertEqual(failure["seed"]["permissions"], ["notifications", "granted"])
            self.assertEqual(
                failure["seed"]["notificationSchedulingFailure"],
                "qa_injected_schedule_failure",
            )
            instructions = (root / "ACCEPTANCE.md").read_text()
            self.assertIn("SEND TEST PROMPT", instructions)
            self.assertIn("advance-repair", instructions)
            self.assertNotIn("Zoid Coach", instructions)

    def test_acceptance_mapping_matches_authoritative_registry_wording(self) -> None:
        mapping = json.loads(MAPPING.read_text())
        registry = json.loads((REPO / "docs" / "scenario-registry.json").read_text())
        scenarios = {scenario["id"]: scenario for scenario in registry["scenarios"]}
        expected = {
            "ZC-044-011",
            "ZC-044-013",
            "ZC-048-004",
            "ZC-050-002",
            "ZC-050-007",
            "ZC-054-008",
            "ZC-054-009",
        }
        self.assertEqual({item["scenarioID"] for item in mapping["mappings"]}, expected)
        for item in mapping["mappings"]:
            self.assertEqual(item["wording"], scenarios[item["scenarioID"]]["wording"])
            self.assertIn(item["maximumStatusAfterHarness"], {"Fully implemented", "Touches remaining"})
            self.assertTrue(item["requiredVisibleEvidence"])
            self.assertTrue(item["requiredMachineEvidence"])

    def test_prepare_refuses_to_overwrite_existing_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "notification-acceptance"
            root.mkdir()
            (root / "owned.txt").write_text("keep")
            result = self.run_script("prepare", str(root))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((root / "owned.txt").read_text(), "keep")

    def test_advance_repair_requires_processed_denial_then_queues_grant(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "notification-acceptance"
            self.assertEqual(self.run_script("prepare", str(root)).returncode, 0)
            run_root = root / "denied-repair"
            pending = run_root / "QA Control" / "os-fixture-request.json"
            pending.unlink()
            state = run_root / "OS Fixtures" / "state.json"
            state.parent.mkdir(parents=True)
            state.write_text("{}\n")

            result = self.run_script("advance-repair", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            request = json.loads(pending.read_text())
            self.assertEqual(request["requestID"], "notification-acceptance-repair-granted")
            self.assertEqual(request["seed"]["permissions"], ["notifications", "granted"])

    def test_verify_exports_only_privacy_safe_delivery_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "notification-acceptance"
            self.assertEqual(self.run_script("prepare", str(root)).returncode, 0)
            self.create_ledger(
                root / "delivery-replacement-restart",
                [
                    ("delivered_by_fixture", 1, 0, None),
                    ("delivered_by_fixture", 2, 1, None),
                ],
            )
            self.create_ledger(
                root / "scheduling-failure",
                [("scheduling_failed", 1, 0, "safe failure")],
            )
            self.create_ledger(
                root / "denied-repair",
                [
                    ("authorization_unavailable", 1, 0, None),
                    ("delivered_by_fixture", 2, 0, None),
                ],
            )
            output = root / "evidence.json"

            result = self.run_script("verify", str(root), "--output", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)
            evidence = json.loads(output.read_text())
            serialized = json.dumps(evidence)
            self.assertNotIn("private-prompt", serialized)
            self.assertNotIn("private-request", serialized)
            self.assertNotIn("safe failure", serialized)
            self.assertIn("replacedPriorRequest", serialized)

    def create_ledger(self, run_root: Path, rows: list[tuple]) -> None:
        database = run_root / "Application Support" / "zoid-coach.sqlite"
        database.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(database)
        connection.executescript(
            """
            CREATE TABLE notification_delivery_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_identifier TEXT NOT NULL,
                prompt_id TEXT NOT NULL,
                category TEXT NOT NULL,
                outcome TEXT NOT NULL,
                scheduled_for TEXT,
                recorded_at TEXT NOT NULL,
                attempt INTEGER NOT NULL,
                replaced_prior_request INTEGER NOT NULL,
                redacted_error TEXT
            );
            """
        )
        for index, (outcome, attempt, replacement, error) in enumerate(rows):
            connection.execute(
                """
                INSERT INTO notification_delivery_events (
                    request_identifier, prompt_id, category, outcome, recorded_at,
                    attempt, replaced_prior_request, redacted_error
                ) VALUES (?, ?, 'ONBOARDING_TEST', ?, ?, ?, ?, ?)
                """,
                (
                    f"private-request-{index}",
                    f"private-prompt-{index}",
                    outcome,
                    f"2026-07-13T00:00:0{index}Z",
                    attempt,
                    replacement,
                    error,
                ),
            )
        connection.commit()
        connection.close()


if __name__ == "__main__":
    unittest.main()
