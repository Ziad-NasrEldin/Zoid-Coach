# ZC-010-007 signed end-to-end QA runbook

## Purpose

This runbook proves that an end user can end and review an explicitly unplanned day without Zoid 666 inventing planned outcomes.
It binds one exact signed QA app, one isolated QA database, the visible Today command, its confirmation, the existing Reviews destination, relaunch persistence, accessibility, privacy, exclusion states, and byte-for-byte cleanup.
Source presence or unit tests alone do not qualify the scenario as Full.

## Acceptance contract

Full acceptance requires all of these observations against one signed build identity.

- An explicitly unplanned day with no active task shows one enabled `END UNPLANNED DAY AND REVIEW` command on Today.
- The visible command and confirmation describe observed behavior and tracked task outcomes.
- The visible command and confirmation explicitly avoid invented planned commitments or missed-plan conclusions.
- Confirming the command reaches the existing daily Reviews surface.
- An ordinary app relaunch preserves the explicit unplanned state and exposes the same enabled command again.
- Planned, invitation, snoozed, dismissed, nil, and active-unplanned states never expose the new unplanned-day review container.
- The active-unplanned state retains the existing enabled end-workday command so timer-stopping behavior keeps precedence.
- Private fixture title and URL sentinels never appear through the accessibility tree.
- The isolated current-day snapshot is restored byte-for-byte after verification.

## Preconditions

Use a signed QA package whose commit descends from current canonical base `a002610ae3d8db3f1e88cfd8463a4ce103531e83`, contains refreshed product candidate `65fa67324db313281fe2db0562a97930aec1a93c`, and contains this verifier tooling.
The refreshed product candidate preserves source candidate `6fa4bcb029a13eb951806a2d5a4f073d2f11c58e` with stable patch ID `0342dd335be54243490b07e9eb978e33e7b3d4c9`.
The QA package must embed a dedicated QA root that is not used by another scenario.
Grant Accessibility permission to the terminal that runs the Swift probe.
Do not perform this journey while another lane owns the installed QA runtime.
Stop the app before every fixture write or restore.
Do not use a production database.

## Bind the exact signed app

Set the paths after installing the dedicated signed QA package.

```sh
set -euo pipefail
REPO="/absolute/path/to/Zoid Coach"
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="$(plutil -extract ZoidCoachGitCommit raw -o - "$APP/Contents/Info.plist")"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BACKUP_ROOT="$(mktemp -d /private/tmp/zoid-666-zc010007-backup.XXXXXX)"
BACKUP="$BACKUP_ROOT/today-snapshot.tsv"
FIXTURE="$REPO/Scripts/qa-zc010007-unplanned-review-fixture.sh"
PROBE="$REPO/Scripts/qa-zc010007-unplanned-review-ax-probe.swift"
PREFLIGHT="$REPO/Scripts/qa-zc010007-signed-preflight.sh"
READY_STATE="$REPO/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$REPO/Scripts/fixtures/qa-ready-state.example.json"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"
stop_exact_qa_app() {
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    candidate_executable="$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    if test "$candidate_executable" = "$APP_EXECUTABLE"; then
      kill "$candidate"
      for _ in $(seq 1 50); do
        ! kill -0 "$candidate" 2>/dev/null && break
        sleep 0.2
      done
      ! kill -0 "$candidate" 2>/dev/null
    fi
  done
}
```

Launch the foreground main window and bind its process to the signed app and isolated database.

```sh
set -euo pipefail
stop_exact_qa_app
open "$APP" --args --qa-open-main
for _ in $(seq 1 50); do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | tail -1 || true)"
  [[ -n "$PID" ]] && lsof -Fn -a -p "$PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && break
  sleep 0.2
done
[[ -n "${PID:-}" ]]
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main --expected-app-pid "$PID"
```

## Capture the byte baseline

Quit the app before backing up the current-day snapshot.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
for _ in $(seq 1 50); do
  ! kill -0 "$PID" 2>/dev/null && break
  sleep 0.2
