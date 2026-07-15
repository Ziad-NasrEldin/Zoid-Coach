# ZC-061-005 signed QA runbook

This runbook proves that uncertain browser activity cannot leave a strong gaming-drift intervention active.
The exact stacked parent is `0f82cbc3dd12252a3ed8f08a65210cfc72dcf6b2`.
The signed candidate must be a direct child of that parent and must contain only the six proof-tooling paths named by the static verifier.
The installed helper already provides the bounded production `--once` path used by this journey.
Stop immediately after any failed assertion.
Never classify the session as Research.

## Bind the signed candidate and isolated runtime

Install a clean signed QA candidate under a new isolated ZC-061-005 root.
Grant Accessibility permission to the terminal that runs the AX probe.
Close every unrelated copy of Zoid 666.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_CANDIDATE_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc061005-installed-proof"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
OS_STATE="$QA_ROOT/OS Fixtures/state.json"
BASELINE_ROOT="/private/tmp/zoid-666-zc061005-baseline"
FIXTURE="$PWD/Scripts/qa-zc061005-insufficient-evidence-fixture.sh"
PROBE="$PWD/Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc061005-signed-preflight.sh"
STATIC="$PWD/Scripts/verify-zc-061-005-insufficient-evidence-static.sh"
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
"$STATIC"
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$OS_STATE" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
AGENT_EXECUTABLE="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_EXECUTABLE=//p')"
AGENT_LABEL="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_LABEL=//p')"
test -x "$AGENT_EXECUTABLE"
test -n "$AGENT_LABEL"
```

The preflight binds the exact signed commit, direct parent, six-file scope, helper binary, database, OS fixture state, and embedded QA root.
It rejects abbreviated identities, a different lineage, a database outside the package root, or a helper that no longer exposes the existing bounded `--once` path.

## Stop processes and capture the byte baseline

Stop the launch agent and app before changing the isolated root.
The baseline snapshot is the authority for final restoration.

```sh
set -euo pipefail
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
for _ in {1..50}; do
  launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || break
  sleep 0.1
done
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc061005-target" "$BASELINE_ROOT.zc061005-manifest" "$BASELINE_ROOT.zc061005-restored-manifest"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
```

The fixture refuses any root outside `/private/tmp/zoid-666-zc061005-*`.
It records every regular file by SHA-256 and records every symlink target before the journey begins.

## Define the bounded installed-helper journey

Each phase starts from the same byte baseline.
The fixture seeds one active declared-technical task when the phase requires it, uncertain Safari tutorial activity, one unresolved strong `GAMING_DRIFT` episode, and either a scheduled or delivered matching fixture notification.
The raw title and URL deliberately contain private sentinels so the database and AX assertions can prove they never escape.

```sh
set -euo pipefail
find_app_pid() {
  local pid
  for _ in {1..50}; do
    for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
      if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        printf '%s\n' "$pid"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}

run_phase() {
  local phase="$1"
  local ax_phase="$2"
  local helper_runs="${3:-1}"
  "$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
  "$FIXTURE" prepare "$phase" "$DATABASE" "$OS_STATE"
  for _ in $(seq 1 "$helper_runs"); do
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
  done
  "$FIXTURE" assert-result "$phase" "$DATABASE" "$OS_STATE"
  open "$APP" --args --qa-open-main
  PID="$(find_app_pid)"
  swift "$PROBE" --pid "$PID" --phase "$ax_phase"
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
}
```

The helper invocation is the installed production binary, not a test double.
The database assertion requires the strong prompt to be dismissed with `resolution_origin = system` and `resolution_reason = screenwatch_evidence_invalid`.
The OS assertion requires every scheduled or delivered strong notification to be gone.
The AX assertion fails on strong coaching titles, raw private context, duplicate ambiguity actions, or any Research label.

## Prove qualifying uncertainty and idempotency

Run both notification states.
Then run the same helper twice against one qualifying session to prove that the ambiguity confirmation remains singular.

```sh
set -euo pipefail
run_phase qualifying-scheduled confirmation
run_phase qualifying-delivered confirmation
run_phase qualifying-scheduled confirmation 2
```

Each qualifying run must leave exactly one optional `AMBIGUOUS_ACTIVITY` confirmation.
Its visible copy must say that about ten minutes were observed in Safari and that application and duration cannot show intent.
It must expose exactly the three correction choices already owned by the production ambiguity flow.
It must contain no strong gaming-drift wording.

## Prove the ineligible boundaries

Run the below-threshold, stale, and no-active-task phases.
These phases must withdraw the seeded strong prompt while leaving no ambiguity confirmation.

```sh
set -euo pipefail
run_phase below-threshold absent
run_phase stale absent
run_phase no-active-task absent
```

The absence assertion is deliberately narrow.
It rejects both a strong gaming-drift intervention and the scoped ambiguity confirmation while allowing unrelated product content.

## Prove the already-handled boundary

Seed the exact ambiguity decision key before the helper runs.
The helper must not create a second episode.

```sh
set -euo pipefail
run_phase already-handled confirmation 2
```

The result assertion requires exactly one ambiguity episode after both helper invocations.
It also requires no unresolved `GAMING_DRIFT` episode and no matching fixture notification.

## Prove focused SQL and privacy failure behavior

Run only the focused journey test file.
This is not a release or broad package test.

```sh
set -euo pipefail
swift test --filter zc061005
```

The focused test replaces `behavior_records` with an invalid schema and requires both producers to throw without queuing a prompt.
It also proves below-threshold, stale, no-active-task, already-handled, duplicate suppression, exact system withdrawal metadata, and private title and URL exclusion.

## Restore the isolated root exactly

Stop all processes before restoration.
Restore the original root and compare its complete byte manifest.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
for _ in {1..50}; do
  launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || break
  sleep 0.1
done
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc061005-target" "$BASELINE_ROOT.zc061005-manifest" "$BASELINE_ROOT.zc061005-restored-manifest"
```

Do not update the scenario registry or tracker from an incomplete run.
Do not claim ZC-061-003 from this evidence.
This journey proves only that insufficient evidence suppresses strong drift, withdraws stale strong notifications, and allows at most one privacy-safe confirmation.
