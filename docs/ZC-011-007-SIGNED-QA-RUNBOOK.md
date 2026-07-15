# ZC-011-007 signed invalid-estimate QA runbook

This runbook verifies one exact installed signed Zoid 666 candidate against the full custom-estimate validation matrix.
It covers empty input, ASCII and Unicode whitespace, zero, negative values, decimal and text input, localized digits, localized decimal punctuation, values above 480 minutes, and a valid whitespace-padded recovery.
It also proves exact corrective copy, keyboard Return submission, retained input and focus after failure, no durable mutation on failure, valid persistence, accessibility, privacy, ordinary relaunch, and byte-exact restoration.

The product implementation is already present at canonical base `e38383374cdc8618b39a5eaaaae47ee5eaf638b7`.
This candidate may add only the four namespaced QA files listed by the preflight.
The preflight binds the exact canonical blobs for `TaskEstimateInput.swift`, `DashboardView.swift`, and `TaskEstimateInputTests.swift` so verifier work cannot silently change product behavior.

## Bind the exact signed package

Use a clean QA package whose embedded root is in the isolated ZC-011-007 namespace.
Grant Accessibility and event-posting permission to the terminal running the verifier before starting.
Do not change macOS permissions during this run.
Do not start while another signed-QA lane owns the installed app, LaunchAgent, or Mach service.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc011007-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE_SNAPSHOT="/private/tmp/zoid-666-zc011007-baseline"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc011007-invalid-estimate-fixture.sh"
AX_PROBE="$PWD/Scripts/qa-zc011007-invalid-estimate-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc011007-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
TASK_ID="qa-zc011007-invalid-estimate"
PRIVATE_NOTE="qa-zc011007-private-estimate-note"

test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor e38383374cdc8618b39a5eaaaae47ee5eaf638b7 "$EXPECTED_SIGNED_COMMIT"
"$PREFLIGHT" --self-test
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean

APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
test -x "$APP_EXECUTABLE"
test "$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")" = "$QA_ROOT"
```

The full signed commit must be repository HEAD.
The diff from canonical base must contain exactly one commit and exactly the four approved QA files.
Tracker, registry, Lavish, backlog, product, and unrelated verifier changes are rejected.

## Establish and snapshot the ready-state baseline

Stop the exact app and helper before replacing the isolated root.
Launch and bind the foreground app before helper registration.

```sh
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
  if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
rm -rf -- "$BASELINE_SNAPSHOT" "$BASELINE_SNAPSHOT".zc011007-*(N)
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
FOREGROUND_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered)"
printf '%s\n' "$FOREGROUND_OUTPUT"
PID="$(printf '%s\n' "$FOREGROUND_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
swift "$WINDOW_PROBE" "$PID" --expect-today
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$APP_EXECUTABLE" --qa-unregister-agent
sqlite3 "$DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);'
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

The snapshot occurs only after both signed processes stop and SQLite checkpoints its WAL.
The final restoration compares every file and symlink against this baseline.

## Prepare the exact missing-estimate task

The fixture replaces only the current isolated daily plan and adds one local main objective with no estimate and no active interval.
The entire root is restored later, including any baseline plan rows displaced by the deterministic fixture.

```sh
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-unmutated "$DATABASE"
open "$APP"
ORDINARY_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --require-helper-unregistered)"
PID="$(printf '%s\n' "$ORDINARY_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
```

Every probe call rejects the raw task ID, private fixture note, database path, and QA root from the accessibility tree.

```sh
probe() {
  swift "$AX_PROBE" --pid "$PID" "$@" \
    --forbid "$TASK_ID" \
    --forbid "$PRIVATE_NOTE" \
    --forbid "$DATABASE" \
    --forbid "$QA_ROOT"
}

probe --phase open
```

The open phase finds the exact task-specific Custom action through normal Today accessibility, opens it, and places keyboard focus in the labelled minutes field.
The editor must expose Save and Cancel without leaking fixture internals.

## Prove every invalid case with physical Return

Each submit phase focuses the same production field, uses Command-A and Delete to replace the previous correction, types the case through `CGEvent`, and submits with a physical Return key event at the HID event tap.
The editor must stay open with the exact raw input, keyboard focus, Save, Cancel, and the exact corrective sentence.
The database must remain missing-estimate truth after every failure.

```sh
probe --phase submit --case empty
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case whitespace
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case unicode-whitespace
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case zero
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case negative
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case decimal
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case text
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case localized-digits
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case localized-decimal
"$FIXTURE" assert-unmutated "$DATABASE"

probe --phase submit --case too-large
"$FIXTURE" assert-unmutated "$DATABASE"
```

The exact expected errors are:

- Empty, ASCII whitespace, and Unicode whitespace: `Enter an estimate in minutes.`
- Zero and negative values: `Estimate must be at least 1 minute.`
- Decimal, text, Arabic-Indic digits, and comma-decimal input: `Use a whole number of minutes, such as 25.`
- 481 minutes: `Estimate must be 480 minutes or less. Split larger work into smaller tasks.`

The localized inputs are intentionally rejected rather than silently misinterpreted.
No failure may show a confirmed estimate, close the editor, move focus away from correction, or write `estimate_minutes` or `estimate_is_uncertain`.

## Prove valid correction and durable recovery

Submit the whitespace-padded whole number ` 25 ` through the same focused field and physical Return path.

```sh
probe --phase submit --case valid-padded
"$FIXTURE" assert-valid "$DATABASE"
```

The editor must close, all stale error copy must disappear, and the exact accessible confirmation must read `Time estimate confirmed: 25 MIN`.
The fixture requires a durable value of exactly 25 minutes with uncertainty still false.

Quit and relaunch through an ordinary LaunchServices open without touching the database.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP"
RELAUNCH_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open)"
PID="$(printf '%s\n' "$RELAUNCH_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
probe --phase persisted
"$FIXTURE" assert-valid "$DATABASE"
```

The ordinary relaunch must restore exactly one main Today window and the same confirmed 25-minute estimate.
The custom editor and every prior validation error must remain closed and absent.

## Cleanup and byte restoration

Stop both signed processes before cleanup and restoration.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$APP_EXECUTABLE" --qa-unregister-agent
sqlite3 "$DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);'
"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

Cleanup removes every owned source, plan, execution, and interval row.
Root restoration then recovers the exact original ready-state bytes and symlinks, including any replaced baseline plan.

## Acceptance boundary

Do not mark ZC-011-007 fully usable unless every package, lineage, foreground-before-helper, ordinary relaunch, exact error, retained-focus, keyboard Return, no-mutation, valid-recovery, persistence, accessibility, privacy, cleanup, and byte-restoration assertion passes against one installed signed identity.
Static tests, source-code presence, or an AX value written without keyboard submission do not qualify.