done
! kill -0 "$PID" 2>/dev/null
"$APP_EXECUTABLE" --qa-unregister-agent
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
"$APP_EXECUTABLE" --qa-register-agent
"$APP_EXECUTABLE" --qa-unregister-agent
for _ in $(seq 1 50); do
  ! pgrep -x ZoidCoachAgentQA >/dev/null && break
  sleep 0.2
done
! pgrep -x ZoidCoachAgentQA >/dev/null
! launchctl print "gui/$(id -u)/qa.ziadnasreldin.ZoidCoach.agent" >/dev/null 2>&1
stop_exact_qa_app
"$FIXTURE" prepare unused "$DATABASE" "$BACKUP"
```

The supported ready-state fixture is required because a fresh isolated package intentionally opens at onboarding.
It establishes the normal post-onboarding Today surface before the scenario-specific current-day snapshot is written.
The signed helper registration, XPC timeline, and heartbeat are proven first, then the exact QA helper remains unregistered throughout every synthetic snapshot phase.

## Prove the complete usable journey

Write the explicit unplanned state only while the app is stopped, then relaunch the same signed app.

```sh
set -euo pipefail
"$FIXTURE" set unplanned "$DATABASE" "$BACKUP"
stop_exact_qa_app
open "$APP" --args --qa-open-main
for _ in $(seq 1 50); do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | tail -1 || true)"
  [[ -n "$PID" ]] && break
  sleep 0.2
done
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase unplanned
swift "$PROBE" --pid "$PID" --phase open-confirmation
swift "$PROBE" --pid "$PID" --phase confirm-reviews
```

Record a screenshot of the enabled Today command, the factual confirmation, and the daily Reviews destination.
Reject the journey if any visible copy implies that an unplanned day had commitments or missed planned outcomes.

## Prove ordinary relaunch persistence

An ordinary app relaunch must not require rewriting the fixture.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit"
for _ in $(seq 1 50); do
  ! kill -0 "$PID" 2>/dev/null && break
  sleep 0.2
done
stop_exact_qa_app
open "$APP" --args --qa-open-main
for _ in $(seq 1 50); do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | tail -1 || true)"
  [[ -n "$PID" ]] && break
  sleep 0.2
done
"$FIXTURE" assert unplanned "$DATABASE" "$BACKUP"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase unplanned
```

## Prove every exclusion

Run the exact matrix `planned invitation snoozed dismissed nil active-unplanned` from the original byte baseline.
Each fixture mutation occurs only while the app is stopped.

```sh
set -euo pipefail
for STATE in planned invitation snoozed dismissed nil; do
  osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
  for _ in $(seq 1 50); do
    ! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null && break
    sleep 0.2
  done
  "$FIXTURE" set "$STATE" "$DATABASE" "$BACKUP"
  stop_exact_qa_app
  open "$APP" --args --qa-open-main
  for _ in $(seq 1 50); do
    PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | tail -1 || true)"
    [[ -n "$PID" ]] && break
    sleep 0.2
  done
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main --expected-app-pid "$PID"
  swift "$PROBE" --pid "$PID" --phase absent
done
```

The active-unplanned boundary must show the old active-task command and must not show the new unplanned-day container.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
for _ in $(seq 1 50); do
  ! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null && break
  sleep 0.2
done
"$FIXTURE" set active-unplanned "$DATABASE" "$BACKUP"
stop_exact_qa_app
open "$APP" --args --qa-open-main
for _ in $(seq 1 50); do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | tail -1 || true)"
  [[ -n "$PID" ]] && break
  sleep 0.2
done
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-qa-open-main --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase active-precedence
```

## Cleanup and restoration proof

Quit the app before restoring the baseline.
Cleanup is incomplete unless the fixture reports exact payload and timestamp restoration and removes the external backup.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
for _ in $(seq 1 50); do
  ! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null && break
  sleep 0.2
done
"$FIXTURE" cleanup unused "$DATABASE" "$BACKUP"
rmdir "$BACKUP_ROOT"
```

## Evidence record

Record the signed commit, package verification output, app path, app PID for each phase, isolated database path, fixture outputs, accessibility probe outputs, screenshots, ordinary relaunch observation, exclusion matrix, privacy result, and cleanup result.
Only then may orchestration evaluate ZC-010-007 for Full status.
