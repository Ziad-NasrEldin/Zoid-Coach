# ZC-062-002 Signed QA Runbook

## Qualification boundary

This run proves that one active technical task remains active and visible while only its isolated QA Screenwatch stream moves through fresh, stale, and missing states.
It never stops Screenwatch, modifies `~/screenwatch/days`, or mutates a non-QA database.
It does not qualify ZC-062-003, and it makes no claim about warning presentation or prompt suppression.

Run this only after the shared signed-runtime lane is available.
The preflight binds the signed app, helper, database, and Screenwatch source to one `/private/tmp/zoid-666-zc062002-*` root before any mutation.

## Bind the signed candidate

```sh
set -euo pipefail
export REPOSITORY="/Users/ziadnasreldin/Documents/GitHub/Zoid Coach"
export APP="/path/to/Zoid 666.app"
export EXPECTED_COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)"
export QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export SCREENWATCH_ROOT="$QA_ROOT/Screenwatch/days"
export BASELINE_ROOT="${QA_ROOT}-zc062002-baseline"
export INFO_PLIST="$APP/Contents/Info.plist"
AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 ))
export AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLISTS[1]")"
export AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
"$REPOSITORY/Scripts/qa-zc062002-signed-preflight.sh" "$APP" "$DATABASE" "$SCREENWATCH_ROOT" "$EXPECTED_COMMIT"
```

## Snapshot and prepare the isolated state

```sh
set -euo pipefail
"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
trap '"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" restore-root "$QA_ROOT" "$BASELINE_ROOT"' EXIT
"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" prepare "$DATABASE" "$SCREENWATCH_ROOT"
"$AGENT_EXECUTABLE" --once
```

The baseline helper pass must ingest the private observation, generate the Today snapshot, and leave the seeded technical task active with one open activity interval.

## Exercise the isolated stream transitions

```sh
set -euo pipefail
for PHASE in fresh stale missing; do
    "$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" disrupt "$PHASE" "$DATABASE" "$SCREENWATCH_ROOT"
    "$AGENT_EXECUTABLE" --once
    "$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" assert-result "$PHASE" "$DATABASE" "$SCREENWATCH_ROOT"
    APP_PID="$(pgrep -x "$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")" | head -1)"
    swift "$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift" --pid "$APP_PID" --phase "$PHASE"
done
```

Only the fixture-owned log inside `$SCREENWATCH_ROOT` is aged or removed.
The helper continues to run normally, so the proof exercises ingestion failure containment without disrupting any real process or file.

## Prove ordinary relaunch persistence

Perform an ordinary foreground app relaunch from the same signed bundle after the missing phase.
Do not rebuild, repackage, change roots, or reseed the database between termination and relaunch.

```sh
set -euo pipefail
APP_EXECUTABLE="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
for PID in ${(f)"$(pgrep -x "${APP_EXECUTABLE:t}" || true)"}; do
    if lsof -Fn -a -p "$PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        kill "$PID"
    fi
done
open -na "$APP" --args --qa-open-main
sleep 2
APP_PID="$(pgrep -x "${APP_EXECUTABLE:t}" | head -1)"
"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" assert-result missing "$DATABASE" "$SCREENWATCH_ROOT"
swift "$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift" --pid "$APP_PID" --phase missing
```

The database assertions prove durable task state and one open interval.
The accessibility probe proves the same active technical task remains visible after relaunch.

## Restore and close

```sh
set -euo pipefail
"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" restore-root "$QA_ROOT" "$BASELINE_ROOT"
trap - EXIT
"$REPOSITORY/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
```

Keep the command output as evidence for the three transitions, the ordinary relaunch, privacy checks, database integrity, and byte-exact restoration.
