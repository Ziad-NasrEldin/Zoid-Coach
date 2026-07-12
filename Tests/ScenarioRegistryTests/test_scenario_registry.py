import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from unittest import mock
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
            "Open Zoid 666 for the first time and immediately understand that it helps connect planned work with actual computer activity.",
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

    def test_validate_rejects_invalid_top_level_contract(self):
        module = load_module()
        base = module.build_registry(TRACKER, ROOT)
        mutations = [
            ("schema_version", 999, "schema_version"),
            ("$schema", "https://evil.example/schema.json", "$schema"),
            ("tracker_path", "docs/other.md", "tracker_path"),
            ("tracker_sha256", "0" * 64, "tracker_sha256"),
        ]

        for field, value, expected_error in mutations:
            with self.subTest(field=field):
                payload = copy.deepcopy(base)
                payload[field] = value
                errors = module.validate_registry(payload, TRACKER, ROOT)
                self.assertTrue(
                    any(expected_error in error for error in errors),
                    errors,
                )

        payload = copy.deepcopy(base)
        payload["unexpected"] = True
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("unexpected top-level" in error for error in errors), errors)

    def test_validate_rejects_unexpected_scenario_properties(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["unreviewed_claim"] = "complete"

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("unexpected scenario properties" in error for error in errors), errors)

    def test_sync_drops_evidence_when_tracker_derived_status_changes(self):
        module = load_module()
        existing = module.build_registry(TRACKER, ROOT)
        scenario_index = next(
            index
            for index, scenario in enumerate(existing["scenarios"])
            if scenario["audit_status"] != "Fully implemented"
        )
        existing["scenarios"][scenario_index]["audit_status"] = "Fully implemented"
        existing["scenarios"][scenario_index]["checkbox_state"] = "checked"
        existing["scenarios"][scenario_index]["evidence_paths"] = [
            ".audit/runs/baseline/a068d27/REPORT.md"
        ]

        rebuilt = module.build_registry(TRACKER, ROOT, existing=existing)

        self.assertEqual(rebuilt["scenarios"][scenario_index]["evidence_paths"], [])
        self.assertIsNone(
            rebuilt["scenarios"][scenario_index]["last_verified_commit"]
        )

    def test_completion_claim_requires_audit_evidence(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        checked = next(
            scenario for scenario in payload["scenarios"]
            if scenario["checkbox_state"] == "checked"
        )
        checked["evidence_paths"] = []

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("completion claim requires evidence_paths" in error for error in errors), errors)

    def test_validate_rejects_nonexistent_or_incoherent_verification_identity(self):
        module = load_module()
        base = module.build_registry(TRACKER, ROOT)
        existing_commit = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        payload = copy.deepcopy(base)
        payload["scenarios"][0]["last_verified_commit"] = "d" * 40
        payload["scenarios"][0]["last_verified_build"] = (
            f"zoid-coach-{'d' * 40}-clean"
        )
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("does not exist" in error for error in errors), errors)

        payload = copy.deepcopy(base)
        payload["scenarios"][0]["last_verified_commit"] = existing_commit
        payload["scenarios"][0]["last_verified_build"] = "anything"
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("last_verified_build" in error for error in errors), errors)

        payload = copy.deepcopy(base)
        payload["scenarios"][0]["last_verified_commit"] = existing_commit
        payload["scenarios"][0]["last_verified_build"] = (
            f"zoid-coach-{'a' * 40}-clean"
        )
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("does not match" in error for error in errors), errors)

    def test_validate_rejects_partial_verification_identity(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["last_verified_commit"] = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("must both be null or populated" in error for error in errors), errors)

    def test_commit_lookup_ignores_foreign_git_environment(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            repositories = [root / "primary", root / "foreign"]
            commits = []
            for index, repository in enumerate(repositories):
                repository.mkdir()
                subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
                subprocess.run(
                    ["git", "config", "user.email", "registry@example.invalid"],
                    cwd=repository,
                    check=True,
                )
                subprocess.run(
                    ["git", "config", "user.name", "Registry Test"],
                    cwd=repository,
                    check=True,
                )
                (repository / "seed.txt").write_text(f"seed-{index}\n", encoding="utf-8")
                subprocess.run(["git", "add", "seed.txt"], cwd=repository, check=True)
                subprocess.run(
                    ["git", "commit", "-q", "-m", f"Seed {index}"],
                    cwd=repository,
                    check=True,
                )
                commits.append(
                    subprocess.run(
                        ["git", "rev-parse", "HEAD"],
                        cwd=repository,
                        check=True,
                        capture_output=True,
                        text=True,
                    ).stdout.strip()
                )

            contaminated = {
                "GIT_DIR": str(repositories[1] / ".git"),
                "GIT_WORK_TREE": str(repositories[1]),
            }
            with mock.patch.dict(os.environ, contaminated, clear=False):
                self.assertFalse(
                    module.commit_exists(commits[1], repositories[0])
                )

    def test_clean_build_identity_requires_matching_machine_linked_evidence(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository_root = Path(temporary_directory)
            subprocess.run(["git", "init", "-q"], cwd=repository_root, check=True)
            subprocess.run(
                ["git", "config", "user.email", "scenario-registry@example.invalid"],
                cwd=repository_root,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Scenario Registry Test"],
                cwd=repository_root,
                check=True,
            )
            (repository_root / "seed.txt").write_text("seed\n", encoding="utf-8")
            subprocess.run(["git", "add", "seed.txt"], cwd=repository_root, check=True)
            subprocess.run(
                ["git", "commit", "-q", "-m", "Seed proof repository"],
                cwd=repository_root,
                check=True,
            )
            commit = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=repository_root,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            identity = f"zoid-coach-{commit}-clean"
            run_directory = repository_root / ".audit" / "runs" / "test" / commit
            artifact = run_directory / "proof.txt"
            artifact.parent.mkdir(parents=True)
            artifact.write_text("proof\n", encoding="utf-8")
            evidence = run_directory / "evidence.json"
            evidence.write_text(
                json.dumps(
                    {
                        "verified_commit": commit,
                        "build_identity": identity,
                        "status": "passed",
                        "scenario_ids": ["ZC-001-001"],
                        "required_proof_classes": ["unit_rule"],
                        "completed_at": "2026-07-12T00:00:00Z",
                        "assertions": ["Fixture behavior passed"],
                        "artifacts": [
                            {
                                "path": "proof.txt",
                                "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            evidence_path = evidence.relative_to(repository_root).as_posix()

            self.assertEqual(
                module.validate_verification_identity(
                    commit,
                    identity,
                    [evidence_path],
                    repository_root,
                    scenario_id="ZC-001-001",
                    required_proof_classes=["unit_rule"],
                ),
                [],
            )
            invalid_assertion_payload = json.loads(evidence.read_text(encoding="utf-8"))
            invalid_assertion_payload["assertions"] = [None]
            evidence.write_text(
                json.dumps(invalid_assertion_payload, indent=2) + "\n",
                encoding="utf-8",
            )
            invalid_assertion_errors = module.validate_verification_identity(
                commit,
                identity,
                [evidence_path],
                repository_root,
                scenario_id="ZC-001-001",
                required_proof_classes=["unit_rule"],
            )
            self.assertTrue(
                any("scenario-bound evidence manifest" in error for error in invalid_assertion_errors),
                invalid_assertion_errors,
            )
            invalid_assertion_payload["assertions"] = ["Fixture behavior passed"]
            evidence.write_text(
                json.dumps(invalid_assertion_payload, indent=2) + "\n",
                encoding="utf-8",
            )
            dirty_errors = module.validate_verification_identity(
                commit,
                f"zoid-coach-{commit}-dirty",
                [evidence_path],
                repository_root,
                scenario_id="ZC-001-001",
                required_proof_classes=["unit_rule"],
            )
            self.assertTrue(
                any("last_verified_build" in error for error in dirty_errors),
                dirty_errors,
            )
            line_qualified_errors = module.validate_verification_identity(
                commit,
                identity,
                [f"{evidence_path}:1"],
                repository_root,
                scenario_id="ZC-001-001",
                required_proof_classes=["unit_rule"],
            )
            self.assertTrue(
                any("scenario-bound evidence manifest" in error for error in line_qualified_errors),
                line_qualified_errors,
            )

    def test_evidence_paths_must_exist_inside_audit_runs(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["evidence_paths"] = [
            "Sources/ZoidCoachApp/ZoidCoachApp.swift"
        ]
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("evidence_paths" in error for error in errors), errors)
        existing_report = ".audit/runs/phase0-foundation/0091652/REPORT.md"
        self.assertFalse(module.validate_evidence_path(f"{existing_report}:0", ROOT))
        self.assertFalse(module.validate_evidence_path(f"{existing_report}:2-1", ROOT))

        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["evidence_paths"] = [
            ".audit/runs/missing/proof.txt"
        ]
        errors = module.validate_registry(payload, TRACKER, ROOT)
        self.assertTrue(any("evidence_paths" in error for error in errors), errors)

        with tempfile.TemporaryDirectory() as temporary_directory:
            repository_root = Path(temporary_directory)
            audit_root = repository_root / ".audit" / "runs"
            outside = repository_root / "outside"
            audit_root.mkdir(parents=True)
            outside.mkdir()
            (outside / "proof.txt").write_text("proof\n", encoding="utf-8")
            (audit_root / "escape").symlink_to(outside, target_is_directory=True)
            self.assertFalse(
                module.validate_evidence_path(
                    ".audit/runs/escape/proof.txt",
                    repository_root,
                )
            )

        with tempfile.TemporaryDirectory() as temporary_directory:
            repository_root = Path(temporary_directory) / "repository"
            outside = Path(temporary_directory) / "outside-runs"
            (repository_root / ".audit").mkdir(parents=True)
            (outside / "test").mkdir(parents=True)
            (outside / "test" / "proof.txt").write_text("proof\n", encoding="utf-8")
            (repository_root / ".audit" / "runs").symlink_to(
                outside,
                target_is_directory=True,
            )
            self.assertFalse(
                module.validate_evidence_path(
                    ".audit/runs/test/proof.txt",
                    repository_root,
                )
            )

    def test_validate_rejects_out_of_range_tracker_and_evidence_lines(self):
        module = load_module()
        payload = module.build_registry(TRACKER, ROOT)
        payload["scenarios"][0]["tracker_line"] = 999_999
        payload["scenarios"][0]["evidence_paths"] = [
            ".audit/runs/phase0-foundation/0091652/REPORT.md:999999"
        ]

        errors = module.validate_registry(payload, TRACKER, ROOT)

        self.assertTrue(any("tracker_line" in error for error in errors), errors)
        self.assertTrue(any("evidence_paths" in error for error in errors), errors)

    def test_write_sync_is_deterministic_with_existing_registry(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as temporary_directory:
            registry = Path(temporary_directory) / "registry.json"
            first = module.write_registry(TRACKER, registry, ROOT)
            first_bytes = registry.read_bytes()
            second = module.write_registry(TRACKER, registry, ROOT)

            self.assertEqual(first, second)
            self.assertEqual(first_bytes, registry.read_bytes())

    def test_sync_is_deterministic(self):
        module = load_module()

        first = module.build_registry(TRACKER, ROOT)
        second = module.build_registry(TRACKER, ROOT)

        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
