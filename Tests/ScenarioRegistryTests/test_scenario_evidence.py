import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "scenario_evidence.py"
REGISTRY = ROOT / "docs" / "scenario-registry.json"
SPEC = importlib.util.spec_from_file_location("scenario_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class ScenarioEvidenceTests(unittest.TestCase):
    commit = "a" * 40

    def create(self, root: Path, scenario_ids=None) -> Path:
        return MODULE.create_manifest(
            run_dir=root / "slice" / self.commit,
            scenario_ids=scenario_ids or ["ZC-001-001"],
            build_identity="qa-build-a",
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
                    build_identity="qa-build-a",
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


if __name__ == "__main__":
    unittest.main()
