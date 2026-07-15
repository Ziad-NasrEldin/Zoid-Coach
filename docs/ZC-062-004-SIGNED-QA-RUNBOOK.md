# ZC-062-004 Signed QA Runbook

## Qualification boundary

This run proves that one manually tracked local task remains active and singular while its isolated Screenwatch stream is fresh, stale, or missing.
The elapsed value must advance during the unavailable phases, survive the exact helper and an ordinary foreground app relaunch, and agree with the Today Pause and Complete controls.
The fixture never reads, ages, removes, or stops real Screenwatch data or processes.
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
export BASELINE_ROOT="${QA_ROOT}-zc062004-baseline"
export FIXTURE="$REPOSITORY/Scripts/qa-zc062004-manual-tracking-outage-fixture.sh"
export PROBE="$REPOSITORY/Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift"
OUTPUT="$("$REPOSITORY/Scripts/qa-zc062004-signed-preflight.sh" "$APP" "$DATABASE" "$SCREENWATCH_ROOT" "$EXPECTED_COMMIT")"
printf '%s\n' "$OUTPUT"
export AGENT_EXECUTABLE="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_EXECUTABLE=//p')"
export AGENT_LABEL="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_LABEL=//p')"
export APP_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
export APP_EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
```

The preflight binds a direct child of the ZC-062-003 stack tip, the exact six-file scope, the app and helper root, the canonical database, and the isolated Screenwatch source.

## Capture the byte baseline

Stop only the app and helper that belong to this signed QA bundle.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
for PID in ${(f)"$(pgrep -x "$APP_NAME" || true)"}; do
    if lsof -Fn -a -p "$PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        kill "$PID"
    fi
done
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc062004-target" "$BASELINE_ROOT.zc062004-manifest" "$BASELINE_ROOT.zc062004-restored"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
```

## Define the deterministic installed journey

The fixture uses a local task so an invalid Reminder bootstrap cannot remove the active work state.
To avoid a minute-long wall-clock wait, `advance` moves only the owned interval start boundary five minutes earlier while preserving its database identity.
The production helper must then calculate and persist the new elapsed value from that same open interval.
To avoid a fifteen-minute warning wait, stale and missing transitions age or remove only behavior rows derived from the fixture-owned Screenwatch log.

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
    local minimum_elapsed="$2"
    open -na "$APP" --args --qa-open-main
    local pid
    pid="$(find_app_pid)"
    swift "$PROBE" --pid "$pid" --phase "$phase" --minimum-elapsed "$minimum_elapsed"
    kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
}

run_phase() {
    local phase="$1"
    "$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
    "$FIXTURE" prepare "$DATABASE" "$SCREENWATCH_ROOT"
    "$FIXTURE" simulate-invalid-bootstrap "$DATABASE" "$SCREENWATCH_ROOT"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
    "$FIXTURE" assert-control "$DATABASE" "$SCREENWATCH_ROOT"
    open_and_probe fresh 14
    "$FIXTURE" source-state "$phase" "$DATABASE" "$SCREENWATCH_ROOT"
    "$FIXTURE" advance "$DATABASE" "$SCREENWATCH_ROOT"
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
    "$FIXTURE" assert-result "$phase" "$DATABASE" "$SCREENWATCH_ROOT"
    open_and_probe "$phase" 19
    open_and_probe "$phase" 19
    "$FIXTURE" assert-result "$phase" "$DATABASE" "$SCREENWATCH_ROOT"
}
```

The second 19-minute probe is an ordinary foreground app relaunch against the unchanged isolated database.
Both 19-minute checks require the same active task title, open-ended timing contract, Pause control, Complete control, and privacy-safe copy.

## Prove fresh control and unavailable sources

```sh
set -euo pipefail
run_phase fresh
run_phase stale
run_phase missing
```

Fresh is the positive source control.
Stale and missing are the isolated outage cases.
All three must retain one interval with the original ID and show at least nineteen tracked minutes after the deterministic advance.

## Prove focused failure boundaries

The self-tests reject an invalid Reminder bootstrap that removes the local task, duplicate or replaced intervals, elapsed freeze or reset, task loss, a stale source accepted as fresh, inconsistent controls, wrong roots, invalid SQL schema, private-data leakage, duplicate Today snapshots, relaunch loss, and cleanup mismatch.
The signed preflight separately rejects a wrong helper binary or runtime identity.

```sh
set -euo pipefail
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$REPOSITORY/Scripts/qa-zc062004-signed-preflight.sh" --self-test
"$REPOSITORY/Scripts/verify-zc-062-004-manual-tracking-outage-static.sh"
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
Keep the fresh control, two unavailable-source results, helper identities, interval IDs, elapsed snapshots, accessibility outputs, relaunch results, and byte-restoration output together.
