#!/usr/bin/env python3
"""Prepare an isolated signed-QA root that opens directly at Today."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


class ManifestError(ValueError):
    pass


STEPS = [
    "welcome",
    "localPrivacy",
    "reminders",
    "screenwatch",
    "notifications",
    "applicationInventory",
    "activityClassification",
    "schedule",
    "gamingPolicy",
    "coachingMode",
    "deliveryTest",
    "firstDailyPlan",
]
PERMISSION_STATES = {"granted", "denied", "restricted", "notDetermined"}
ACCESS_STATES = {"granted", "denied", "unavailable", "deferred"}
SCREENWATCH_STATES = {"healthy", "stale", "missing", "deferred"}
DATE_DIRECTORY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def fail(message: str) -> None:
    raise ManifestError(message)


def exact_keys(value: dict[str, Any], required: set[str], optional: set[str], path: str) -> None:
    missing = required - value.keys()
    unknown = value.keys() - required - optional
    if missing:
        fail(f"{path} is missing: {', '.join(sorted(missing))}")
    if unknown:
        fail(f"{path} has unsupported fields: {', '.join(sorted(unknown))}")


def require_object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{path} must be an array")
    return value


def require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{path} must be a non-empty string")
    return value


def require_number(value: Any, path: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{path} must be a number")
    return float(value)


def validate_identified_objects(
    values: Any,
    path: str,
    required: set[str],
    optional: set[str],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    identifiers: set[str] = set()
    for index, raw in enumerate(require_list(values, path)):
        item_path = f"{path}[{index}]"
        item = require_object(raw, item_path)
        exact_keys(item, required, optional, item_path)
        identifier = require_string(item.get("id"), f"{item_path}.id")
        if identifier in identifiers:
            fail(f"{path} contains duplicate id {identifier}")
        identifiers.add(identifier)
        result.append(item)
    return result


def validate_manifest(raw: Any) -> dict[str, Any]:
    manifest = require_object(raw, "manifest")
    exact_keys(manifest, {"schemaVersion", "onboarding", "osFixture", "screenwatch"}, set(), "manifest")
    if manifest["schemaVersion"] != 1:
        fail("manifest.schemaVersion must be 1")

    onboarding = require_object(manifest["onboarding"], "manifest.onboarding")
    exact_keys(
        onboarding,
        {
            "coachingMode",
            "remindersAccess",
            "screenwatchAccess",
            "notificationAccess",
            "reminderListDecisions",
        },
        set(),
        "manifest.onboarding",
    )
    if onboarding["coachingMode"] not in {"rulesOnly", "optionalAI"}:
        fail("manifest.onboarding.coachingMode is invalid")
    for key in ("remindersAccess", "screenwatchAccess", "notificationAccess"):
        if onboarding[key] not in ACCESS_STATES:
            fail(f"manifest.onboarding.{key} is invalid")

    decisions: list[dict[str, Any]] = []
    decision_ids: set[str] = set()
    for index, raw_decision in enumerate(require_list(
        onboarding["reminderListDecisions"],
        "manifest.onboarding.reminderListDecisions",
    )):
        decision = require_object(raw_decision, f"manifest.onboarding.reminderListDecisions[{index}]")
        exact_keys(
            decision,
            {"listID", "isIncluded"},
            set(),
            f"manifest.onboarding.reminderListDecisions[{index}]",
        )
        list_id = require_string(decision["listID"], f"manifest.onboarding.reminderListDecisions[{index}].listID")
        if list_id in decision_ids:
            fail(f"manifest.onboarding.reminderListDecisions contains duplicate listID {list_id}")
        decision_ids.add(list_id)
        if not isinstance(decision["isIncluded"], bool):
            fail(f"manifest.onboarding.reminderListDecisions[{index}].isIncluded must be boolean")
        decisions.append(decision)

    fixture = require_object(manifest["osFixture"], "manifest.osFixture")
    exact_keys(
        fixture,
        {"permissions", "reminderLists", "reminders", "calendarCommitments", "notifications"},
        set(),
        "manifest.osFixture",
    )
    permissions = require_object(fixture["permissions"], "manifest.osFixture.permissions")
    exact_keys(permissions, {"reminders", "calendar", "notifications"}, set(), "manifest.osFixture.permissions")
    for key, state in permissions.items():
        if state not in PERMISSION_STATES:
            fail(f"manifest.osFixture.permissions.{key} is invalid")

    reminder_lists = validate_identified_objects(
        fixture["reminderLists"],
        "manifest.osFixture.reminderLists",
        {"id", "name"},
        set(),
    )
    list_ids = {require_string(item["id"], "reminder list id") for item in reminder_lists}
    for item in reminder_lists:
        require_string(item["name"], f"reminder list {item['id']} name")
    if not decision_ids.issubset(list_ids):
        fail("manifest.onboarding.reminderListDecisions references an unknown fixture list")

    reminders = validate_identified_objects(
        fixture["reminders"],
        "manifest.osFixture.reminders",
        {"id", "title", "listIdentifier", "priority", "isCompleted"},
        {"dueDate", "notes", "metadataMarker"},
    )
    for item in reminders:
        require_string(item["title"], f"reminder {item['id']} title")
        list_identifier = require_string(item["listIdentifier"], f"reminder {item['id']} listIdentifier")
        if list_identifier not in list_ids:
            fail(f"reminder {item['id']} references unknown list {list_identifier}")
        if isinstance(item["priority"], bool) or not isinstance(item["priority"], int):
            fail(f"reminder {item['id']} priority must be an integer")
        if not isinstance(item["isCompleted"], bool):
            fail(f"reminder {item['id']} isCompleted must be boolean")
        if item.get("dueDate") is not None:
            require_number(item["dueDate"], f"reminder {item['id']} dueDate")

    commitments = validate_identified_objects(
        fixture["calendarCommitments"],
        "manifest.osFixture.calendarCommitments",
        {"id", "title", "start", "end", "calendarIdentifier", "participants"},
        {"ownershipToken", "meetingFingerprint"},
    )
    for item in commitments:
        require_string(item["title"], f"calendar commitment {item['id']} title")
        require_string(item["calendarIdentifier"], f"calendar commitment {item['id']} calendarIdentifier")
        if require_number(item["end"], f"calendar commitment {item['id']} end") <= require_number(
            item["start"], f"calendar commitment {item['id']} start"
        ):
            fail(f"calendar commitment {item['id']} must end after it starts")
        if not all(isinstance(value, str) for value in require_list(item["participants"], "participants")):
            fail(f"calendar commitment {item['id']} participants must be strings")

    notifications = validate_identified_objects(
        fixture["notifications"],
        "manifest.osFixture.notifications",
        {"id", "desired", "status"},
        {"deliveredAt", "actionIdentifier", "respondedAt"},
    )
    for item in notifications:
        desired = require_object(item["desired"], f"notification {item['id']} desired")
        exact_keys(desired, {"category", "title", "body", "promptID"}, {"deliveryDate"}, "notification desired")
        for key in ("category", "title", "body", "promptID"):
            require_string(desired[key], f"notification {item['id']} desired.{key}")
        if desired.get("deliveryDate") is not None:
            require_number(desired["deliveryDate"], f"notification {item['id']} deliveryDate")
        if item["status"] not in {"scheduled", "delivered", "responded"}:
            fail(f"notification {item['id']} status is invalid")

    screenwatch = require_object(manifest["screenwatch"], "manifest.screenwatch")
    exact_keys(screenwatch, {"state", "days"}, set(), "manifest.screenwatch")
    if screenwatch["state"] not in SCREENWATCH_STATES:
        fail("manifest.screenwatch.state is invalid")
    days = require_list(screenwatch["days"], "manifest.screenwatch.days")
    if screenwatch["state"] in {"missing", "deferred"} and days:
        fail("missing or deferred Screenwatch state cannot contain days")
    if screenwatch["state"] in {"healthy", "stale"} and not days:
        fail("healthy or stale Screenwatch state requires at least one day")
    seen_days: set[str] = set()
    for index, raw_day in enumerate(days):
        day = require_object(raw_day, f"manifest.screenwatch.days[{index}]")
        exact_keys(day, {"date", "records"}, set(), f"manifest.screenwatch.days[{index}]")
        date = require_string(day["date"], f"manifest.screenwatch.days[{index}].date")
        if not DATE_DIRECTORY.fullmatch(date) or date in seen_days:
            fail(f"invalid or duplicate Screenwatch day {date}")
        seen_days.add(date)
        records = require_list(day["records"], f"Screenwatch day {date} records")
        if not records:
            fail(f"Screenwatch day {date} requires records")
        for record_index, raw_record in enumerate(records):
            record = require_object(raw_record, f"Screenwatch day {date} record {record_index}")
            exact_keys(record, {"t", "epoch", "app", "window", "url", "img"}, set(), "Screenwatch record")
            for key in ("t", "app", "window", "url"):
                if not isinstance(record[key], str):
                    fail(f"Screenwatch record {key} must be a string")
            if isinstance(record["epoch"], bool) or not isinstance(record["epoch"], int):
                fail("Screenwatch record epoch must be an integer")
            if not isinstance(record["img"], bool):
                fail("Screenwatch record img must be boolean")

    if onboarding["remindersAccess"] == "granted" and permissions["reminders"] != "granted":
        fail("granted onboarding Reminders access requires granted fixture permission")
    if onboarding["notificationAccess"] == "granted" and permissions["notifications"] != "granted":
        fail("granted onboarding notification access requires granted fixture permission")
    if onboarding["screenwatchAccess"] == "granted" and screenwatch["state"] not in {"healthy", "stale"}:
        fail("granted onboarding Screenwatch access requires healthy or stale fixture data")

    return manifest


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build_root(staging: Path, manifest: dict[str, Any]) -> None:
    onboarding = manifest["onboarding"]
    progress = {
        "version": 1,
        "flowID": "qa-ready-state-v1",
        "persistenceRevision": 1,
        "currentStep": "firstDailyPlan",
        "completedSteps": STEPS,
        "coachingMode": onboarding["coachingMode"],
        "remindersAccess": onboarding["remindersAccess"],
        "screenwatchAccess": onboarding["screenwatchAccess"],
        "notificationAccess": onboarding["notificationAccess"],
        "reminderListDecisions": onboarding["reminderListDecisions"],
        "emptyReminderListFallbackConfirmed": not onboarding["reminderListDecisions"],
        "deliveryTestTaskCompleted": True,
        "completedEffects": [],
        "finishedAt": 0,
    }
    write_json(staging / "Application Support/Zoid 666/onboarding-progress.json", progress)

    fixture = manifest["osFixture"]
    encoded_permissions: list[str] = []
    for key in sorted(fixture["permissions"]):
        encoded_permissions.extend([key, fixture["permissions"][key]])
    seed = dict(fixture)
    seed["permissions"] = encoded_permissions
    control = {
        "requestID": "qa-ready-state-seed-v1",
        "operation": "seed",
        "seed": seed,
    }
    write_json(staging / "QA Control/os-fixture-request.json", control)
    write_json(staging / "QA Control/ready-state-manifest.json", manifest)

    for day in manifest["screenwatch"]["days"]:
        path = staging / "Screenwatch/days" / day["date"] / "log.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [json.dumps(record, sort_keys=True, separators=(",", ":")) for record in day["records"]]
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("qa_root", type=Path)
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()

    if not args.qa_root.is_absolute() or args.qa_root == Path("/"):
        fail("qa_root must be an absolute non-root path")
    if args.qa_root.is_symlink():
        fail("qa_root cannot be a symbolic link")
    try:
        raw = json.loads(args.manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not read manifest: {error}")
    manifest = validate_manifest(raw)

    target = args.qa_root
    if target.exists() and not args.replace:
        fail("qa_root already exists; pass --replace to replace it atomically")
    target.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{target.name}.staging-", dir=target.parent))
    backup: Path | None = None
    try:
        build_root(staging, manifest)
        if target.exists():
            backup = target.with_name(f".{target.name}.backup-{os.getpid()}")
            os.replace(target, backup)
        os.replace(staging, target)
        if backup is not None:
            shutil.rmtree(backup)
    except Exception:
        if backup is not None and backup.exists() and not target.exists():
            os.replace(backup, target)
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"READY: isolated QA root prepared at {target}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ManifestError as error:
        print(f"SETUP_FAIL: {error}", file=sys.stderr)
        raise SystemExit(2)
