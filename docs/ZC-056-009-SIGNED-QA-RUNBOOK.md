# ZC-056-009 signed gaming settings QA runbook

This runbook verifies that the gaming allowance remains visible without letting advanced policy tuning dominate Settings.
Run every command from the repository containing the exact signed integration commit.

The check is read-only and does not save policy changes.
The AX probe opens Settings through the app's menu-bar action and verifies a collapsed, expanded, and collapsed sequence.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root.
Grant Accessibility permission to the terminal running the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc056009-gaming-settings-fixture.sh"
PROBE="$PWD/Scripts/qa-zc056009-gaming-settings-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc056009-signed-preflight.sh"
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

The self-tests reject stale disclosure states, mixed control groups, malformed identities, and incomplete runbook sequencing.

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

## Verify progressive disclosure

The collapsed settings state must keep budget enablement, base allowance, priority reward, and intentional override visible.
Work-hours maximum, prompt cap, cooldown, and grace controls must not exist in the accessibility tree while collapsed.
After expansion, every advanced control must become available while the four core decisions remain visible.
The final press must hide advanced controls again without changing any setting.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID"
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

Accept this ZC-056-009 slice only when the installed signed app passes the complete disclosure sequence against one exact commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
