# ZC-062-001 signed QA runbook

This runbook proves one durable approved planned day with Reminders, fresh Screenwatch ingestion, a fresh agent heartbeat, and a healthy canonical database in the same signed user-visible state.
The signed candidate must be a direct child of `0c6e749bdbafc732779ff1bd85a2829b8ea248e1` and contain exactly the six proof-tooling paths enforced by the static verifier.
The same state must survive one bounded installed-helper refresh and an ordinary foreground app relaunch.
Stop on the first failed assertion.

## Prepare the isolated signed runtime

Use a new signed QA root under `/private/tmp/zoid-666-zc062001-*`.
Close unrelated copies of Zoid 666 and grant Accessibility permission to the terminal running the probe.
Do not run this journey while another lane owns the installed runtime.

```sh
set -euo pipefail
REPO="/absolute/path/to/Zoid Coach"
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_CANDIDATE_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc062001-installed-proof"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
SCREENWATCH_ROOT="$QA_ROOT/Screenwatch/days"
BASELINE_ROOT="/private/tmp/zoid-666-zc062001-baseline"
FIXTURE="$REPO/Scripts/qa-zc062001-healthy-workday-fixture.sh"
PROBE="$REPO/Scripts/qa-zc062001-healthy-workday-ax-probe.swift"
PREFLIGHT="$REPO/Scripts/qa-zc062001-signed-preflight.sh"
STATIC="$REPO/Scripts/verify-zc-062-001-healthy-workday-static.sh"
READY_STATE="$REPO/Scripts/prepare-qa-ready-state.py"
READY_TEMPLATE="$REPO/Scripts/fixtures/qa-ready-state.example.json"
READY_MANIFEST="$(mktemp /private/tmp/zoid-666-zc062001-ready.XXXXXX.json)"
jq '.screenwatch.rebaseToNow=true | .screenwatch.timeZoneIdentifier="Africa/Cairo"' "$READY_TEMPLATE" > "$READY_MANIFEST"
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
```

The ready-state materializer rebases Screenwatch into the current local day and grants only isolated QA fixture permissions.
It does not touch production Reminders, Calendar, notifications, Screenwatch, or the production database.

## Bootstrap and bind the exact package

Launch the signed app once to create the migrated isolated database, then stop it and bind every owned path.

```sh
set -euo pipefail
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"
open -n "$APP" --args --qa-open-main
for _ in {1..50}; do
  test -f "$DATABASE" && break
  sleep 0.1
done
test -f "$DATABASE"
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
for _ in {1..50}; do
  ! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null && break
  sleep 0.1
done
"$APP_EXECUTABLE" --qa-unregister-agent || true
OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$SCREENWATCH_ROOT" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
AGENT_EXECUTABLE="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_EXECUTABLE=//p')"
test -x "$AGENT_EXECUTABLE"
```

The preflight rejects a wrong database, Screenwatch root, helper executable, QA root, lineage, package identity, or commit scope.

## Capture the byte baseline

The stopped isolated root is the authority for final restoration.

```sh
set -euo pipefail
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc062001-target" "$BASELINE_ROOT.zc062001-manifest" "$BASELINE_ROOT.zc062001-restored-manifest"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
```

The fixture records every regular file hash and symlink target and refuses unsafe root namespaces.

## Run one bounded helper refresh

Prepare one durable local plan entry and one fresh private Screenwatch observation while the app and launch agent are stopped.
Then invoke the exact installed helper once.

```sh
set -euo pipefail
"$FIXTURE" prepare "$DATABASE" "$SCREENWATCH_ROOT"
env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
"$FIXTURE" assert-result "$DATABASE" "$SCREENWATCH_ROOT"
```

The result must contain one planned task, one canonical current-day snapshot, one matching ingested Screenwatch epoch, and one agent heartbeat no older than 240 seconds.
Reminders must be available, Screenwatch must be current, the agent must be running, SQLite integrity must be `ok`, and no stale or limited fallback may remain.
Private raw title and URL sentinels may remain only in the owned raw Screenwatch log and behavior record.

## Prove the five privacy-safe rows

Open the signed app without starting a persistent helper.
The probe visits Today and Source Health and emits exactly five evidence rows.

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
open -n "$APP" --args --qa-open-main
PID="$(find_app_pid)"
swift "$PROBE" --pid "$PID"
```

The five rows are Planned day, Apple Reminders Healthy, Screenwatch Current and ingested, Zoid 666 Agent Running, and Local database Healthy.
The probe rejects stale, limited, missing, raw private title, and raw private URL evidence.

## Prove ordinary relaunch persistence

Quit and reopen the same signed app without rewriting the fixture or rerunning the helper.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit"
for _ in {1..50}; do
  ! kill -0 "$PID" 2>/dev/null && break
  sleep 0.1
done
! kill -0 "$PID" 2>/dev/null
open -n "$APP" --args --qa-open-main
PID="$(find_app_pid)"
"$FIXTURE" assert-result "$DATABASE" "$SCREENWATCH_ROOT"
swift "$PROBE" --pid "$PID"
```

The second probe must emit the same five evidence rows.
Any missing plan, duplicate snapshot, stale source, missing ingestion, lost heartbeat, unhealthy database, or privacy leak fails closed.

## Run the local negative self-tests

These are proof-tooling self-tests only and do not build, package, install, or launch the product.

```sh
set -euo pipefail
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
"$STATIC"
```

The self-tests cover one-source unhealthy, stale and missing evidence, wrong database and helper ownership, relaunch plan loss, duplicate snapshots, SQL failure, privacy leakage, cleanup mismatch, unsafe roots, and byte restoration.

## Restore the root exactly

Stop the foreground app and helper before restoration.

```sh
set -euo pipefail
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" || true
for _ in {1..50}; do
  ! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null && break
  sleep 0.1
done
"$APP_EXECUTABLE" --qa-unregister-agent || true
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc062001-target" "$BASELINE_ROOT.zc062001-manifest" "$BASELINE_ROOT.zc062001-restored-manifest"
rm -f -- "$READY_MANIFEST"
```

Do not update the scenario registry or tracker from an incomplete run.
Only the complete signed helper, database, AX, relaunch, privacy, freshness, and restoration sequence can qualify ZC-062-001.
