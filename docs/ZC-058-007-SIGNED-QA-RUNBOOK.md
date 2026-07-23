# ZC-058-007 signed alignment evidence boundary QA runbook

This runbook verifies that Behavior Evidence explains when weak evidence holds back strong drift coaching.
Run every command from the repository containing the exact signed integration commit.

The check is read-only and does not change coaching policy or evidence.
The AX probe opens Behavior Evidence, validates the state shown by the installed app, and closes the sheet.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root with a supported ready-state fixture.
Grant Accessibility permission to the terminal running the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc058007-alignment-boundary-fixture.sh"
PROBE="$PWD/Scripts/qa-zc058007-alignment-boundary-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc058007-signed-preflight.sh"
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

The self-tests distinguish limited, unknown, and current evidence and reject stale labels, missing policy context, malformed identities, and incomplete sequencing.

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

## Verify the evidence boundary

Open Behavior Evidence through the installed Today surface and validate the exact state available in the isolated fixture.
Limited coverage must explain that stale or missing activity is not strong drift evidence and point to Source Health.
Unknown evidence must remain outside work, gaming, and distraction rather than being guessed.
Current evidence must explain that classification and app names do not prove intent or active-task alignment.
Every state must retain the factual threshold context for strong gaming coaching.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID"
```

The probe prints `BOUNDARY_VALUE` as `Limited evidence`, `Unknown evidence excluded`, or `Current evidence boundary`.

## Cleanup and acceptance

Stop the exact app process after the probe passes.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
trap - EXIT
```

Accept this ZC-058-007 slice only when the installed signed app exposes one truthful evidence-boundary state against one exact commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
