# ZC-016-006 signed QA runbook

This runbook verifies that one task started or switched from Today becomes the same single active task in Today and the compact menu bar.
It covers initial start, active-task switch, exactly-one persistence, ordinary app relaunch, helper-backed refresh, privacy, and byte restoration in one signed installed QA package.
It does not justify a Full claim by itself.

Acquire exclusive QA runtime ownership before this journey.
Do not start while another builder or verifier owns the installed QA app, helper, notifications, or Accessibility surface.
Do not touch production app or helper processes.

## Bind the exact candidate

Install one clean signed QA package in an isolated root.
Grant Accessibility permission to the terminal running the probe and close unrelated QA copies.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_CANDIDATE_COMMIT"
PREFLIGHT="$PWD/Scripts/qa-zc016006-signed-preflight.sh"
FIXTURE="$PWD/Scripts/qa-zc016006-single-active-everywhere-fixture.sh"
PROBE="$PWD/Scripts/qa-zc016006-single-active-everywhere-ax-probe.swift"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
WORK_ROOT="$(mktemp -d /private/tmp/zoid-zc016006-run.XXXXXX)"
MANIFEST="$WORK_ROOT/ready-state.json"
BACKUP_ROOT="$WORK_ROOT/original-root"
ORIGINAL_HASHES="$WORK_ROOT/original-hashes.txt"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_PLIST="$(find "$APP/Contents/Library/LaunchAgents" -type f -name '*.plist' -maxdepth 1 -print)"
AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
ORIGINAL_HELPER_REGISTERED=0
launchctl print "gui/$(id -u)/$(plutil -extract Label raw -o - "$AGENT_PLIST")" >/dev/null 2>&1 \
  && ORIGINAL_HELPER_REGISTERED=1
"$PREFLIGHT" --self-test
"$FIXTURE" self-test
swift "$PROBE" --self-test
```

The preflight rejects abbreviated revisions, packages not descending from canonical `b73a1c1c489eb02017d8609eab7a056296065819`, packages missing the committed verifier, another executable, another QA root, and a helper that does not own the isolated database.

## Preserve and prepare the isolated root

Stop the QA app and helper before backup or replacement.
Keep the backup outside the repository with mode 700.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
mkdir -m 700 "$BACKUP_ROOT"
if test -d "$QA_ROOT"; then
  ditto "$QA_ROOT" "$BACKUP_ROOT/root"
  (cd "$BACKUP_ROOT/root" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$ORIGINAL_HASHES"
else
  : > "$ORIGINAL_HASHES"
fi
fixture_output="$("$FIXTURE" materialize "$MANIFEST")"
printf '%s\n' "$fixture_output"
FIRST_TASK_ID="$(printf '%s\n' "$fixture_output" | sed -n 's/^FIRST_TASK_ID=//p')"
SECOND_TASK_ID="$(printf '%s\n' "$fixture_output" | sed -n 's/^SECOND_TASK_ID=//p')"
test -n "$FIRST_TASK_ID"
test -n "$SECOND_TASK_ID"
"$READY_STATE" "$MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
while ! test -f "$DATABASE"; do sleep 0.2; done
pkill -x "$APP_EXECUTABLE_NAME"
while pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null; do sleep 0.1; done
"$AGENT_EXECUTABLE" --draft-plan --once
```

The ready state contains two distinct Reminder tasks and a private Screenwatch sentinel that must never appear in either task surface.
The packaged agent creates the plan through the supported production draft path.

## Start the first task from Today

Register the packaged helper, open Today, and let the AX probe activate the first task through its bounded-sprint control.
The probe then opens the compact menu and requires the same active title and status on both surfaces.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-register-agent
open "$APP" --args --qa-open-main
preflight_output="$("$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$preflight_output"
APP_PID="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
test -n "$APP_PID"
swift "$PROBE" \
  --pid "$APP_PID" \
  --task-id "$FIRST_TASK_ID" \
  --task-title "Write the first focus brief" \
  --activate
"$FIXTURE" assert-database "$DATABASE" "$FIRST_TASK_ID"
```

The first database assertion requires one active execution state and one open activity interval for the same task.
Any second active state or interval fails the journey.

## Switch from Today and verify both surfaces

Activate the second task from Today and confirm the native switch alert.
The probe rejects the former title in the compact active-task summary and the database requires the former task to be paused.

```sh
set -euo pipefail
swift "$PROBE" \
  --pid "$APP_PID" \
  --task-id "$SECOND_TASK_ID" \
  --task-title "Prepare the second focus review" \
  --previous-title "Write the first focus brief" \
  --activate
"$FIXTURE" assert-database "$DATABASE" "$SECOND_TASK_ID" "$FIRST_TASK_ID"
```

This is the critical regression path.
Today changes its authoritative snapshot after the switch, and the already-open menu controller must replace its earlier fallback rather than keep showing the first task.

## Relaunch and verify persistence

Quit and reopen the foreground app without replacing the isolated root or restarting the helper.
Verify the second task remains the only active task in Today, the menu bar, and SQLite.

```sh
set -euo pipefail
kill "$APP_PID"
while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.1; done
open "$APP" --args --qa-open-main
preflight_output="$("$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT")"
APP_PID="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
swift "$PROBE" \
  --pid "$APP_PID" \
  --task-id "$SECOND_TASK_ID" \
  --task-title "Prepare the second focus review" \
  --previous-title "Write the first focus brief"
"$FIXTURE" assert-database "$DATABASE" "$SECOND_TASK_ID" "$FIRST_TASK_ID"
```

Record the visible Today state, compact menu state, exact app and helper PIDs, and database counts before cleanup.
Do not update the tracker or registry from builder or static evidence.

## Restore exactly

Stop the QA processes before restoring the isolated root.
Restore the prior helper registration state only after the byte comparison succeeds.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
rm -rf -- "$QA_ROOT"
if test -d "$BACKUP_ROOT/root"; then
  ditto "$BACKUP_ROOT/root" "$QA_ROOT"
  RESTORED_HASHES="$WORK_ROOT/restored-hashes.txt"
  (cd "$QA_ROOT" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$RESTORED_HASHES"
  cmp "$ORIGINAL_HASHES" "$RESTORED_HASHES"
else
  test ! -e "$QA_ROOT"
fi
if test "$ORIGINAL_HELPER_REGISTERED" = 1; then
  "$APP_EXECUTABLE" --qa-register-agent
fi
rm -rf -- "$WORK_ROOT"
```

Record the exact signed commit, package identity, app and helper PIDs, fixture output, both AX activation outputs, prompt-free privacy inspection, SQLite assertions, relaunch output, cleanup, and restoration hashes in immutable evidence.
