# ZC-013-002 Signed QA Runbook

This runbook proves that the installed Today dashboard reports coaching as observation-only, gentle active, accountability active, indefinitely paused, timed paused, or unavailable from persisted runtime sources.
It never treats a coaching pause as stopped task tracking or stopped activity observation.
It keeps generated evidence and every database mutation inside an isolated `/private/tmp/zoid-zc013002-*` root.
The signed bootstrap must establish complete onboarding, a valid policy store, exact isolated database ownership, an absent helper, and a Today UI with no accessible setup root before the first acceptance state.

## Bind and bootstrap the candidate

```zsh
set -euo pipefail

EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
QA_ROOT="/private/tmp/zoid-zc013002-runtime"
INSTALL_ROOT="/private/tmp/zoid-zc013002-install"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
APP_EXECUTABLE_NAME="ZoidCoachQA"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_EXECUTABLE_NAME="ZoidCoachAgentQA"
AGENT_LABEL="qa.ziadnasreldin.ZoidCoach.agent"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE="/private/tmp/zoid-zc013002-baseline"
EVIDENCE_ROOT="/private/tmp/zoid-zc013002-evidence/$EXPECTED_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc013002-coaching-status-fixture.sh"
PREFLIGHT="$PWD/Scripts/qa-zc013002-signed-preflight.sh"
BOOTSTRAP="$PWD/Scripts/qa-zc013002-signed-bootstrap.sh"

test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
"$PREFLIGHT" --self-test
swift test --filter CoachingStatePresentationTests
mkdir -p "$EVIDENCE_ROOT"
"$BOOTSTRAP" "$EXPECTED_SIGNED_COMMIT" "$QA_ROOT" "$INSTALL_ROOT" 2>&1 | tee "$EVIDENCE_ROOT/bootstrap.log"
```

The bootstrap uses `--qa-open-main` only for the pre-acceptance readiness proof.
Every scenario state and persistence check below uses an ordinary LaunchServices open with no presentation arguments.
The bootstrap exits with the exact QA app and helper stopped, the LaunchAgent absent, and the database quiescent.

## Preserve the exact ready state

```zsh
"$FIXTURE" assert-ready-root "$QA_ROOT" "$DATABASE" "$APP_EXECUTABLE_NAME" "$AGENT_EXECUTABLE_NAME" "$AGENT_LABEL"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE"
BASELINE_DIGEST="$("$FIXTURE" digest-root "$BASELINE")"
print -r -- "$BASELINE_DIGEST" | tee "$EVIDENCE_ROOT/baseline-digest.txt"
```

The snapshot contains only the isolated QA root.
Never point the fixture at the production database or any path outside the ZC-013-002 namespace.

## Ordinary-launch acceptance helper

```zsh
stop_exact_app() {
  local candidate
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    if test "$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)" = "$APP_EXECUTABLE"; then
      kill "$candidate"
      for _ in {1..40}; do kill -0 "$candidate" 2>/dev/null || break; sleep 0.1; done
      ! kill -0 "$candidate" 2>/dev/null
    fi
  done
}

wait_for_quiescence() {
  for _ in {1..40}; do
    lsof -t "$DATABASE" >/dev/null 2>&1 || return 0
    sleep 0.2
  done
  return 1
}

exact_app_pid() {
  local candidate executable
  for _ in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
      executable="$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
      test "$executable" = "$APP_EXECUTABLE" && { print -- "$candidate"; return 0; }
    done
    sleep 0.2
  done
  return 1
}

run_phase() {
  local phase="$1" pid
  stop_exact_app
  wait_for_quiescence
  ! pgrep -x "$AGENT_EXECUTABLE_NAME" >/dev/null 2>&1
  ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
  "$FIXTURE" prepare "$DATABASE" "$phase"
  open -na "$APP"
  pid="$(exact_app_pid)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$pid" "$phase" 2>&1 | tee "$EVIDENCE_ROOT/$phase.log"
}
```

The preflight binds each PID to the exact installed executable and to the isolated database as its only open Zoid database.
Its accessibility probe polls for the Today coaching card, verifies exact state copy, rejects contradictions, and rejects private paths, database names, URLs, application names, and fixture text.

## Exercise every authoritative state

```zsh
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

## Prove ordinary relaunch persistence

```zsh
stop_exact_app
wait_for_quiescence
open -na "$APP"
PID="$(exact_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$PID" paused-timed 2>&1 | tee "$EVIDENCE_ROOT/paused-timed-relaunch.log"
```

The ordinary relaunch must restore the same paused state and timed evidence from persisted policy and baseline data.
It must not fall back to observation-only while the authoritative pause is active.

## Prove fail-closed unavailability

```zsh
stop_exact_app
wait_for_quiescence
sqlite3 "$DATABASE" "ALTER TABLE baseline_observation_days RENAME TO baseline_observation_days_zc013002_unavailable;"
open -na "$APP"
PID="$(exact_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$PID" unavailable 2>&1 | tee "$EVIDENCE_ROOT/unavailable.log"
```

The missing authoritative baseline source must render coaching status as unavailable.
It must not guess that coaching is active or paused, and it must not show the Settings recovery hint.

## Cleanup, exact restoration, and manifest

```zsh
stop_exact_app
wait_for_quiescence
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE"
RESTORED_DIGEST="$("$FIXTURE" digest-root "$QA_ROOT")"
test "$RESTORED_DIGEST" = "$BASELINE_DIGEST"
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" "$PWD/Scripts/uninstall-signed-qa-runtime.sh" | tee "$EVIDENCE_ROOT/uninstall.log"
! pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1
! pgrep -x "$AGENT_EXECUTABLE_NAME" >/dev/null 2>&1
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
test ! -e "$APP"
test ! -e "$QA_ROOT"
rm -rf -- "$BASELINE" "$INSTALL_ROOT"
{
  print -r -- "expected_commit=$EXPECTED_SIGNED_COMMIT"
  print -r -- "baseline_digest=$BASELINE_DIGEST"
  print -r -- "restored_digest=$RESTORED_DIGEST"
  print -r -- "qa_app_absent=true"
  print -r -- "qa_helper_absent=true"
  git status --porcelain=v1 --untracked-files=all
} | tee "$EVIDENCE_ROOT/manifest.txt"
```

Do not mark ZC-013-002 fully implemented from static or signed-source proof alone.
Full status requires the complete installed six-state journey, ordinary relaunch persistence, privacy inspection, exact byte restoration, helper absence, uninstall, and a clean candidate manifest.
