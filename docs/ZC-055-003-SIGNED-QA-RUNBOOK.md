# ZC-055-003 signed keyboard lifecycle QA runbook

This runbook verifies that one exact installed signed Zoid 666 candidate can start, pause, resume, switch, and complete tasks using only documented keyboard shortcuts.
It also verifies shortcut discoverability, exact accessible labels, correct disabled states, durable time preservation, the durable switch reason, ordinary relaunch persistence, privacy, and byte-exact restoration.
The signed candidate must be one direct child of current canonical `b97c2ce3177ccf89f60225c475062608db1920ad` and contain only the exact six-file ZC-055-003 contract.
The audited source candidate is `e8b037ec47824541da51ecaba2c7477ff2a9a029`, whose lineage starts at source canonical `7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b`, continues through keyboard lifecycle product commit `6d8ec43867e0bf6aee53bb089f0fa7cf508ce870`, product correction `f260fa8f14d69e49b33e411366a6fc06ddd7dcf2`, and tooling commit `7efed0f712ffcc35f9f7afb9b3aa136c32e9fc51`.
The source patch IDs are `764437992c743d0fba4109360a66b3d89c9fff06`, `0a5662a3b0c5c69a5b98a516e6faf2ee1fa83a4a`, and `5226588dbc0b50b5b034e4dabc2e1eecd12a2898`; the complete audited source patch ID is `94063e987c858110ad30cdd35dd4ab0aca8a3650`.
The product, test, fixture, and Accessibility probe files must remain byte-identical to the audited source candidate; only this runbook and the signed preflight lineage bindings may differ.

The verifier reads the native Task menu through Accessibility only to confirm its labels, shortcut metadata, and enabled states.
Every lifecycle mutation is delivered as a real Command-Option chord through `CGEvent at the HID event tap` while the installed app is frontmost.
The verifier never substitutes an accessibility press, direct XPC call, database mutation, or product-only test seam for those keyboard actions.

## Bind the exact signed package

Use a clean QA package whose embedded root is in the isolated ZC-055-003 namespace.
Grant Accessibility and event-posting permission to the terminal that runs the verifier before starting.
Do not change macOS permissions during this run.
Do not run this journey while another signed-QA lane owns the installed app, LaunchAgent, or Mach service.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc055003-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE_SNAPSHOT="/private/tmp/zoid-666-zc055003-baseline"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc055003-keyboard-lifecycle-fixture.sh"
AX_PROBE="$PWD/Scripts/qa-zc055003-keyboard-lifecycle-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc055003-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
PRIMARY_TASK_ID="qa-zc055003-keyboard-primary"
TARGET_TASK_ID="qa-zc055003-keyboard-target"
PRIMARY_TASK_TITLE="QA keyboard lifecycle primary"
TARGET_TASK_TITLE="QA keyboard lifecycle switch target"
PRIVATE_NOTE="qa-zc055003-private-note"

test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT^")" = b97c2ce3177ccf89f60225c475062608db1920ad
test "$(git rev-list --count "b97c2ce3177ccf89f60225c475062608db1920ad..$EXPECTED_SIGNED_COMMIT")" = 1
"$PREFLIGHT" --self-test
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean

APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
test -x "$APP_EXECUTABLE"
test "$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")" = "$QA_ROOT"
```

The full commit must be the repository HEAD passed to the preflight.
The preflight requires exactly the reviewed two product files and four verifier files relative to current canonical `b97c2ce3177ccf89f60225c475062608db1920ad`.
It rejects tracker, registry, unrelated product, or additional commit drift.

## Establish and snapshot the ready-state baseline

Stop the exact installed app and helper before replacing the isolated root.
Launch the foreground app before registering the helper so both processes bind the same package and root.

```sh
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
  if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
rm -rf -- "$BASELINE_SNAPSHOT" "$BASELINE_SNAPSHOT".zc055003-*(N)
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

