# ZC-013-002 Signed QA Runbook

This runbook proves that the installed Today dashboard reports coaching as gentle active, accountability active, observation-only, paused, or unavailable from the persisted runtime sources.
The reviewed candidate is bound directly to canonical base `b73a1c1c489eb02017d8609eab7a056296065819`.
It never treats a coaching pause as stopped task tracking or stopped activity observation.
It keeps generated evidence and every database mutation inside an isolated `/private/tmp/zoid-zc013002-*` root.

## Bind the candidate

```zsh
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
APP="/private/tmp/zoid-zc013002-install/Zoid 666.app"
QA_ROOT="/private/tmp/zoid-zc013002-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE="/private/tmp/zoid-zc013002-baseline"
FIXTURE="$PWD/Scripts/qa-zc013002-coaching-status-fixture.sh"
PREFLIGHT="$PWD/Scripts/qa-zc013002-signed-preflight.sh"

test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test -z "$(git status --porcelain)"
"$PREFLIGHT" --self-test
swift test --filter CoachingStatePresentationTests
```

Install the exact signed candidate into `APP` with `ZOID_COACH_QA_ROOT="$QA_ROOT"` using the repository signed-QA installer.
Grant Accessibility permission only to the terminal running the AX probe.
Keep the helper stopped while the fixture changes policy and baseline rows.

## Preserve the exact isolated state

```zsh
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE"
BASELINE_DIGEST="$("$FIXTURE" digest-root "$BASELINE")"
```

The snapshot contains only the isolated QA root.
Never point the fixture at the production database or any path outside its namespace.

## Exercise every authoritative state

For each phase, stop the foreground app and helper, prepare the state, launch the same signed app ordinarily, wait for Today, and bind its exact PID.

```zsh
run_phase() {
  local phase="$1"
  pkill -x "Zoid 666" 2>/dev/null || true
  "$FIXTURE" prepare "$DATABASE" "$phase"
  ZOID_COACH_QA_ROOT="$QA_ROOT" open -na "$APP"
  local pid
  pid="$(pgrep -x "Zoid 666" | tail -n1)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$pid" "$phase"
}

run_phase observation
run_phase gentle
run_phase accountability
run_phase paused-indefinite
run_phase paused-timed
```

Observation-only must say that baseline learning continues without behavior coaching prompts.
Gentle and accountability must both be active and must reflect the exact persisted coaching level.
Only paused states may show the Settings recovery hint.
The indefinite pause must say that it lasts until the user resumes coaching.
The timed pause must expose a pause end without including task titles, application names, captured text, URLs, screenshots, or database paths.
Every state must state that task tracking and activity observation continue according to their own settings.

## Prove ordinary relaunch

```zsh
pkill -x "Zoid 666" 2>/dev/null || true
ZOID_COACH_QA_ROOT="$QA_ROOT" open -na "$APP"
PID="$(pgrep -x "Zoid 666" | tail -n1)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$PID" paused-timed
```

The ordinary relaunch must restore the same paused state and timed evidence from persisted policy and baseline data.
It must not fall back to observation-only while the authoritative pause is active.

## Cleanup and byte restoration

```zsh
pkill -x "Zoid 666" 2>/dev/null || true
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE"
test "$("$FIXTURE" digest-root "$QA_ROOT")" = "$BASELINE_DIGEST"
rm -rf -- "$QA_ROOT" "$BASELINE" /private/tmp/zoid-zc013002-install
```

Do not mark ZC-013-002 fully implemented from static or signed-source proof alone.
Full status requires the complete installed five-state journey, ordinary relaunch, privacy inspection, and exact cleanup evidence.
