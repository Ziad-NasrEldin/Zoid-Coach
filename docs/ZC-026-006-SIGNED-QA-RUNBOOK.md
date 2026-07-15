# ZC-026-006 signed QA runbook

This runbook verifies that an installed signed Zoid 666 review reports the actual persisted consequences of a correction.
The journey covers exact classification-minute movement, task alignment attachment, removal and unchanged state, review-statement change and unchanged state, combined impact, no-op suppression, persistence, ordinary relaunch, privacy, Accessibility, and byte-exact cleanup.
It uses one isolated QA database and never mutates the production database.

## Static gate and isolated installation

Run the complete journey from the clean candidate repository at the exact signed commit.

```zsh
set -euo pipefail

EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc026006-runtime"
INSTALL_ROOT="/private/tmp/zoid-666-zc026006-install"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BYTE_BACKUP="/private/tmp/zoid-666-zc026006-byte-backup-$EXPECTED_SIGNED_COMMIT"
EVIDENCE_ROOT="/private/tmp/zoid-666-zc026006-evidence/$EXPECTED_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc026006-correction-impact-fixture.sh"
PROBE="$PWD/Scripts/qa-zc026006-correction-impact-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc026006-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
SOURCE_DAY="$(date '+%Y-%m-%d')"
BASE_EPOCH="$(date -j -f '%Y-%m-%d %H:%M:%S' "$SOURCE_DAY 09:00:00" '+%s')"
export ZOID_666_QA_ROOT="$QA_ROOT"
export ZOID_666_QA_ZC026006_DAY="$SOURCE_DAY"
export ZOID_666_QA_ZC026006_BASE_EPOCH="$BASE_EPOCH"

test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test -z "$(git status --short)"
test "$(df -Pk /private/tmp | awk 'NR==2 {print $4}')" -ge 8388608
"$FIXTURE" self-test
"$PROBE" --self-test
swiftc -typecheck "$PROBE" -framework ApplicationServices -framework CoreGraphics
"$PREFLIGHT" --self-test
swift test --filter 'ZoidCoachAppTests.correction(Impact|Controller)'
mkdir -p "$EVIDENCE_ROOT"

PRODUCTION_DATABASE="$HOME/Library/Application Support/Zoid 666/zoid-coach.sqlite"
if test -f "$PRODUCTION_DATABASE"; then
  PRODUCTION_DATABASE_SHA_BEFORE="$(shasum -a 256 "$PRODUCTION_DATABASE" | awk '{print $1}')"
else
  PRODUCTION_DATABASE_SHA_BEFORE="ABSENT"
fi

ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
Scripts/install-signed-qa-runtime.sh 2>&1 | tee "$EVIDENCE_ROOT/install.log"
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
exec > >(tee -a "$EVIDENCE_ROOT/runbook.log") 2>&1
```

The free-space check requires at least 8 GiB before the one authorized signed package build.
Do not substitute a debug app, another commit, another QA root, or a presentation-only database.

Resolve exact packaged identities and define process helpers.

```zsh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
test "${#AGENT_PLISTS[@]}" = 1
AGENT_PLIST="${AGENT_PLISTS[1]}"
AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"

resolve_app_pid() {
  local candidate
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
      if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null \
        | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    sleep 0.2
  done
  return 1
}

stop_exact_app() {
  local candidate
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null \
      | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
      kill "$candidate"
      while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
    fi
  done
}

wait_for_database_quiescence() {
  local database="$1"
  for attempt in {1..60}; do
    lsof -t "$database" "$database-wal" "$database-shm" 2>/dev/null | grep -q . || return 0
    sleep 0.2
  done
  return 1
}

probe() {
  "$PROBE" --pid "$PID" --day "$SOURCE_DAY" --base-epoch "$BASE_EPOCH" --phase "$1"
}
```

## Establish the owned fixture and initial foreground window

Stop the packaged helper and app before creating the byte snapshot.
The snapshot records the exact database, WAL, and SHM presence, size, and SHA-256 before the fixture changes any byte.

```zsh
"$APP_EXECUTABLE" --qa-unregister-agent || true
stop_exact_app
rm -rf -- "$QA_ROOT" "$BYTE_BACKUP"
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
wait_for_database_quiescence "$DATABASE"
"$FIXTURE" snapshot "$DATABASE" "$BYTE_BACKUP"
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-before "$DATABASE"

open "$APP" --args --qa-open-main
FOREGROUND_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered)"
printf '%s\n' "$FOREGROUND_OUTPUT"
PID="$(printf '%s\n' "$FOREGROUND_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
probe before
screencapture -x "$EVIDENCE_ROOT/before.png"
```

