import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "scenario_evidence.py"
REGISTRY = ROOT / "docs" / "scenario-registry.json"
SPEC = importlib.util.spec_from_file_location("scenario_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class ScenarioEvidenceTests(unittest.TestCase):
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

    def create(self, root: Path, scenario_ids=None) -> Path:
        return MODULE.create_manifest(
            run_dir=root / "slice" / self.commit,
            scenario_ids=scenario_ids or ["ZC-001-001"],
            build_identity=f"zoid-coach-{self.commit}-clean",
            fixture="first-run",
            qa_root=root / "qa-root",
            commit=self.commit,
            registry_path=REGISTRY,
        )

    def test_create_derives_required_proof_and_validates(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.create(Path(directory))
            payload = json.loads(manifest.read_text())

            self.assertEqual(payload["verified_commit"], self.commit)
            self.assertEqual(payload["scenario_ids"], ["ZC-001-001"])
            self.assertTrue(payload["required_proof_classes"])
            self.assertEqual(MODULE.validate_manifest(manifest, REGISTRY), [])

    def test_create_rejects_unknown_duplicate_and_non_commit_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(MODULE.EvidenceError):
                self.create(root, ["ZC-999-999"])
            with self.assertRaises(MODULE.EvidenceError):
                self.create(root, ["ZC-001-001", "ZC-001-001"])
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.create_manifest(
                    run_dir=root / "slice" / "wrong",
                    scenario_ids=["ZC-001-001"],
                    build_identity=f"zoid-coach-{self.commit}-clean",
                    fixture="first-run",
                    qa_root=root / "qa-root",
                    commit=self.commit,
                    registry_path=REGISTRY,
                )

    def test_create_refuses_to_overwrite_an_existing_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create(root)
            with self.assertRaises(MODULE.EvidenceError):
                self.create(root)

    def test_create_rejects_forged_or_dirty_build_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(MODULE.EvidenceError):
                MODULE.create_manifest(
                    run_dir=root / "slice" / self.commit,
                    scenario_ids=["ZC-001-001"],
                    build_identity=f"zoid-coach-{self.commit}-dirty",
                    fixture="first-run",
                    qa_root=root / "qa-root",
                    commit=self.commit,
                    registry_path=REGISTRY,
                )

    def test_validation_requires_checksummed_artifacts_for_a_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.create(Path(directory))
            payload = json.loads(manifest.read_text())
            payload["status"] = "passed"
            payload["completed_at"] = "2026-07-12T00:00:00+00:00"
            payload["assertions"] = [{"name": "visible state", "result": "passed"}]
            artifact = manifest.parent / "snapshot.txt"
            artifact.write_text("visible UI state\n")
            payload["artifacts"] = [
                {
                    "path": "snapshot.txt",
                    "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                    "kind": "accessibility_snapshot",
                }
            ]
            manifest.write_text(json.dumps(payload, indent=2) + "\n")

            self.assertEqual(MODULE.validate_manifest(manifest, REGISTRY), [])
            artifact.write_text("tampered\n")
            self.assertIn("artifact 0 sha256 mismatch: snapshot.txt", MODULE.validate_manifest(manifest, REGISTRY))

    def test_validation_rejects_absolute_or_escaping_artifact_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.create(Path(directory))
            payload = json.loads(manifest.read_text())
            payload["artifacts"] = [{"path": "../outside.txt", "sha256": "0" * 64}]
            manifest.write_text(json.dumps(payload, indent=2) + "\n")
            errors = MODULE.validate_manifest(manifest, REGISTRY)

            self.assertTrue(any("relative path" in error for error in errors), errors)

    def test_validation_rejects_parent_symlink_artifact_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.create(root)
            outside = root / "outside"
            outside.mkdir()
            artifact = outside / "proof.txt"
            artifact.write_text("outside\n")
            (manifest.parent / "linked").symlink_to(outside, target_is_directory=True)
            payload = json.loads(manifest.read_text())
            payload["artifacts"] = [
                {
                    "path": "linked/proof.txt",
                    "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                }
            ]
            manifest.write_text(json.dumps(payload, indent=2) + "\n")

            errors = MODULE.validate_manifest(manifest, REGISTRY)
            self.assertTrue(any("escapes the evidence run" in error for error in errors), errors)

    def test_passed_manifest_rejects_null_or_failed_assertions(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.create(Path(directory))
            payload = json.loads(manifest.read_text())
            payload["assertions"] = [None, {"name": "visible state", "result": "failed"}]
            manifest.write_text(json.dumps(payload, indent=2) + "\n")

            errors = MODULE.validate_manifest(manifest, REGISTRY)
            self.assertTrue(any("assertions must contain" in error for error in errors), errors)

    def test_git_identity_ignores_ambient_repository_redirection(self):
        original = {key: os.environ.get(key) for key in ("GIT_DIR", "GIT_WORK_TREE")}
        try:
            os.environ["GIT_DIR"] = "/tmp/foreign.git"
            os.environ["GIT_WORK_TREE"] = "/tmp/foreign-worktree"
            self.assertEqual(MODULE.repository_commit(), self.commit)
            self.assertTrue(MODULE.commit_exists(self.commit))
        finally:
            for key, value in original.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    def test_evidence_refuses_structurally_valid_registry_with_tracker_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            drifted_registry = root / "scenario-registry.json"
            payload = json.loads(REGISTRY.read_text())
            payload["scenarios"][0]["required_proof_classes"] = ["unit_rule"]
            drifted_registry.write_text(json.dumps(payload, indent=2) + "\n")

            with self.assertRaisesRegex(MODULE.EvidenceError, "authoritative semantic validation"):
                MODULE.create_manifest(
                    run_dir=root / "slice" / self.commit,
                    scenario_ids=["ZC-001-001"],
                    build_identity=f"zoid-coach-{self.commit}-clean",
                    fixture="first-run",
                    qa_root=root / "qa-root",
                    commit=self.commit,
                    registry_path=drifted_registry,
                )


if __name__ == "__main__":
    unittest.main()
