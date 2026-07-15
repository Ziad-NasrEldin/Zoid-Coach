# ZC-056-006 signed paused day-state QA runbook

This runbook verifies one explicit paused workday state against an exact installed signed candidate.
The product candidate is `86943ed7c1615caa69bee669c4d79247bff3223b`.
The signed integration commit must contain that candidate.
Run every command from the repository containing the signed integration commit.

The fixture owns only the `qa-zc056006-paused-day-task` namespace.
It refuses to replace a foreign active task and removes only its own task, plan, state, and activity rows.
The AX probe requires the existing `today.day-state` identity, exact paused title and explanation, and stable `paused` accessibility value.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root.
Grant Accessibility permission to the terminal that runs the AX probe.
Close unrelated copies of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
DATABASE="/private/tmp/zc056006/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc056006-paused-day-state-fixture.sh"
PROBE="$PWD/Scripts/qa-zc056006-paused-day-state-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc056006-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
PRIVATE_ROOT="${DATABASE%/Application Support/Zoid 666/zoid-coach.sqlite}"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
PID=""

cleanup() {
  if test -n "${PID:-}" && kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  fi
  "$FIXTURE" cleanup --database "$DATABASE" || true
}
trap cleanup EXIT

"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test
```

The self-tests reject a planned-state fallback, a stale accessibility value, unsafe fixture cleanup, malformed identity, and incomplete runbook sequencing.

## Prepare the isolated paused day

Stop the app before mutating the isolated database.
Establish the supported post-onboarding QA state, then add one namespaced paused main objective with a closed tracked interval.

```sh
set -euo pipefail
"$READY_STATE" "$READY_MANIFEST" "$PRIVATE_ROOT" --replace
"$FIXTURE" seed-paused --database "$DATABASE"
"$FIXTURE" verify-paused --database "$DATABASE"
```

The fixture assertion proves there is no open activity interval and no active task.
The paused task remains part of today's visible plan and is ready to resume.

## Bind the signed app and prove the paused header

Launch the exact installed bundle through the supported QA foreground argument.
Bind its full build identity, executable, isolated database, foreground argument, and product ancestry before reading UI.

```sh
set -euo pipefail
open "$APP" --args --qa-open-main
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$PID"
swift "$PROBE" \
  --pid "$PID" \
  --expected-title "WORK PAUSED" \
  --expected-detail "A task is paused and ready to resume." \
  --expected-value paused
"$FIXTURE" verify-paused --database "$DATABASE"
```

The visible header must say `WORK PAUSED` rather than `PLANNED DAY`.
Its explanation must say that a task is paused and ready to resume.
Its stable AX value must be `paused` while the existing `today.day-state` identifier remains unchanged.

## Cleanup and acceptance

Stop the app and prove the owned namespace is empty.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
"$FIXTURE" cleanup --database "$DATABASE"
"$FIXTURE" verify-clean --database "$DATABASE"
trap - EXIT
```

Accept this ZC-056-006 slice only when the signed installed app passes the paused-state AX contract and fixture cleanup against one exact commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
