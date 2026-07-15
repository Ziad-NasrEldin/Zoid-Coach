# ZC-062-003 Signed QA Runbook

## Qualification boundary

This run proves that a healthy, otherwise eligible strong prompt is visible before an isolated Screenwatch outage, then disappears when the same evidence becomes stale or missing.
The degraded state must show a user-visible Screenwatch warning, dismiss the prompt with the exact system reason, remove matching scheduled or delivered notifications, and preserve the baseline, plan, and active task.
The fixture refuses real Screenwatch, database, and OS-state paths.
Run this only after the shared signed-runtime lane is available.

## Bind the signed candidate

```sh
set -euo pipefail
export REPOSITORY="/Users/ziadnasreldin/Documents/GitHub/Zoid Coach"
export APP="/absolute/path/to/Zoid 666 QA E2E.app"
export EXPECTED_COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)"
export QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export SCREENWATCH_ROOT="$QA_ROOT/Screenwatch/days"
export OS_STATE="$QA_ROOT/OS Fixtures/state.json"
export BASELINE_ROOT="${QA_ROOT}-zc062003-baseline"
export FIXTURE="$REPOSITORY/Scripts/qa-zc062003-source-warning-suppression-fixture.sh"
export PROBE="$REPOSITORY/Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift"
OUTPUT="$("$REPOSITORY/Scripts/qa-zc062003-signed-preflight.sh" "$APP" "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE" "$EXPECTED_COMMIT")"
printf '%s\n' "$OUTPUT"
export AGENT_EXECUTABLE="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_EXECUTABLE=//p')"
export AGENT_LABEL="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_LABEL=//p')"
export APP_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
export APP_EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
```

The preflight requires a direct child of the ZC-062-002 stack tip and the exact six proof-tooling paths.
It binds the app, helper, database, Screenwatch source, and OS fixture to one `/private/tmp/zoid-666-zc062003-*` root.

## Capture the byte baseline

Stop only processes whose executable belongs to this signed QA bundle before changing its isolated root.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
for PID in ${(f)"$(pgrep -x "$APP_NAME" || true)"}; do
    if lsof -Fn -a -p "$PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        kill "$PID"
    fi
done
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc062003-target" "$BASELINE_ROOT.zc062003-manifest" "$BASELINE_ROOT.zc062003-restored"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
```

## Define the installed journey

Each phase starts from the same byte baseline.
The healthy control keeps seven complete baseline days, one priority plan entry, one active technical task, one open interval, ten current gaming observations, one strong prompt, and one matching notification.
To avoid a fifteen-minute wall-clock wait, the outage transition ages or removes only fixture-owned behavior rows derived from the isolated Screenwatch log.
It does not change the baseline, planned day, active-task state, open interval, real Screenwatch files, or real processes.

```sh
set -euo pipefail
find_app_pid() {
    local pid
    for _ in {1..50}; do
        for pid in ${(f)"$(pgrep -x "$APP_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
                printf '%s\n' "$pid"
                return 0
            fi
        done
        sleep 0.1
    done
    return 1
}

open_and_probe() {
    local phase="$1"
    open -na "$APP" --args --qa-open-main
    local pid
    pid="$(find_app_pid)"
    swift "$PROBE" --pid "$pid" --phase "$phase"
    kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
}

run_outage() {
    local notification_state="$1"
    local outage_phase="$2"
    "$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
    "$FIXTURE" prepare "$notification_state" "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
    "$FIXTURE" assert-healthy "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE"
    open_and_probe healthy
    "$FIXTURE" outage "$outage_phase" "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
    "$FIXTURE" assert-outage "$outage_phase" "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE"
    open_and_probe "$outage_phase"
    open_and_probe "$outage_phase"
    "$FIXTURE" assert-outage "$outage_phase" "$DATABASE" "$SCREENWATCH_ROOT" "$OS_STATE"
}
```

The second degraded launch is an ordinary foreground app relaunch against the unchanged isolated database.
Both degraded probes reject every strong prompt title and raw private sentinel.

## Prove stale and missing suppression

```sh
set -euo pipefail
run_outage scheduled stale
run_outage delivered missing
```

The stale journey proves a queued notification is removed.
The missing journey proves an already delivered notification is removed.
Both require `resolution_origin = system` and `resolution_reason = screenwatch_evidence_invalid` on the one original prompt.

## Prove focused boundaries

The fixture self-test covers no eligible baseline, an existing handled prompt, wrong or real roots, invalid SQL schema, private-data leakage, duplicate snapshots, relaunch persistence, and cleanup mismatch.

```sh
set -euo pipefail
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$REPOSITORY/Scripts/qa-zc062003-signed-preflight.sh" --self-test
"$REPOSITORY/Scripts/verify-zc-062-003-source-warning-suppression-static.sh"
```

## Restore exactly

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
for PID in ${(f)"$(pgrep -x "$APP_NAME" || true)"}; do
    if lsof -Fn -a -p "$PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        kill "$PID"
    fi
done
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
```

Do not update the scenario tracker or registry from an incomplete run.
Keep the healthy control, stale and missing warnings, exact prompt resolution, notification removal, relaunch, privacy, and byte-restoration output together as the evidence set.
