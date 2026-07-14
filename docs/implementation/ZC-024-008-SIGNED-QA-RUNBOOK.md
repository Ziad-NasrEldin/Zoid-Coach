# ZC-024-008 signed QA runbook

This runbook verifies that the compact Zoid 666 menu-bar task card separates active-task elapsed time from Screenwatch-observed aligned time.

It must run against candidate `5accf2dac689797c39b7e409270fffddce1ad229` or a later candidate containing the same product and verifier commits.

It uses only an isolated signed-QA run root and never seeds a production database.

## Preconditions

Install the signed QA app with its normal installer before starting this runbook.

Grant Accessibility permission to the terminal process that runs the AX probe.

Set `LOCAL_DAY` to the day shown in the QA app under its configured policy time zone.

```bash
export REPO="/Users/ziadnasreldin/Documents/GitHub/Zoid Coach"
export QA_ROOT="${ZOID_COACH_QA_RUN_ROOT:-/private/tmp/zoid-666-signed-qa}"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :qa:appDisplayName' "$REPO/App/PackageIdentities.plist")"
export APP="$HOME/Applications/$DISPLAY_NAME E2E.app"
export EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
export EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
export AGENT_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :qa:launchAgentLabel' "$REPO/App/PackageIdentities.plist")"
export USER_DOMAIN="gui/$(id -u)"
export FIXTURE="$REPO/Scripts/qa-active-time-comparison-fixture.sh"
export PROBE="$REPO/Scripts/qa-active-time-comparison-ax-probe.swift"
export LOCAL_DAY="YYYY-MM-DD"
```

Confirm that `DATABASE`, `APP`, `FIXTURE`, and `PROBE` all exist before changing QA state.

## Seed the isolated QA database

Quit the signed QA app and stop the QA helper before seeding so neither process can race the fixture transaction.

```bash
pkill -f "$EXECUTABLE" 2>/dev/null || true
launchctl kill SIGTERM "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true
"$FIXTURE" seed --database "$DATABASE" --local-day "$LOCAL_DAY"
```

The fixture must print `MINIMUM_ELAPSED_MINUTES=14` and `EXPECTED_ALIGNED_MINUTES=5`.

The fixture refuses to replace a foreign active interval and refuses to overwrite occupied observation epochs.

## Verify the first signed menu-bar presentation

Start the QA helper, launch the installed app, and identify the process by its exact executable path.

```bash
launchctl kickstart -k "$USER_DOMAIN/$AGENT_LABEL"
open "$APP"
for _ in {1..40}; do
  PID="$(pgrep -x "$EXECUTABLE_NAME" | while read -r candidate; do lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE" && echo "$candidate" && break; done)"
  [[ -n "$PID" ]] && break
  sleep 0.2
done
[[ -n "${PID:-}" ]]
BASELINE_OUTPUT="$(swift "$PROBE" --pid "$PID" --minimum-elapsed 14 --expected-aligned 5)"
printf '%s\n' "$BASELINE_OUTPUT"
BASELINE_ELAPSED="$(printf '%s\n' "$BASELINE_OUTPUT" | awk -F= '/^ELAPSED_MINUTES=/{print $2}')"
[[ "$BASELINE_ELAPSED" =~ ^[0-9]+$ ]]
```

Capture a screenshot of the open compact card showing the separate elapsed and observed-aligned values plus the evidence disclosure.

The probe must find distinct `menu-bar.task.elapsed-time`, `menu-bar.task.aligned-time`, and `menu-bar.task.alignment-evidence` elements.

The elapsed value must be at least 14 minutes, the aligned value must be exactly 5 minutes, and the AX help must state that aligned evidence is a signal rather than proof of task match.

## Verify helper and app relaunch persistence

Terminate the installed app, restart the QA helper, relaunch the same installed bundle, and run the probe again.

```bash
kill "$PID"
launchctl kickstart -k "$USER_DOMAIN/$AGENT_LABEL"
open "$APP"
unset PID
for _ in {1..40}; do
  PID="$(pgrep -x "$EXECUTABLE_NAME" | while read -r candidate; do lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE" && echo "$candidate" && break; done)"
  [[ -n "$PID" ]] && break
  sleep 0.2
done
[[ -n "${PID:-}" ]]
swift "$PROBE" --pid "$PID" --minimum-elapsed "$BASELINE_ELAPSED" --expected-aligned 5
```

The second run proves that persisted task and observation rows restore through the real helper and that elapsed time never moves backward while aligned evidence stays fixed at five minutes.

## Clean only fixture-owned rows

Stop both QA processes, remove only the `qa-zc024008-*` rows, and verify the owned-row cleanup.

```bash
kill "$PID" 2>/dev/null || true
launchctl kill SIGTERM "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true
"$FIXTURE" cleanup --database "$DATABASE" --local-day "$LOCAL_DAY"
"$FIXTURE" verify-clean --database "$DATABASE" --local-day "$LOCAL_DAY"
```

Restart the helper and app once after cleanup so the normal product path replaces any derived Today snapshot that previously referenced the fixture task.

```bash
launchctl kickstart -k "$USER_DOMAIN/$AGENT_LABEL"
open "$APP"
sleep 2
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM today_snapshots WHERE CAST(payload AS TEXT) LIKE '%qa-zc024008-active-task%';")" == "0" ]]
```

Keep the two probe outputs, the screenshot, candidate hash, installed build identity, and cleanup output as the acceptance evidence.
