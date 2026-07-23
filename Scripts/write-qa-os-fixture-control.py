#!/usr/bin/env python3

"""Write a QA OS fixture control request in Swift Codable's canonical format."""

import argparse
import json
import os
import tempfile
from pathlib import Path


PERMISSIONS = {"reminders", "calendar", "notifications"}
PERMISSION_STATES = {"granted", "denied", "restricted", "notDetermined"}
OPERATIONS = {"seed", "reset", "snapshot", "notificationAction"}


def fail(message: str) -> None:
    raise SystemExit(message)


def encode_permissions(value: object) -> list[str]:
    if not isinstance(value, dict):
        fail("seed.permissions must be a JSON object")
    unknown = set(value) - PERMISSIONS
    if unknown:
        fail(f"unsupported permission: {sorted(unknown)[0]}")
    for permission, state in value.items():
        if state not in PERMISSION_STATES:
            fail(f"unsupported state for {permission}: {state}")
    encoded: list[str] = []
    for permission in sorted(value):
        encoded.extend([permission, value[permission]])
    return encoded


def canonical_request(value: object) -> dict:
    if not isinstance(value, dict):
        fail("request must be a JSON object")
    request_id = value.get("requestID")
    if not isinstance(request_id, str) or not request_id.strip():
        fail("requestID must be a non-empty string")
    operation = value.get("operation")
    if operation not in OPERATIONS:
        fail(f"unsupported operation: {operation}")
    result = dict(value)
    if operation == "seed" and not isinstance(result.get("seed"), dict):
        fail("seed operation requires a seed object")
    if isinstance(result.get("seed"), dict):
        seed = dict(result["seed"])
        seed["permissions"] = encode_permissions(seed.get("permissions", {}))
        result["seed"] = seed
    return result


def write_atomic(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=Path, help="Object-form control request JSON")
    parser.add_argument("qa_root", type=Path, help="Absolute isolated QA run root")
    args = parser.parse_args()
    if not args.qa_root.is_absolute() or args.qa_root == Path("/"):
        fail("qa_root must be an absolute non-root path")
    if args.qa_root.is_symlink():
        fail("qa_root cannot be a symbolic link")
    try:
        request = json.loads(args.request.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not read request: {error}")
    target = args.qa_root / "QA Control/os-fixture-request.json"
    processing = target.with_name("os-fixture-request.processing.json")
    if target.exists() or processing.exists():
        fail("a QA OS fixture control request is already pending")
    write_atomic(target, canonical_request(request))
    print(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
