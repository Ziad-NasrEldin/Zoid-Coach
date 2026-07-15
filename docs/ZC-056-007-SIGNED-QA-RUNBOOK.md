# ZC-056-007 signed menu visual QA runbook

This runbook verifies the Sumi-Ink Voice Controls disclosure in the general task menu against one exact installed signed commit.
Run every command from the repository containing that signed commit.

The check is read-only and does not mutate user data.
The AX probe opens the app's unique status item, verifies the collapsed contract, expands the disclosure, verifies its content, and collapses it again.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root.
Grant Accessibility permission to the terminal running the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc056007-menu-visual-fixture.sh"
PROBE="$PWD/Scripts/qa-zc056007-menu-visual-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc056007-signed-preflight.sh"
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

The self-tests reject stale accessibility values, inverted actions, unknown disclosure states, malformed identities, and incomplete runbook sequencing.

## Bind the signed status item

Launch the exact installed bundle through the supported background path.
Bind the package identity, executable PID, launch argument, signed commit, and source contract before reading UI.

```sh
set -euo pipefail
open "$APP" --args --background-schedule
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT" "$PID"
```

## Verify the disclosure sequence

The collapsed toggle must expose `Voice controls`, `Collapsed`, and `Expand voice controls`.
Its body must not exist in the accessibility tree while collapsed.
After expansion, the toggle must expose `Expanded` and `Collapse voice controls`, and the Voice Controls body must exist.
The final press must restore the collapsed contract and remove the body from the accessibility tree.

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

Accept this ZC-056-007 slice only when the installed signed app passes the full collapsed, expanded, and collapsed sequence against one exact commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
