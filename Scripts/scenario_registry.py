#!/usr/bin/env python3
"""Generate and validate the Zoid Coach end-user scenario registry."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TRACKER = ROOT / "docs" / "zoid-coach-product-scenario-tracker.md"
DEFAULT_REGISTRY = ROOT / "docs" / "scenario-registry.json"
EXPECTED_SCENARIO_COUNT = 666

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
EVIDENCE_REFERENCE_PATTERN = re.compile(
    r"(?P<path>(?:[A-Za-z0-9_. -]+/)*[A-Za-z0-9_. -]+"
    r"\.(?:swift|sh|plist|md|json|jsonl|sqlite))(?::(?P<lines>\d+(?:-\d+)?))?"
)
VALID_EVIDENCE_PATH = re.compile(
    r"^[A-Za-z0-9_. -]+(?:/[A-Za-z0-9_. -]+)+"
    r"(?:\.(?:swift|sh|plist|md|json|jsonl|sqlite))"
    r"(?::\d+(?:-\d+)?)?$"
)


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


def repository_file_index(repository_root):
    excluded_parts = {".git", ".build", "DerivedData"}
    index = {}
    for path in repository_root.rglob("*"):
        if not path.is_file() or any(part in excluded_parts for part in path.parts):
            continue
        relative = path.relative_to(repository_root).as_posix()
        index.setdefault(path.name, []).append(relative)
    return index


def extract_evidence_paths(audit_note, file_index):
    evidence_paths = set()
    repository_paths = {path for candidates in file_index.values() for path in candidates}
    for code_span in re.findall(r"\x60([^\x60]+)\x60", audit_note or ""):
        for match in EVIDENCE_REFERENCE_PATTERN.finditer(code_span):
            raw_path = match.group("path").strip()
            lines = match.group("lines")
            if "/" in raw_path:
                if raw_path not in repository_paths:
                    continue
                resolved = raw_path
            else:
                candidates = file_index.get(raw_path, [])
                if len(candidates) != 1:
                    continue
                resolved = candidates[0]
            if lines:
                resolved = f"{resolved}:{lines}"
            evidence_paths.add(resolved)
    return sorted(evidence_paths)


def tracker_verification_metadata(tracker_text):
    commit_match = re.search(
        r"against branch \x60[^\x60]+\x60 at \x60([0-9a-f]{7,40})\x60",
        tracker_text,
    )
    build_match = re.search(r"installed version ([0-9.]+) Build ([0-9]+)", tracker_text)
    commit = commit_match.group(1) if commit_match else None
    build = f"{build_match.group(1)} ({build_match.group(2)})" if build_match else None
    return commit, build


def parse_tracker(tracker_path, repository_root):
    tracker_text = tracker_path.read_text(encoding="utf-8")
    verified_commit, verified_build = tracker_verification_metadata(tracker_text)
    file_index = repository_file_index(repository_root)
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
                "evidence_paths": extract_evidence_paths(audit_note, file_index),
                "last_verified_commit": verified_commit if is_checked else None,
                "last_verified_build": verified_build if is_checked else None,
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
        if not previous or previous.get("wording") != scenario["wording"]:
            continue
        preserved_evidence = {
            value
            for value in previous.get("evidence_paths", [])
            if validate_evidence_path(value, repository_root)
        }
        scenario["evidence_paths"] = sorted(
            set(scenario["evidence_paths"]) | preserved_evidence
        )
        if previous.get("last_verified_commit"):
            scenario["last_verified_commit"] = previous["last_verified_commit"]
        if previous.get("last_verified_build"):
            scenario["last_verified_build"] = previous["last_verified_build"]

    return {
        "$schema": "scenario-registry.schema.json",
        "schema_version": 1,
        "tracker_path": tracker_path.relative_to(repository_root).as_posix(),
        "tracker_sha256": hashlib.sha256(tracker_text.encode("utf-8")).hexdigest(),
        "scenario_count": len(scenarios),
        "scenarios": scenarios,
    }


def validate_evidence_path(value, repository_root):
    if not isinstance(value, str) or not VALID_EVIDENCE_PATH.fullmatch(value):
        return False
    path_without_lines = re.sub(r":\d+(?:-\d+)?$", "", value)
    return (repository_root / path_without_lines).is_file()


def validate_registry(payload, tracker_path=DEFAULT_TRACKER, repository_root=ROOT):
    tracker_path = Path(tracker_path)
    repository_root = Path(repository_root)
    errors = []
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
    duplicate_ids = sorted({item_id for item_id in ids if ids.count(item_id) > 1})
    if duplicate_ids:
        errors.append(f"duplicate scenario ID: {', '.join(duplicate_ids)}")

    for index, scenario in enumerate(scenarios, start=1):
        label = scenario.get("id", f"scenario {index}") if isinstance(scenario, dict) else f"scenario {index}"
        if not isinstance(scenario, dict):
            errors.append(f"{label} must be an object")
            continue
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
            or any(value not in PROOF_CLASSES for value in proof_classes)
            or proof_classes != sorted(set(proof_classes))
        ):
            errors.append(f"{label}: malformed required_proof_classes")
        evidence_paths = scenario.get("evidence_paths")
        if (
            not isinstance(evidence_paths, list)
            or evidence_paths != sorted(set(evidence_paths))
            or any(not validate_evidence_path(value, repository_root) for value in evidence_paths)
        ):
            errors.append(f"{label}: malformed evidence_paths")
        commit = scenario.get("last_verified_commit")
        if commit is not None and not re.fullmatch(r"[0-9a-f]{7,40}", commit):
            errors.append(f"{label}: malformed last_verified_commit")
        build = scenario.get("last_verified_build")
        if build is not None and (not isinstance(build, str) or not build.strip()):
            errors.append(f"{label}: malformed last_verified_build")

    try:
        expected = build_registry(tracker_path, repository_root, existing=payload)
    except (OSError, ValueError) as error:
        errors.append(f"tracker parse failed: {error}")
        return errors

    if payload.get("tracker_sha256") != expected["tracker_sha256"]:
        errors.append("tracker drift: tracker_sha256 does not match the authoritative tracker")
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