The snapshot is taken only after the app and helper stop and SQLite checkpoints its WAL.
Every journey below restores and compares this same manifest.

Define one ordinary-launch helper for the remaining phases.
It binds the scene-restored main window before helper registration and then confirms the same PID with the helper holding the exact database.

```sh
launch_ordinary() {
  open "$APP"
  ORDINARY_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open --require-helper-unregistered)"
  PID="$(printf '%s\n' "$ORDINARY_OUTPUT" | sed -n 's/^APP_PID=//p')"
  test -n "$PID"
  "$APP_EXECUTABLE" --qa-register-agent
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open --expected-app-pid "$PID"
}

relaunch_ordinary() {
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  open "$APP"
  ORDINARY_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open)"
  PID="$(printf '%s\n' "$ORDINARY_OUTPUT" | sed -n 's/^APP_PID=//p')"
  test -n "$PID"
}

stop_and_unregister() {
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  "$APP_EXECUTABLE" --qa-unregister-agent
  sqlite3 "$DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);'
}

probe() {
  swift "$AX_PROBE" --pid "$PID" "$@" \
    --forbid "$DATABASE" \
    --forbid "$QA_ROOT" \
    --forbid "$PRIMARY_TASK_ID" \
    --forbid "$TARGET_TASK_ID" \
    --forbid "$PRIVATE_NOTE"
}
```

## Prove Start and active-session relaunch persistence

Prepare exactly two local tasks while both signed processes are stopped.
The primary task is the only ready recommendation and the target is the only ready alternative.

```sh
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-ready "$DATABASE"
launch_ordinary
probe --phase ready --send start
"$FIXTURE" assert-active-primary "$DATABASE"
relaunch_ordinary
probe --phase active-primary
"$FIXTURE" assert-active-primary "$DATABASE"
```

The ready phase requires the exact `Start Recommended Task: QA keyboard lifecycle primary` label and Command-Option-S metadata.
Pause, Switch, and Complete must all be disabled before Start.
The HID chord must create exactly one active primary state and one open interval.
The ordinary relaunch must preserve that same active session without creating another open interval.

## Prove Pause and paused-session relaunch persistence

```sh
probe --phase active-primary --send pause
"$FIXTURE" assert-paused-primary "$DATABASE"
PAUSED_INTERVAL_ID="$(sqlite3 -noheader "$DATABASE" \
  "SELECT id FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NOT NULL ORDER BY id LIMIT 1;")"
PAUSED_INTERVAL_BYTES="$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT id, task_id, started_at, ended_at FROM task_activity_intervals WHERE id = $PAUSED_INTERVAL_ID;")"
test -n "$PAUSED_INTERVAL_BYTES"
relaunch_ordinary
probe --phase paused-primary
"$FIXTURE" assert-paused-primary "$DATABASE"
```

The active phase requires exact Pause, Switch, and Complete labels for the primary task.
It requires Command-Option-P, Command-Option-K, and Command-Option-Return to be enabled while Start is disabled.
Pause must close the primary interval and persist one open `doneForNow` pause.
The ordinary relaunch must retain the exact Resume label and paused state.

## Prove Resume, preserved time, and Switch

```sh
probe --phase paused-primary --send resume
"$FIXTURE" assert-resumed-primary "$DATABASE"
test "$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT id, task_id, started_at, ended_at FROM task_activity_intervals WHERE id = $PAUSED_INTERVAL_ID;")" = "$PAUSED_INTERVAL_BYTES"
probe --phase active-primary --send switch
"$FIXTURE" assert-switched "$DATABASE"
test "$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT id, task_id, started_at, ended_at FROM task_activity_intervals WHERE id = $PAUSED_INTERVAL_ID;")" = "$PAUSED_INTERVAL_BYTES"
relaunch_ordinary
probe --phase switched-target
"$FIXTURE" assert-switched "$DATABASE"
```

