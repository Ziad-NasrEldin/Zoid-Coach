# ZC-061-001 signed QA runbook

This runbook verifies optional technical task context against one exact signed QA candidate and isolated database.
Absence of the declaration remains the legacy general-task boundary.
Do not continue after a failed assertion.

## Bind the signed candidate

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
DATABASE="/private/tmp/zc061001/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
PREFLIGHT="$PWD/Scripts/qa-zc061001-signed-preflight.sh"
FIXTURE="$PWD/Scripts/qa-zc061001-technical-task-fixture.sh"
PROBE="$PWD/Scripts/qa-zc061001-technical-task-ax-probe.swift"
STATIC="$PWD/Scripts/verify-zc-061-001-technical-task-static.sh"
"$STATIC"
"$PREFLIGHT" --self-test
open "$APP" --args --qa-open-main
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
PID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
```

The preflight proves the running executable belongs to the exact clean signed package and binds the database path used for the session.

## Verify explicit creation control

Open the normal local-task creation sheet from Today.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --phase creation-visible
```

Confirm `TECHNICAL TASK` is visible and off by default.
Enter `QA ZC-061-001 signed user technical task`, turn the control on, keep `ADD TO TODAY'S PLAN` on, and press `CREATE LOCAL TASK`.
Prove the production command persisted the declaration.

```sh
set -euo pipefail
"$FIXTURE" assert-created "$DATABASE"
```

## Verify durable context and the general boundary

Quit the app before fixture mutation, then prepare the isolated database and relaunch the same bundle.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
open "$APP" --args --qa-open-main
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
PID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
```

The fixture proves the technical row persists as `technical` and a row without a declaration remains `NULL`.

## Verify live plan and active accessibility

Start `QA ZC-061-001 signed user technical task` through the normal Today task action.
Wait for the live plan refresh without relaunching.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --phase active-visible
```

Confirm the active surface exposes both `TECHNICAL TASK` and `ACTIVE COMMITMENT`.
Confirm the general fixture task does not acquire a technical label.

## Cleanup

```sh
set -euo pipefail
kill "$PID" 2>/dev/null || true
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup "$DATABASE"
```
