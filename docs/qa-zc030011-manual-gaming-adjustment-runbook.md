# ZC-030-011 signed QA completion runbook

This runbook verifies the combined product commit through the installed signed QA app and helper.
It uses only the isolated QA database, QA OS-fixture state, and verifier-owned rows.
It does not modify the production runtime or canonical tracker.

## Paths

```bash
export QA_ROOT=/private/tmp/zoid-666-signed-qa
export INSTALL_ROOT="$HOME/Applications"
export APP="$INSTALL_ROOT/Zoid 666 QA.app"
export APP_EXECUTABLE="$APP/Contents/MacOS/ZoidCoachQA"
export AGENT_EXECUTABLE="$APP/Contents/MacOS/ZoidCoachAgentQA"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export FIXTURE="$PWD/Scripts/qa-gaming-manual-adjustment-verifier.sh"
export AX_SOURCE="$PWD/Scripts/qa-gaming-manual-adjustment-ax-probe.swift"
export AX_PROBE="${TMPDIR:-/private/tmp}/qa-gaming-manual-adjustment-ax-probe"
swiftc "$AX_SOURCE" -o "$AX_PROBE"
```

## Persist a bounded grant and prove helper suppression

Prepare ten current gaming observations after the QA baseline has seven complete days.

```bash
"$FIXTURE" prepare-suppression "$DATABASE" "$QA_ROOT"
open "$APP"
export APP_PID="$(pgrep -x ZoidCoachQA | head -1)"
"$AX_PROBE" "$APP_PID" open
"$AX_PROBE" "$APP_PID" submit
"$FIXTURE" verify-grant "$DATABASE" "$QA_ROOT"
```

Stop the registered helper and invoke the same signed helper once with the QA-only production-service probe.

```bash
"$APP_EXECUTABLE" --qa-unregister-agent
ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
  "$AGENT_EXECUTABLE" --qa-gaming-drift-probe
"$FIXTURE" verify-probe "$DATABASE" "$QA_ROOT"
"$APP_EXECUTABLE" --qa-register-agent
```

The probe must report `suppressed:gamingIsUnlocked`, positive unlocked minutes, zero owned prompt rows, zero owned notification-delivery rows, and no owned QA OS notification.

## Reject a stale local day with zero writes

Open the form first so it captures the currently presented local day and time zone.
After the form is open, move the authoritative QA policy to a time zone whose current local day differs.

```bash
open "$APP"
export APP_PID="$(pgrep -x ZoidCoachQA | head -1)"
"$AX_PROBE" "$APP_PID" open
"$FIXTURE" authoritative-next-day "$DATABASE" "$QA_ROOT"
"$AX_PROBE" "$APP_PID" submit
"$AX_PROBE" "$APP_PID" assert-rejection
"$FIXTURE" verify-zero-write "$DATABASE" "$QA_ROOT"
"$FIXTURE" restore-policy "$DATABASE" "$QA_ROOT"
```

## Reject a changed time zone with zero writes

Refresh the app, then open a new form so it captures the restored authoritative policy.
After the form is open, move the authoritative QA policy to a different time zone that retains the same current local day.

```bash
pkill -x ZoidCoachQA || true
open "$APP"
export APP_PID="$(pgrep -x ZoidCoachQA | head -1)"
"$AX_PROBE" "$APP_PID" open
"$FIXTURE" authoritative-time-zone "$DATABASE" "$QA_ROOT"
"$AX_PROBE" "$APP_PID" submit
"$AX_PROBE" "$APP_PID" assert-rejection
"$FIXTURE" verify-zero-write "$DATABASE" "$QA_ROOT"
"$FIXTURE" restore-policy "$DATABASE" "$QA_ROOT"
```

## Disable saving when the ledger is unavailable

The ledger rename is confined to the stopped QA runtime and is restored immediately after the visible assertion.

```bash
"$APP_EXECUTABLE" --qa-unregister-agent
"$FIXTURE" ledger-unavailable "$DATABASE" "$QA_ROOT"
pkill -x ZoidCoachQA || true
open "$APP"
export APP_PID="$(pgrep -x ZoidCoachQA | head -1)"
"$AX_PROBE" "$APP_PID" assert-ledger-unavailable
"$FIXTURE" restore-ledger "$DATABASE" "$QA_ROOT"
"$FIXTURE" verify-zero-write "$DATABASE" "$QA_ROOT"
"$APP_EXECUTABLE" --qa-register-agent
```

## Cleanup

```bash
"$FIXTURE" cleanup "$DATABASE" "$QA_ROOT"
rm -f "$AX_PROBE"
```

Capture screenshots of the persisted adjustment history, each visible stale-state rejection, and the unavailable-ledger disclosure before cleanup.
