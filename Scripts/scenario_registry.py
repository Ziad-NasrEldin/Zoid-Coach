#!/usr/bin/env python3
"""Generate and validate the Zoid 666 end-user scenario registry."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TRACKER = ROOT / "docs" / "zoid-coach-product-scenario-tracker.md"
DEFAULT_REGISTRY = ROOT / "docs" / "scenario-registry.json"
EXPECTED_SCENARIO_COUNT = 666
EXPECTED_SCHEMA = "scenario-registry.schema.json"
EXPECTED_SCHEMA_VERSION = 1
EXPECTED_TRACKER_PATH = "docs/zoid-coach-product-scenario-tracker.md"
TOP_LEVEL_FIELDS = {
    "$schema",
    "schema_version",
    "tracker_path",
    "tracker_sha256",
    "scenario_count",
    "scenarios",
}
SCENARIO_FIELDS = {
    "id",
    "section_number",
    "section_title",
    "item_index",
    "wording",
    "checkbox_state",
    "audit_status",
    "delivery_status",
    "disposition",
    "required_proof_classes",
    "affected_capability",
    "evidence_paths",
    "last_verified_commit",
    "last_verified_build",
    "audit_note",
    "tracker_line",
}

AUDIT_TO_DELIVERY = {
    "Fully implemented": "fully_implemented",
    "Touches remaining": "touches_remaining",
    "Frontend only left": "frontend_only_left",
    "Partially implemented": "partially_implemented",
    "Barely started": "barely_started",
    "Not implemented": "not_implemented",
    "Blocked from verification": "blocked_from_verification",
}
DELIVERY_STATUSES = set(AUDIT_TO_DELIVERY.values())
DISPOSITIONS = {
    "required_now",
    "negative_invariant",
    "superseded_candidate",
    "deferred_guardrail",
}
PROOF_CLASSES = {
    "unit_rule",
    "integration",
    "ui_automation",
    "accessibility",
    "installed_app_e2e",
    "live_runtime",
    "multi_day",
    "negative_invariant",
}
SECTION_PATTERN = re.compile(r"^## (\d+)\. (.+)$")
SCENARIO_PATTERN = re.compile(
    r"^- \[([ xX])\] (.*?) \*\*Status: ([^.]+)\.\*\*(?: (.*))?$"
)
EVIDENCE_PATH_PATTERN = re.compile(
    r"^(?P<path>\.audit/runs/[A-Za-z0-9_. -]+"
    r"(?:/[A-Za-z0-9_. -]+)+)"
    r"(?::(?P<line>[1-9]\d*))?$"
)
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
BUILD_IDENTITY_PATTERN = re.compile(r"^zoid-coach-([0-9a-f]{40})-clean$")


def capability_for_section(section_number):
    if section_number <= 5:
        return "onboarding_and_source_setup"
    if section_number <= 15:
        return "daily_planning"
    if section_number <= 23:
        return "task_execution"
    if section_number <= 28:
        return "behavior_truth_and_correction"
    if section_number <= 39:
        return "gaming_and_coaching"
    if section_number <= 43:
        return "review_and_learning"
    if section_number <= 46:
        return "settings"
    if section_number == 47:
        return "privacy_and_data_control"
    if section_number <= 54:
        return "resilience_and_diagnostics"
    if section_number <= 57:
        return "product_quality"
    if section_number <= 64:
        return "end_to_end_acceptance"
    return "release_scope_guardrail"


def disposition_for(section_number, item_index):
    if section_number < 65:
        return "required_now"
    if item_index == 5:
        return "superseded_candidate"
    if item_index == 8:
        return "deferred_guardrail"
    return "negative_invariant"


def proof_classes_for(section_number, disposition, wording):
    proof_classes = {"ui_automation", "installed_app_e2e"}
    if section_number in set(range(2, 5)) | set(range(21, 29)) | set(range(47, 55)):
        proof_classes.add("integration")
    if section_number in set(range(9, 13)) | set(range(15, 21)) | set(range(24, 44)):
        proof_classes.add("unit_rule")
    if section_number == 55:
        proof_classes.add("accessibility")
    if section_number >= 57:
        proof_classes.add("live_runtime")
    if section_number in {43, 64} or "seven consecutive days" in wording.lower():
        proof_classes.add("multi_day")
    if disposition == "negative_invariant":
        proof_classes.add("negative_invariant")
    return sorted(proof_classes)


def parse_tracker(tracker_path, repository_root):
    tracker_text = tracker_path.read_text(encoding="utf-8")
    scenarios = []
    section_number = None
    section_title = None
    section_item_index = 0

    for line_number, raw_line in enumerate(tracker_text.splitlines(), start=1):
        section_match = SECTION_PATTERN.match(raw_line)
        if section_match:
            section_number = int(section_match.group(1))
            section_title = section_match.group(2)
            section_item_index = 0
            continue

        scenario_match = SCENARIO_PATTERN.match(raw_line)
        if not scenario_match:
            continue
        if section_number is None:
            raise ValueError(f"Scenario on line {line_number} appears before a numbered section")

        section_item_index += 1
        checkbox_mark, wording, audit_status, audit_note = scenario_match.groups()
        if audit_status not in AUDIT_TO_DELIVERY:
            raise ValueError(f"Unknown audit status on line {line_number}: {audit_status}")
        disposition = disposition_for(section_number, section_item_index)
        is_checked = checkbox_mark.lower() == "x"
        scenarios.append(
            {
                "id": f"ZC-{section_number:03d}-{section_item_index:03d}",
                "section_number": section_number,
                "section_title": section_title,
                "item_index": section_item_index,
                "wording": wording,
                "checkbox_state": "checked" if is_checked else "unchecked",
                "audit_status": audit_status,
                "delivery_status": AUDIT_TO_DELIVERY[audit_status],
                "disposition": disposition,
                "required_proof_classes": proof_classes_for(
                    section_number, disposition, wording
                ),
                "affected_capability": capability_for_section(section_number),
                "evidence_paths": [],
                "last_verified_commit": None,
                "last_verified_build": None,
                "audit_note": audit_note or "",
                "tracker_line": line_number,
            }
        )
    return tracker_text, scenarios


def build_registry(tracker_path=DEFAULT_TRACKER, repository_root=ROOT, existing=None):
    tracker_path = Path(tracker_path)
    repository_root = Path(repository_root)
    tracker_text, scenarios = parse_tracker(tracker_path, repository_root)
    previous_by_id = {
        item["id"]: item for item in (existing or {}).get("scenarios", [])
    }
    for scenario in scenarios:
        previous = previous_by_id.get(scenario["id"])
        tracker_fields = SCENARIO_FIELDS - {
            "evidence_paths",
            "last_verified_commit",
            "last_verified_build",
        }
        if not previous or any(
            previous.get(field) != scenario.get(field) for field in tracker_fields
        ):
            continue
        preserved_evidence = {
            value
            for value in previous.get("evidence_paths", [])
            if validate_evidence_path(value, repository_root)
        }
        scenario["evidence_paths"] = sorted(
            set(scenario["evidence_paths"]) | preserved_evidence
        )
        verification_errors = validate_verification_identity(
            previous.get("last_verified_commit"),
            previous.get("last_verified_build"),
            scenario["evidence_paths"],
            repository_root,
            scenario_id=scenario["id"],
            required_proof_classes=scenario["required_proof_classes"],
        )
        if not verification_errors and previous.get("last_verified_commit"):
            scenario["last_verified_commit"] = previous["last_verified_commit"]
            scenario["last_verified_build"] = previous["last_verified_build"]

    return {
        "$schema": EXPECTED_SCHEMA,
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "tracker_path": tracker_path.relative_to(repository_root).as_posix(),
        "tracker_sha256": hashlib.sha256(tracker_text.encode("utf-8")).hexdigest(),
        "scenario_count": len(scenarios),
        "scenarios": scenarios,
    }


def validate_evidence_path(value, repository_root):
    if not isinstance(value, str):
        return False
    match = EVIDENCE_PATH_PATTERN.fullmatch(value)
    if not match:
        return False
    resolved_repository_root = repository_root.resolve()
    audit_root = (repository_root / ".audit" / "runs").resolve()
    try:
        audit_root.relative_to(resolved_repository_root)
    except ValueError:
        return False
    candidate = (repository_root / match.group("path")).resolve()
    try:
        candidate.relative_to(audit_root)
    except ValueError:
        return False
    if not candidate.is_file():
        return False
    if match.group("line") is None:
        return True
    line = int(match.group("line"))
    try:
        with candidate.open(encoding="utf-8") as evidence_file:
            line_count = sum(1 for _ in evidence_file)
    except UnicodeDecodeError:
        return False
    return line <= line_count


def commit_exists(commit, repository_root):
    if not isinstance(commit, str) or not COMMIT_PATTERN.fullmatch(commit):
        return False
    git_environment = os.environ.copy()
    for variable in (
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR",
        "GIT_DIR",
        "GIT_INDEX_FILE",
        "GIT_NAMESPACE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_WORK_TREE",
    ):
        git_environment.pop(variable, None)
    result = subprocess.run(
        ["git", "-C", str(repository_root), "cat-file", "-e", f"{commit}^{{commit}}"],
        capture_output=True,
        env=git_environment,
        text=True,
    )
    return result.returncode == 0


def valid_manifest_for_scenario(
    manifest_path,
    commit,
    build,
    scenario_id,
    required_proof_classes,
):
    if manifest_path.name != "evidence.json" or manifest_path.parent.name != commit:
        return False
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    scenario_ids = manifest.get("scenario_ids")
    manifest_proof_classes = manifest.get("required_proof_classes")
    assertions = manifest.get("assertions")
    artifacts = manifest.get("artifacts")
    if (
        manifest.get("verified_commit") != commit
        or manifest.get("build_identity") != build
        or manifest.get("status") != "passed"
        or not isinstance(scenario_ids, list)
        or scenario_id not in scenario_ids
        or not isinstance(manifest_proof_classes, list)
        or any(not isinstance(value, str) for value in manifest_proof_classes)
        or not set(required_proof_classes).issubset(
            set(manifest_proof_classes)
        )
        or not manifest.get("completed_at")
        or not isinstance(assertions, list)
        or not assertions
        or any(not valid_manifest_assertion(value) for value in assertions)
        or not isinstance(artifacts, list)
        or not artifacts
    ):
        return False
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            return False
        relative = Path(str(artifact.get("path", "")))
        if relative.is_absolute() or ".." in relative.parts or relative == Path("."):
            return False
        unresolved_artifact_path = manifest_path.parent / relative
        if unresolved_artifact_path.is_symlink():
            return False
        artifact_path = unresolved_artifact_path.resolve()
        try:
            artifact_path.relative_to(manifest_path.parent.resolve())
        except ValueError:
            return False
        if not artifact_path.is_file():
            return False
        digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
        if artifact.get("sha256") != digest:
            return False
    return True


def valid_manifest_assertion(value):
    if isinstance(value, str):
        return bool(value.strip())
    return (
        isinstance(value, dict)
        and isinstance(value.get("name"), str)
        and bool(value["name"].strip())
        and value.get("result") == "passed"
    )


def validate_verification_identity(
    commit,
    build,
    evidence_paths,
    repository_root,
    scenario_id=None,
    required_proof_classes=(),
):
    errors = []
    if commit is None and build is None:
        return errors
    if commit is None or build is None:
        return ["last_verified_commit and last_verified_build must both be null or populated"]
    if not isinstance(commit, str) or not COMMIT_PATTERN.fullmatch(commit):
        errors.append("malformed last_verified_commit; expected 40 lowercase hex characters")
    elif not commit_exists(commit, repository_root):
        errors.append(f"last_verified_commit does not exist: {commit}")
    build_match = BUILD_IDENTITY_PATTERN.fullmatch(build) if isinstance(build, str) else None
    if not build_match:
        errors.append(
            "malformed last_verified_build; expected zoid-coach-<40-hex-commit>-clean"
        )
    elif build_match.group(1) != commit:
        errors.append("last_verified_build commit does not match last_verified_commit")
    if not evidence_paths:
        errors.append("populated verification identity requires evidence_paths")
    elif isinstance(build, str):
        manifests = []
        for value in evidence_paths:
            match = EVIDENCE_PATH_PATTERN.fullmatch(value) if isinstance(value, str) else None
            if match and match.group("line") is None:
                manifests.append((repository_root / match.group("path")).resolve())
        if not scenario_id or not any(
            valid_manifest_for_scenario(
                manifest,
                commit,
                build,
                scenario_id,
                required_proof_classes,
            )
            for manifest in manifests
        ):
            errors.append(
                "last_verified_build requires a passed scenario-bound evidence manifest"
            )
    return errors


def validate_registry(payload, tracker_path=DEFAULT_TRACKER, repository_root=ROOT):
    tracker_path = Path(tracker_path)
    repository_root = Path(repository_root)
    errors = []
    if not isinstance(payload, dict):
        return ["registry must be an object"]
    unexpected_top_level = sorted(set(payload) - TOP_LEVEL_FIELDS)
    missing_top_level = sorted(TOP_LEVEL_FIELDS - set(payload))
    if unexpected_top_level:
        errors.append(
            f"unexpected top-level properties: {', '.join(unexpected_top_level)}"
        )
    if missing_top_level:
        errors.append(f"missing top-level properties: {', '.join(missing_top_level)}")
    if payload.get("$schema") != EXPECTED_SCHEMA:
        errors.append(f"$schema must be {EXPECTED_SCHEMA}")
    if payload.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        errors.append(f"schema_version must be {EXPECTED_SCHEMA_VERSION}")
    if payload.get("tracker_path") != EXPECTED_TRACKER_PATH:
        errors.append(f"tracker_path must be {EXPECTED_TRACKER_PATH}")

    scenarios = payload.get("scenarios")
    if not isinstance(scenarios, list):
        return ["scenarios must be an array"]
    if payload.get("scenario_count") != EXPECTED_SCENARIO_COUNT:
        errors.append(
            f"scenario_count must be {EXPECTED_SCENARIO_COUNT}, got {payload.get('scenario_count')}"
        )
    if len(scenarios) != EXPECTED_SCENARIO_COUNT:
        errors.append(f"registry must contain {EXPECTED_SCENARIO_COUNT} scenarios, got {len(scenarios)}")

    ids = [item.get("id") for item in scenarios if isinstance(item, dict)]
    seen_ids = set()
    duplicate_ids = set()
    for item_id in ids:
        if not isinstance(item_id, str):
            continue
        if item_id in seen_ids:
            duplicate_ids.add(item_id)
        seen_ids.add(item_id)
    if duplicate_ids:
        errors.append(f"duplicate scenario ID: {', '.join(sorted(duplicate_ids))}")

    tracker_line_count = len(tracker_path.read_text(encoding="utf-8").splitlines())
    for index, scenario in enumerate(scenarios, start=1):
        label = scenario.get("id", f"scenario {index}") if isinstance(scenario, dict) else f"scenario {index}"
        if not isinstance(scenario, dict):
            errors.append(f"{label} must be an object")
            continue
        unexpected_fields = sorted(set(scenario) - SCENARIO_FIELDS)
        missing_fields = sorted(SCENARIO_FIELDS - set(scenario))
        if unexpected_fields:
            errors.append(
                f"{label}: unexpected scenario properties: {', '.join(unexpected_fields)}"
            )
        if missing_fields:
            errors.append(
                f"{label}: missing scenario properties: {', '.join(missing_fields)}"
            )
        if scenario.get("audit_status") not in AUDIT_TO_DELIVERY:
            errors.append(f"{label}: invalid audit_status")
        if scenario.get("delivery_status") not in DELIVERY_STATUSES:
            errors.append(f"{label}: invalid delivery_status")
        if scenario.get("disposition") not in DISPOSITIONS:
            errors.append(f"{label}: invalid disposition")
        proof_classes = scenario.get("required_proof_classes")
        if (
            not isinstance(proof_classes, list)
            or not proof_classes
            or any(
                not isinstance(value, str) or value not in PROOF_CLASSES
                for value in proof_classes
            )
            or proof_classes != sorted(set(proof_classes))
        ):
            errors.append(f"{label}: malformed required_proof_classes")
        evidence_paths = scenario.get("evidence_paths")
        if (
            not isinstance(evidence_paths, list)
            or any(not isinstance(value, str) for value in evidence_paths)
            or len(evidence_paths) != len(set(evidence_paths))
            or evidence_paths != sorted(evidence_paths)
            or any(not validate_evidence_path(value, repository_root) for value in evidence_paths)
        ):
            errors.append(f"{label}: malformed evidence_paths")
        if (
            scenario.get("checkbox_state") == "checked"
            or scenario.get("delivery_status") == "fully_implemented"
        ) and not evidence_paths:
            errors.append(f"{label}: completion claim requires evidence_paths")
        tracker_line = scenario.get("tracker_line")
        if (
            not isinstance(tracker_line, int)
            or isinstance(tracker_line, bool)
            or tracker_line < 1
            or tracker_line > tracker_line_count
        ):
            errors.append(f"{label}: tracker_line is outside the authoritative tracker")
        for verification_error in validate_verification_identity(
            scenario.get("last_verified_commit"),
            scenario.get("last_verified_build"),
            evidence_paths if isinstance(evidence_paths, list) else [],
            repository_root,
            scenario_id=scenario.get("id"),
            required_proof_classes=proof_classes if isinstance(proof_classes, list) else [],
        ):
            errors.append(f"{label}: {verification_error}")

    try:
        expected = build_registry(tracker_path, repository_root, existing=payload)
    except (OSError, ValueError) as error:
        errors.append(f"tracker parse failed: {error}")
        return errors

    if payload.get("tracker_sha256") != expected["tracker_sha256"]:
        errors.append("tracker_sha256 does not match the authoritative tracker")
    if len(scenarios) == len(expected["scenarios"]):
        mutable_fields = {"evidence_paths", "last_verified_commit", "last_verified_build"}
        for actual, generated in zip(scenarios, expected["scenarios"]):
            actual_stable = {key: value for key, value in actual.items() if key not in mutable_fields}
            generated_stable = {key: value for key, value in generated.items() if key not in mutable_fields}
            if actual_stable != generated_stable:
                errors.append(
                    f"tracker drift: {actual.get('id', 'unknown ID')} no longer matches its tracker scenario"
                )
                break
    return errors


def write_registry(tracker_path, registry_path, repository_root):
    existing = None
    if registry_path.exists():
        existing = json.loads(registry_path.read_text(encoding="utf-8"))
    payload = build_registry(tracker_path, repository_root, existing=existing)
    registry_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return payload


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("sync", "validate"))
    parser.add_argument("--tracker", type=Path, default=DEFAULT_TRACKER)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    args = parser.parse_args(argv)

    if args.command == "sync":
        payload = write_registry(args.tracker, args.registry, ROOT)
        print(f"Synced {payload['scenario_count']} scenarios to {args.registry.relative_to(ROOT)}")
        return 0

    try:
        payload = json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Registry could not be read: {error}", file=sys.stderr)
        return 1
    errors = validate_registry(payload, args.tracker, ROOT)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Validated {payload['scenario_count']} scenarios with no tracker drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
