# ZC-059-001 signed incomplete priority-plan QA runbook

This runbook verifies that one exact installed signed app exposes an incomplete priority task before local plan approval, in the durable approval receipt, and after receipt restoration.
Run every command from the repository containing the exact signed integration commit.

The journey uses an isolated QA root with Calendar unavailable so approval remains local and requests no Calendar or Reminder mutations.
The release build and installed signed journey are pending until the constrained disk guard is lifted.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root.
Use the supported ready-state preparation flow with one incomplete reminder whose stable fixture identity is `qa-priority-task`, add that reminder to today's plan, make it the main objective, and assign an estimate.
Set the isolated Calendar permission fixture to denied so the approval action is `USE PLAN LOCALLY`.
Grant Accessibility permission to the terminal running the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
TASK_ID="qa-priority-task"
FIXTURE="$PWD/Scripts/qa-zc059001-priority-plan-fixture.sh"
PROBE="$PWD/Scripts/qa-zc059001-priority-plan-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc059001-signed-preflight.sh"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
PID=""

cleanup() {
  if test -n "${PID:-}" && kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  fi
}
trap cleanup EXIT

"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test
```

The self-tests distinguish review and receipt identities and reject complete, unknown, non-priority, malformed identity, and incomplete sequencing contracts.

## Bind the signed app

Launch the exact installed bundle through the supported QA foreground path.
Bind the package identity, executable PID, launch argument, signed commit, and source contract before reading UI.

```sh
set -euo pipefail
open "$APP" --args --qa-open-main
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT" "$PID"
```

## Verify review and durable receipt

Open Today and request plan approval after confirming that `qa-priority-task` remains incomplete and is the main objective.
The review must expose `PRIORITY · INCOMPLETE` with the `Priority task status` label and `Incomplete` value.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --surface review --task-id "$TASK_ID"
```

Choose `USE PLAN LOCALLY`.
The result must state that no Calendar or Reminder changes were requested, and the durable receipt must preserve the same explicit incomplete priority state.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --surface receipt --task-id "$TASK_ID"
```

## Verify restored receipt after relaunch

Stop and relaunch the exact app, then open the saved plan receipt from Today.
The restored receipt must expose the same stable identity and `Incomplete` value without replaying approval.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
open "$APP" --args --qa-open-main
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT" "$PID"
swift "$PROBE" --pid "$PID" --surface receipt --task-id "$TASK_ID"
```

## Cleanup and acceptance

Stop the exact app process after the probe passes.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
trap - EXIT
```

Accept this ZC-059-001 slice only when the installed signed app passes the review, local approval receipt, and restored receipt sequence against one exact commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
