# ZC-044-004 signed QA runbook

This runbook verifies manual workday start and end against one exact installed signed candidate.
The product candidate is `03ed2a3ef6e14bd91cb0903d4c8b98be6ecdfa87`.
The signed build commit must contain that product candidate and verifier base `0068cd2d9da540818feea90ff1e39fc5270b97ee`.
Every command must run from the repository containing those commits.

The fixture uses the production policy, local-task, daily-plan, task-execution, activity-interval, and pause-event schemas.
The fixture owns only the `qa-zc044004-*` task namespace.
It records the original active policy version and restores its exact payload during cleanup.

## Preconditions and exact identity binding

Install a clean signed QA package in an isolated install root.
Grant Accessibility permission to the terminal that runs the AX probe.
Close unrelated copies of the app.
Do not continue after any failed assertion.

Set the exact installed paths and full signed integration commit.
The database path must be the database embedded in the QA bundle runtime root.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
DATABASE="/private/tmp/zc044004/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc044004-manual-workday-fixture.sh"
PROBE="$PWD/Scripts/qa-zc044004-manual-workday-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc044004-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
TASK_TITLE="QA ZC-044-004 manual workday task"
PRIVATE_ROOT="${DATABASE%/Application Support/Zoid 666/zoid-coach.sqlite}"
"$PREFLIGHT" --self-test
```

The preflight self-test parses this runbook and fails if helper registration appears before the foreground launch and PID binding after ready-state preparation.

Open the installed bundle and bind the session to its real executable, helper, signature, build identity, and isolated database.

```sh
open "$APP"
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$PREFLIGHT_OUTPUT"
PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
```

The preflight derives `CFBundleExecutable` from the installed `Info.plist`.
It rejects a PID whose executable path is outside the installed bundle.
It runs strict code-signature, package, clean-build, and exact build-identity verification.
It requires the signed commit to contain both the product candidate and verifier base.
It requires the app and LaunchAgent to embed the same canonical QA root.
It requires the helper's stripped-environment runtime identity and open SQLite file to resolve to `DATABASE`.

## Establish the supported post-onboarding QA state

A clean isolated runtime starts at onboarding and intentionally has no Dashboard Settings route.
ZC-044-004 tests Settings after onboarding, so establish the repository's supported 12-of-12 QA ready state before preparing the scenario database.
This is fixture state, not a product backdoor.
An ordinary launch intentionally preserves the app's previous scene state and does not force the main window to appear.
The signed QA package already provides the tested `--qa-open-main` presentation argument so verification can request the same main window that users open from the menu bar without changing production launch behavior.

```sh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$READY_STATE" "$READY_MANIFEST" "$PRIVATE_ROOT" --replace
open "$APP" --args --qa-open-main
FOREGROUND_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered)"
printf '%s\n' "$FOREGROUND_OUTPUT"
PID="$(printf '%s\n' "$FOREGROUND_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID")"
printf '%s\n' "$PREFLIGHT_OUTPUT"
CONFIRMED_PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
test "$CONFIRMED_PID" = "$PID"
swift "$WINDOW_PROBE" "$PID" --expect-today
```

The first preflight binds the foreground PID and argument while proving the helper is still unregistered.
The helper is registered only after that foreground binding succeeds.
The second preflight requires the same foreground PID and argument, the installed helper executable, the shared QA root, and the exact open database.
The Today assertion proves onboarding is complete and the normal Dashboard navigation is visible.
Do not continue if the app still exposes onboarding.

## Prepare scheduled baseline and ready task

Quit the app before fixture mutation.
The helper may remain registered, but it must not mutate the owned fixture namespace.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
open "$APP" --args --qa-open-main
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main)"
PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
```

## Save manual mode through production Settings

Leave the normal Today window visible.
The probe must begin from the scheduled baseline.
The probe presses the normal sidebar `Settings` button.
If the menu-bar popover is already open, it may instead press the production `menu-bar.open-settings` button.
It then binds the one visible window containing `SETTINGS / POLICY` and scrolls at most 12 pages to the Command schedule controls.

```sh
swift "$PROBE" --pid "$PID" --phase settings-select-manual \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-manual "$DATABASE"
```

