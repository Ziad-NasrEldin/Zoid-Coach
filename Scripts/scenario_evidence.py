#!/usr/bin/env python3
"""Create and validate immutable evidence manifests for Zoid Coach scenarios."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY = ROOT / "docs" / "scenario-registry.json"
SCENARIO_ID = re.compile(r"^ZC-\d{3}-\d{3}$")
COMMIT_ID = re.compile(r"^[0-9a-f]{7,40}$")
RUN_STATUSES = {"in_progress", "passed", "failed", "blocked"}


class EvidenceError(ValueError):
    """Raised when an evidence run violates the verification contract."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repository_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def load_registry(path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    payload = json.loads(path.read_text())
    scenarios = payload.get("scenarios", [])
    return payload, {item["id"]: item for item in scenarios}


def safe_relative_path(value: str, label: str) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or path == Path("."):
        raise EvidenceError(f"{label} must be a non-empty relative path without '..': {value}")
    return path


def create_manifest(
    *,
    run_dir: Path,
    scenario_ids: list[str],
    build_identity: str,
    fixture: str,
    qa_root: Path,
    commit: str,
    registry_path: Path = DEFAULT_REGISTRY,
) -> Path:
    if not scenario_ids:
        raise EvidenceError("at least one scenario ID is required")
    if len(scenario_ids) != len(set(scenario_ids)):
        raise EvidenceError("scenario IDs must not contain duplicates")
    if not COMMIT_ID.fullmatch(commit):
        raise EvidenceError(f"invalid git commit: {commit}")
    if run_dir.name != commit:
        raise EvidenceError("evidence run directory name must equal the exact verified commit")
    if not qa_root.is_absolute():
        raise EvidenceError("QA root must be absolute")
    if not build_identity.strip() or not fixture.strip():
        raise EvidenceError("build identity and fixture are required")

    _, scenarios = load_registry(registry_path)
    unknown = [item for item in scenario_ids if not SCENARIO_ID.fullmatch(item) or item not in scenarios]
    if unknown:
        raise EvidenceError(f"unknown scenario IDs: {', '.join(unknown)}")

    proof_classes = sorted(
        {
            proof
            for scenario_id in scenario_ids
            for proof in scenarios[scenario_id]["required_proof_classes"]
        }
    )
    manifest_path = run_dir / "evidence.json"
    if run_dir.exists():
        raise EvidenceError(f"refusing to overwrite immutable evidence run: {run_dir}")
    run_dir.mkdir(parents=True)
    payload = {
        "schema_version": 1,
        "run_id": f"{run_dir.parent.name}/{commit}",
        "verified_commit": commit,
        "build_identity": build_identity.strip(),
        "fixture": fixture.strip(),
        "qa_root": str(qa_root.resolve()),
        "registry_path": str(registry_path.resolve().relative_to(ROOT)),
        "registry_sha256": sha256(registry_path),
        "scenario_ids": scenario_ids,
        "required_proof_classes": proof_classes,
        "status": "in_progress",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": None,
        "artifacts": [],
        "assertions": [],
        "commands": [],
    }
    manifest_path.write_text(json.dumps(payload, indent=2) + "\n")
    return manifest_path


def validate_manifest(
    manifest_path: Path,
    registry_path: Path = DEFAULT_REGISTRY,
) -> list[str]:
    errors: list[str] = []
    try:
        payload = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read evidence manifest: {error}"]

    _, scenarios = load_registry(registry_path)
    commit = payload.get("verified_commit")
    if not isinstance(commit, str) or not COMMIT_ID.fullmatch(commit):
        errors.append("verified_commit must be a 7 to 40 character lowercase git SHA")
    elif manifest_path.parent.name != commit:
        errors.append("manifest parent directory must equal verified_commit")

    scenario_ids = payload.get("scenario_ids")
    if not isinstance(scenario_ids, list) or not scenario_ids:
        errors.append("scenario_ids must be a non-empty array")
        scenario_ids = []
    elif len(scenario_ids) != len(set(scenario_ids)):
        errors.append("scenario_ids must not contain duplicates")
    unknown = [item for item in scenario_ids if not isinstance(item, str) or item not in scenarios]
    if unknown:
        errors.append(f"unknown scenario IDs: {', '.join(map(str, unknown))}")

    expected_proof = sorted(
        {
            proof
            for scenario_id in scenario_ids
            if scenario_id in scenarios
            for proof in scenarios[scenario_id]["required_proof_classes"]
        }
    )
    if payload.get("required_proof_classes") != expected_proof:
        errors.append("required_proof_classes do not match the registry")
    if payload.get("registry_sha256") != sha256(registry_path):
        errors.append("registry_sha256 does not match the current registry")
    if payload.get("status") not in RUN_STATUSES:
        errors.append(f"status must be one of {', '.join(sorted(RUN_STATUSES))}")

    qa_root = payload.get("qa_root")
    if not isinstance(qa_root, str) or not Path(qa_root).is_absolute():
        errors.append("qa_root must be an absolute path")

    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list):
        errors.append("artifacts must be an array")
        artifacts = []
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            errors.append(f"artifact {index} must be an object")
            continue
        try:
            relative = safe_relative_path(str(artifact.get("path", "")), f"artifact {index} path")
        except EvidenceError as error:
            errors.append(str(error))
            continue
        artifact_path = manifest_path.parent / relative
        if not artifact_path.is_file():
            errors.append(f"artifact {index} does not exist: {relative}")
            continue
        if artifact_path.is_symlink():
            errors.append(f"artifact {index} must not be a symlink: {relative}")
        expected_digest = artifact.get("sha256")
        if expected_digest != sha256(artifact_path):
            errors.append(f"artifact {index} sha256 mismatch: {relative}")

    for field in ("assertions", "commands"):
        if not isinstance(payload.get(field), list):
            errors.append(f"{field} must be an array")
    if payload.get("status") == "passed":
        if not payload.get("completed_at"):
            errors.append("passed evidence must record completed_at")
        if not payload.get("assertions"):
            errors.append("passed evidence must contain at least one assertion")
        if not payload.get("artifacts"):
            errors.append("passed evidence must contain at least one checksummed artifact")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="create a new immutable evidence run")
    create.add_argument("--run-dir", type=Path, required=True)
    create.add_argument("--scenario", action="append", dest="scenarios", required=True)
    create.add_argument("--build-identity", required=True)
    create.add_argument("--fixture", required=True)
    create.add_argument("--qa-root", type=Path, required=True)
    create.add_argument("--commit", default=None)

    validate = subparsers.add_parser("validate", help="validate an evidence manifest")
    validate.add_argument("manifest", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "create":
            manifest = create_manifest(
                run_dir=args.run_dir,
                scenario_ids=args.scenarios,
                build_identity=args.build_identity,
                fixture=args.fixture,
                qa_root=args.qa_root,
                commit=args.commit or repository_commit(),
                registry_path=args.registry,
            )
            print(manifest)
            return 0
        errors = validate_manifest(args.manifest, args.registry)
    except (EvidenceError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Validated evidence manifest: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
