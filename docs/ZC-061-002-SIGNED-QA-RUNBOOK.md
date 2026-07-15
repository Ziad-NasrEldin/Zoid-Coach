# ZC-061-002 signed QA runbook

This runbook verifies one active declared-technical task with temporally overlapping Safari and YouTube tutorial evidence in an isolated signed QA package.
The required technical-context parent is `a17f1c2c697b769dc80af959b2385d418d8074c8`.
This is a deterministic verification fixture, not a production ingestion bypass and not proof that the activity was Research.
The general task remains undeclared, unplanned, and inactive.
Stop immediately after any failed assertion.

## Bind the exact signed package

Install a clean signed QA package in an isolated root.
Grant Accessibility permission to the terminal running the probe.
Close unrelated copies of the app.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
DATABASE="/private/tmp/zc061002/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc061002-related-tutorial-fixture.sh"
PROBE="$PWD/Scripts/qa-zc061002-related-tutorial-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc061002-signed-preflight.sh"
STATIC="$PWD/Scripts/verify-zc-061-002-related-tutorial-static.sh"
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
"$STATIC"
open "$APP" --args --qa-open-main
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
PID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
```

The preflight binds the exact app executable, helper executable, clean build commit, technical-context parent, shared QA root, and open database.
It rejects abbreviated identities, another installed bundle, another PID, a helper from another bundle, and a database outside the embedded QA root.

## Prepare the deterministic relationship

Stop the app and helper before changing the isolated database.
The fixture refuses to continue if another active interval exists or any owned namespace row already exists.

```sh
set -euo pipefail
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare --database "$DATABASE"
"$FIXTURE" verify --database "$DATABASE"
open "$APP" --args --qa-open-main
"$APP_EXECUTABLE" --qa-register-agent
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
PID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
```

The fixture uses the production `source_tasks`, `daily_plan_entries`, `task_execution_states`, `task_activity_intervals`, and `behavior_records` schemas.
It creates one active task whose declaration is exactly `technical`, one undeclared general boundary task, and five current-day Safari records inside the active interval.
Every browser record uses the same public tutorial window and public YouTube URL, stores no screenshot, and remains classified only as Work.

## Prove the active commitment and browser evidence

Wait for Today to show `QA ZC-061-002 technical task` as the active commitment.
Scroll until the normal behavior-evidence action is visible.
The probe presses that production action and binds the resulting sheet.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --phase active-browser-visible
"$FIXTURE" verify --database "$DATABASE"
```

The probe requires the technical-task title, technical declaration, and active commitment before opening evidence.
It then requires Safari to appear in `WORK CONTEXT LEFT UNCERTAIN`, requires a nonzero Work total, and requires the Research total to remain exactly zero minutes.
It fails if the raw tutorial window, URL, local path, token, or host detail appears in accessibility output.
This proves observed browser evidence without inventing a Research classification or exposing private context.

## Cleanly restore the isolated database

Stop both processes before cleanup.
Cleanup deletes only the two exact task identifiers and the exact `qa-zc061002-` behavior time-label namespace.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup --database "$DATABASE"
"$FIXTURE" verify-clean --database "$DATABASE"
```

Do not mark ZC-061-003 complete from this run.
Research classification requires a separate product contract and separate evidence.
