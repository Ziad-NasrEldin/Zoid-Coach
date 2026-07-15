# ZC-060-004 signed intentional cooldown QA runbook

This runbook verifies that choosing Continue intentionally closes one gaming-drift prompt and exposes factual configured-window feedback through the existing Today action-status surface.
Run every command from the repository containing the exact signed integration commit.

The status does not invent a countdown because the prompt episode does not carry the exact configured duration.
Focused service tests remain the authoritative deterministic proof for suppression, early aligned-work termination, and the configured expiry boundary.
The release build and installed journey are pending until the constrained disk guard is lifted.

## Preconditions and variables

Install a clean signed QA package under an isolated QA root.
Use a product-created `GAMING_DRIFT` prompt with stable prompt identity `PROMPT_ID`; do not insert an unsupported prompt row directly into the database.
The prompt must offer Continue intentionally and the isolated policy must preserve its known configured override duration.
Grant Accessibility permission to the terminal running the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
PROMPT_ID="PRODUCT_CREATED_GAMING_DRIFT_PROMPT_ID"
FIXTURE="$PWD/Scripts/qa-zc060004-intentional-cooldown-fixture.sh"
PROBE="$PWD/Scripts/qa-zc060004-intentional-cooldown-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc060004-signed-preflight.sh"
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

The self-tests reject invented countdowns, incomplete feedback, unknown states, malformed identities, and runbooks that omit deterministic override boundaries.

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

## Close the prompt and verify visible feedback

Open Today with the exact product-created gaming-drift prompt visible.
The probe presses Continue intentionally, requires the waiting row to disappear, and requires the existing action-status surface to expose the factual configured-window message.

```sh
set -euo pipefail
swift "$PROBE" --pid "$PID" --prompt-id "$PROMPT_ID"
```

The message must say that equivalent gaming prompts are paused for the configured override window and that returning to aligned work ends the pause early.
It must not claim a remaining minute count that the episode cannot supply.

## Verify deterministic suppression and boundaries

Run the narrow service tests from the exact source commit when disk capacity permits focused debug testing.
The first test proves suppression throughout the configured window and new prompt eligibility at expiry, including restart.
The second proves that less than two aligned minutes keeps the override active and exactly two aligned minutes ends it early.

```sh
set -euo pipefail
swift test --filter intentionalGamingOverrideUsesConfiguredDurationAcrossRestart
swift test --filter intentionalGamingOverrideRequiresTwoMinutesOfWorkBeforeEarlyReprompt
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

Accept this ZC-060-004 slice only when the installed signed app closes one exact gaming prompt with factual visible feedback and the focused service boundaries pass against the same source commit.
Do not infer installed-app acceptance from focused tests or static checks alone.
