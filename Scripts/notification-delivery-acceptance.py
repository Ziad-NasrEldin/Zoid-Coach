#!/usr/bin/env python3

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Optional

from qa_run_root import canonical_qa_run_root


SCENARIOS = {
    "delivery-replacement-restart": {
        "permission": "granted",
        "failure": None,
        "scenario_ids": ["ZC-044-011", "ZC-048-004", "ZC-050-007", "ZC-054-008", "ZC-054-009"],
    },
    "scheduling-failure": {
        "permission": "granted",
        "failure": "qa_injected_schedule_failure",
        "scenario_ids": ["ZC-048-004", "ZC-050-003"],
    },
    "denied-repair": {
        "permission": "denied",
        "failure": None,
        "scenario_ids": ["ZC-044-013", "ZC-050-002", "ZC-062-005", "ZC-062-006"],
    },
}


def control_request(request_id: str, permission: str, failure: Optional[str]) -> dict:
    seed = {
        "permissions": ["notifications", permission],
        "reminderLists": [],
        "reminders": [],
        "calendarCommitments": [],
        "notifications": [],
    }
    if failure is not None:
        seed["notificationSchedulingFailure"] = failure
    return {
        "requestID": request_id,
        "operation": "seed",
        "seed": seed,
    }


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def prepare(root: Path) -> None:
    if root.exists() and any(root.iterdir()):
        raise SystemExit(f"Acceptance root is not empty: {root}")
    root.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schemaVersion": 1,
        "purpose": "notification-delivery-signed-qa-acceptance",
        "scenarios": {},
    }
    for name, configuration in SCENARIOS.items():
        run_root = root / name
        request_path = run_root / "QA Control" / "os-fixture-request.json"
        write_json(
            request_path,
            control_request(
                f"notification-acceptance-{name}-initial",
                configuration["permission"],
                configuration["failure"],
            ),
        )
        manifest["scenarios"][name] = {
            "qaRunRoot": str(run_root),
            "scenarioIDs": configuration["scenario_ids"],
            "expectedInitialPermission": configuration["permission"],
            "expectedSchedulingFailure": configuration["failure"],
        }
    write_json(root / "acceptance-manifest.json", manifest)
    (root / "ACCEPTANCE.md").write_text(acceptance_instructions(root), encoding="utf-8")


def advance_repair(root: Path) -> None:
    run_root = root / "denied-repair"
    state_path = run_root / "OS Fixtures" / "state.json"
    if not state_path.exists():
        raise SystemExit("Launch the denied-repair QA root once before advancing repair")
    request_path = run_root / "QA Control" / "os-fixture-request.json"
    processing_path = run_root / "QA Control" / "os-fixture-request.processing.json"
    if request_path.exists() or processing_path.exists():
        raise SystemExit("A fixture control request is still pending")
    write_json(
        request_path,
        control_request("notification-acceptance-repair-granted", "granted", None),
    )


def ledger_rows(run_root: Path) -> list[dict]:
    database = run_root / "Application Support" / "zoid-coach.sqlite"
    if not database.exists():
        raise SystemExit(f"Signed QA has not created its database: {database}")
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        rows = connection.execute(
            """
            SELECT category, outcome, recorded_at, attempt, replaced_prior_request,
                   redacted_error IS NOT NULL
            FROM notification_delivery_events
            ORDER BY recorded_at ASC, id ASC
            """
        ).fetchall()
    finally:
        connection.close()
    return [
        {
            "category": row[0],
            "outcome": row[1],
            "recordedAt": row[2],
            "attempt": row[3],
            "replacedPriorRequest": bool(row[4]),
            "hasRedactedError": bool(row[5]),
        }
        for row in rows
    ]


def verify(root: Path, output: Optional[Path]) -> None:
    results = {}
    for name in SCENARIOS:
        results[name] = ledger_rows(root / name)
    delivery = results["delivery-replacement-restart"]
    failure = results["scheduling-failure"]
    repair = results["denied-repair"]
    require(any(row["outcome"] == "delivered_by_fixture" for row in delivery), "delivery outcome missing")
    require(any(row["replacedPriorRequest"] for row in delivery), "replacement outcome missing")
    require(any(row["outcome"] == "scheduling_failed" and row["hasRedactedError"] for row in failure), "failure outcome missing")
    require(any(row["outcome"] == "authorization_unavailable" for row in repair), "denied fallback missing")
    require(any(row["outcome"] == "delivered_by_fixture" for row in repair), "repair delivery missing")
    evidence = {
        "schemaVersion": 1,
        "privacy": "No prompt identifiers, request identifiers, titles, bodies, or actions are exported.",
        "results": results,
    }
    if output is None:
        print(json.dumps(evidence, indent=2, sort_keys=True))
    else:
        write_json(output, evidence)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def acceptance_instructions(root: Path) -> str:
    return f"""# Notification Delivery Signed-QA Acceptance

Use one installed signed-QA application and the three isolated roots below.
Do not point a production app or production helper at these roots.

## Delivery, replacement, and restart

Launch with `--qa-run-root '{root / 'delivery-replacement-restart'}'`.
Reach Delivery Test and choose `SEND TEST PROMPT` twice without resolving the prompt.
Open Settings, choose Signals, and confirm two Delivered in QA rows where the newest row explains replacement instead of stacking.
Quit and relaunch with the same root and confirm the same history remains.

## Scheduling failure

Launch with `--qa-run-root '{root / 'scheduling-failure'}'`.
Reach Delivery Test and choose `SEND TEST PROMPT`.
Confirm Today fallback remains available.
Open Settings, choose Signals, and confirm Delivery Failed appears with no path, email address, prompt title, or body.

## Denial and repair

Launch with `--qa-run-root '{root / 'denied-repair'}'`.
Reach Notifications and Delivery Test, then confirm Access Needed and Today fallback.
Quit the application.
Run `python3 Scripts/notification-delivery-acceptance.py advance-repair '{root}'`.
Relaunch with the same root, refresh notification status, and send the test prompt.
Confirm Ready, Delivered in QA, the earlier Today Fallback row, and restart-safe history.

## Final evidence

Run `python3 Scripts/notification-delivery-acceptance.py verify '{root}' --output '<evidence.json>'`.
The verifier intentionally exports no prompt or request identifiers and no notification content.
"""


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)
    for command in ("prepare", "advance-repair", "verify"):
        child = subparsers.add_parser(command)
        child.add_argument("root", type=Path)
        if command == "verify":
            child.add_argument("--output", type=Path)
    return result


def main() -> None:
    arguments = parser().parse_args()
    root = canonical_qa_run_root(arguments.root)
    if arguments.command == "prepare":
        prepare(root)
    elif arguments.command == "advance-repair":
        advance_repair(root)
    else:
        verify(root, arguments.output)


if __name__ == "__main__":
    main()