The Before phase must show exactly 25 Gaming minutes, no task attachment, the gaming-dominant possible explanation, no correction-impact card, and a disabled unchanged Apply action.
The raw window-title and URL sentinels must be absent from the Accessibility tree.

## Combined correction and actual persisted deltas

Use only the visible Reviews controls to change Gaming to Work and attach the fixture task.

```zsh
probe apply-combined
"$FIXTURE" assert-combined "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/combined.png"
```

The accessible card must say that 25 minutes moved from Gaming to Work, task alignment attached for 25 minutes, and the review statement changed.
The assertion proves that the raw 25 Gaming observations remain unchanged while exactly one persisted correction supplies Work and the task attachment.
The card must not contain the application, task identifier, raw title, raw URL, or hypothesis text.

## Ordinary relaunch, persistence, and no-op suppression

Stop only the exact packaged app and reopen it through ordinary LaunchServices restoration.

```zsh
stop_exact_app
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
probe persisted-combined
"$FIXTURE" assert-combined "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/persisted-combined.png"
```

The ordinary relaunch must restore exactly 25 Work minutes, the task attachment, and the work-dominant review statement.
The transient impact card must be absent and the unchanged Apply action must be disabled, proving no-op suppression rather than replaying inferred copy.

## Alignment removal, reattachment, and unchanged alignment

Remove only the visible task attachment while retaining Work.

```zsh
probe apply-remove
"$FIXTURE" assert-removed "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/alignment-removed.png"
```

The card must report that task alignment was removed from 25 minutes and that the review statement did not change.
It must not claim that classification minutes moved.

Reattach the same task while retaining Work.

```zsh
probe apply-attach
"$FIXTURE" assert-attached "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/alignment-attached.png"
```

The card must report that task alignment attached for 25 minutes and that the review statement did not change.
It must not claim that classification minutes moved.

Change Work back to Gaming without changing the attached task.

```zsh
probe apply-unchanged-alignment
"$FIXTURE" assert-final "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/alignment-unchanged.png"
```

The card must report that 25 minutes moved from Work to Gaming, task alignment stayed unchanged at 25 minutes, and the review statement changed.
The fourth persisted correction must win without mutating any raw observation.

## Final ordinary relaunch and byte-exact cleanup

Prove the final persisted result and no-op suppression through a second ordinary relaunch.

```zsh
stop_exact_app
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
probe persisted-final
"$FIXTURE" assert-final "$DATABASE"
screencapture -x "$EVIDENCE_ROOT/persisted-final.png"
```

The final relaunch must restore 25 Gaming minutes and the task attachment, show the gaming-dominant statement, suppress the transient card, and disable the unchanged Apply action.

Unregister the packaged helper, stop the exact app, wait for all database handles to close, and restore the raw database files.

```zsh
"$APP_EXECUTABLE" --qa-unregister-agent
stop_exact_app
wait_for_database_quiescence "$DATABASE"
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
"$FIXTURE" restore "$DATABASE" "$BYTE_BACKUP"

if test -f "$PRODUCTION_DATABASE"; then
  test "$PRODUCTION_DATABASE_SHA_BEFORE" = "$(shasum -a 256 "$PRODUCTION_DATABASE" | awk '{print $1}')"
else
  test "$PRODUCTION_DATABASE_SHA_BEFORE" = "ABSENT"
fi

test "$QA_ROOT" = /private/tmp/zoid-666-zc026006-runtime
test "$INSTALL_ROOT" = /private/tmp/zoid-666-zc026006-install
rm -rf -- "$QA_ROOT" "$INSTALL_ROOT" "$BYTE_BACKUP"
! pgrep -f "$INSTALL_ROOT/Zoid 666 QA E2E.app" >/dev/null 2>&1
```

The fixture restore command rejects the wrong QA root, wrong database path, wrong ownership marker, missing backup data, and any SHA-256 or size mismatch.
Do not mark ZC-026-006 fully usable unless every static gate, exact package and process binding, seven Accessibility phases, five database assertions, two ordinary relaunches, privacy check, production-database hash check, helper cleanup, and byte restore pass against one installed signed commit.