Resume must close the open pause without altering the first closed interval and must open one new primary interval.
The active production snapshot names the active task as its recommendation, so Switch may fall back only to the one unambiguous Ready target.
The exact Switch label must identify both tasks and state that time is preserved.
Command-Option-K must close the second primary interval, persist `switchingTasks`, activate the target, and retain the first interval byte-for-byte.
The ordinary relaunch must retain the switched target and one global open interval.

## Prove Complete for active and paused tasks

```sh
probe --phase switched-target --send complete
"$FIXTURE" assert-target-completed "$DATABASE"
relaunch_ordinary
probe --phase primary-paused
"$FIXTURE" assert-target-completed "$DATABASE"
probe --phase primary-paused --send complete
"$FIXTURE" assert-primary-completed "$DATABASE"
relaunch_ordinary
probe --phase no-active
"$FIXTURE" assert-primary-completed "$DATABASE"
```

Command-Option-Return must complete the active target, close its interval, and persist local-source completion.
The remaining single paused primary task must expose an exact enabled Complete label after ordinary relaunch.
The same shortcut must complete that paused task, close its pause, and leave no active interval.
The final ordinary relaunch must expose all four lifecycle commands as disabled.

Stop both processes and prove the first byte restoration.

```sh
stop_and_unregister
"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

## Prove ambiguous paused tasks fail closed

Prepare two ordinary paused tasks from the restored baseline.
Neither Pause/Resume nor Complete may guess which task the user means.

```sh
"$FIXTURE" prepare-ambiguous "$DATABASE"
"$FIXTURE" assert-ambiguous "$DATABASE"
AMBIGUOUS_BEFORE="$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT task_id, state FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id; SELECT task_id, reason, paused_at, COALESCE(resumed_at,'') FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id,id;")"
launch_ordinary
probe --phase ambiguous --send complete
"$FIXTURE" assert-ambiguous "$DATABASE"
test "$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT task_id, state FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id; SELECT task_id, reason, paused_at, COALESCE(resumed_at,'') FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id,id;")" = "$AMBIGUOUS_BEFORE"
relaunch_ordinary
probe --phase ambiguous
"$FIXTURE" assert-ambiguous "$DATABASE"
stop_and_unregister
"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

The ambiguous phase requires all four Task menu commands to remain disabled with generic labels.
Sending Command-Option-Return must leave the owned state and pause projection unchanged.
The ordinary relaunch must preserve the same honest disabled state.

## Prove Complete fails closed with no active or paused task

```sh
"$FIXTURE" prepare-no-active "$DATABASE"
"$FIXTURE" assert-no-active "$DATABASE"
NO_ACTIVE_BEFORE="$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT task_id, state FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id; SELECT source_id, is_completed FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY source_id;")"
launch_ordinary
probe --phase no-active --send complete
"$FIXTURE" assert-no-active "$DATABASE"
test "$(sqlite3 -noheader -separator '|' "$DATABASE" \
  "SELECT task_id, state FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY task_id; SELECT source_id, is_completed FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID','$TARGET_TASK_ID') ORDER BY source_id;")" = "$NO_ACTIVE_BEFORE"
relaunch_ordinary
probe --phase no-active
"$FIXTURE" assert-no-active "$DATABASE"
stop_and_unregister
"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

The no-active phase requires generic labels and all four shortcuts disabled.
Sending Command-Option-Return must not change task state or local completion truth.
The ordinary relaunch must preserve the same disabled menu.

## Acceptance boundary

Every AX phase recursively scans the unique visible main window and native menu labels.
The scan rejects the database path, QA root, fixture IDs, and the private source note.
Every menu phase requires exactly four lifecycle items with exact Command-Option shortcut metadata and phase-correct enabled states.

Do not mark ZC-055-003 fully usable unless every package, lineage, foreground-before-helper, ordinary relaunch, fixture, native menu, HID chord, database truth, privacy, and byte-restoration assertion passes against one installed signed identity.
Static tests or source-code presence alone do not qualify.