The probe selects `Manual start and end` through the production segmented control.
It proves the fixed-hours group changes from enabled to disabled.
It presses the real `SAVE CHANGES` control and waits for `All changes saved`.
The fixture requires a newly versioned active manual policy while preserving at least one planning window.

## Prove Settings persistence after relaunch

Quit and relaunch the same installed bundle.
Leave the normal Today window visible after relaunch.
The probe must navigate to Settings again through the normal user-facing route.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP" --args --qa-open-main
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main)"
PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
swift "$PROBE" --pid "$PID" --phase settings-persisted \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-manual "$DATABASE"
```

The persisted-settings phase requires `Manual start and end` to remain selected.
It also requires the fixed-hours group to remain disabled.

## Prove stale Start is rejected without mutation

Open the menu-bar popover and leave the ready `START WORKDAY` control visible.
Inject the stale state only after the control is visible.

```sh
"$FIXTURE" inject-start-stale "$DATABASE"
swift "$PROBE" --pid "$PID" --phase stale-start \
  --expected-task-title "$TASK_TITLE" --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-start-stale "$DATABASE"
"$FIXTURE" restore-ready "$DATABASE"
```

The probe presses the stale production Start control.
It requires the honest `changed before Start` error and requires Start to disappear after the fresh state loads.
The fixture requires no active interval and no end-workday pause mutation.

Close and reopen the popover so it reloads the restored ready state.

## Prove manual Start through the production task path

The ready phase requires the owned task title in the accessible task summary.
It requires `START WORKDAY`, requires `END WORKDAY` to be absent, and presses the production Start control.

```sh
swift "$PROBE" --pid "$PID" --phase ready-start \
  --expected-task-title "$TASK_TITLE" --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-active "$DATABASE"
```

The fixture requires the same owned task to become active with exactly one open activity interval and no open pause.

## Prove stale End is rejected without mutation

Reopen the menu-bar popover and leave the active `END WORKDAY` control visible.
Inject the stale state only after the control is visible.

```sh
"$FIXTURE" inject-end-stale "$DATABASE"
swift "$PROBE" --pid "$PID" --phase stale-end \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-end-stale "$DATABASE"
"$FIXTURE" restore-active "$DATABASE"
```

The probe opens and confirms the stale destructive action.
It requires the honest `active task changed before confirmation` error and requires End to disappear after the fresh state loads.
The fixture requires the ordinary pause to remain and requires no `endingWorkday` mutation.

Close and reopen the popover so it reloads the restored active state.

## Prove confirmed End and ended state

The active phase requires Start to be absent.
It presses the real End control and the destructive confirmation.

```sh
swift "$PROBE" --pid "$PID" --phase active-end \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-ended "$DATABASE"
```

Reopen the popover after the confirmed mutation.
The ended phase requires the ended status.
It requires both invalid Start and End actions to be absent.
It requires the paused-task resume path to be labeled `START WORKDAY`.

```sh
swift "$PROBE" --pid "$PID" --phase ended \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
```

Every AX phase recursively scans identifiers, titles, descriptions, values, and help text.
The scan rejects raw fixture IDs, fixture notes, the database path, and the private QA root.

## Prove ended-state persistence after relaunch

Quit and relaunch the same installed bundle once more.
Open the menu-bar popover.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP" --args --qa-open-main
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main)"
PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
swift "$PROBE" --pid "$PID" --phase ended \
  --forbid "$DATABASE" --forbid "$PRIVATE_ROOT"
"$FIXTURE" assert-relaunch "$DATABASE"
```

The database must still contain the manual active policy, paused task, no open activity interval, and one open `endingWorkday` pause event.

## Cleanup and restoration proof

Quit the app before cleanup.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup "$DATABASE"
```

Cleanup removes all owned task, plan, execution, interval, pause, and backup rows.
Cleanup requires the original policy version to be active again.
Cleanup also requires the restored settings payload to equal the original versioned payload.

Do not mark ZC-044-004 fully usable unless every preflight, fixture assertion, stale-transition assertion, privacy scan, and AX phase passes against this one installed signed identity.
