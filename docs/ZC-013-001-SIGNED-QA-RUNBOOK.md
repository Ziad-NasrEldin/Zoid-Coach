# ZC-013-001 signed QA runbook

This runbook verifies that Today always exposes the current date and one explicit day state.
The signed build must be the exact expected commit on the reviewed canonical-base lineage.
The lineage preflight verifies the replayed product patches by stable patch ID and final blob content instead of relying on pre-reassembly commit ancestry.

The journey uses an isolated QA root and install root.
The fixture backs up only the current-day Today snapshot to an external runtime file, drives the UI through the real persisted snapshot boundary, and restores the original payload byte-for-byte during cleanup.
No evidence is written inside the repository before package cleanliness verification.

## Preflight and installation

Run the full journey from one shell rooted at the candidate repository.

```zsh
set -euo pipefail

EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc013001-runtime"
INSTALL_ROOT="/private/tmp/zoid-666-zc013001-install"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BACKUP="$QA_ROOT/zc013001-original-snapshot.tsv"
EVIDENCE="/private/tmp/zoid-666-zc013001-evidence/$EXPECTED_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc013001-day-state-fixture.sh"
PROBE="$PWD/Scripts/qa-zc013001-day-state-ax-probe.swift"
LINEAGE_PREFLIGHT="$PWD/Scripts/qa-zc013001-lineage-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
FIXTURE_PREPARED=false

"$LINEAGE_PREFLIGHT" --expected-commit "$EXPECTED_SIGNED_COMMIT"
"$FIXTURE" self-test
swift "$PROBE" --self-test
Scripts/qa-zc013001-runbook-self-test.sh
mkdir -p "$EVIDENCE"

ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
Scripts/install-signed-qa-runtime.sh 2>&1 | tee "$EVIDENCE/install.log"

ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
```

The evidence directory is external to the repository, so installer logs cannot invalidate the clean-package gate.

Resolve the exact packaged identities and establish the supported ready state.

```zsh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
# BEGIN RUNBOOK SELF-TEST: launch-agent-array
AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
test "${#AGENT_PLISTS[@]}" = 1
AGENT_PLIST="${AGENT_PLISTS[1]}"
# END RUNBOOK SELF-TEST: launch-agent-array
AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"

"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" || true
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
"$APP_EXECUTABLE" --qa-register-agent

for attempt in {1..80}; do
  test -f "$DATABASE" && \
    test "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM today_snapshots WHERE day_key = date('now', 'localtime') AND json_valid(CAST(payload AS TEXT));")" = 1 && break
  sleep 0.25
done
test "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM today_snapshots WHERE day_key = date('now', 'localtime') AND json_valid(CAST(payload AS TEXT));")" = 1
```

The initial foreground-only argument is used solely to establish the post-onboarding baseline snapshot.
Every acceptance relaunch below is an ordinary LaunchServices open.

Stop the helper and app before fixture ownership begins.

```zsh
"$APP_EXECUTABLE" --qa-unregister-agent
pkill -x "$APP_EXECUTABLE_NAME" || true
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
"$FIXTURE" prepare --database "$DATABASE" --backup "$BACKUP"
FIXTURE_PREPARED=true
```

The accessibility probe resolves the installed bundle's preferred localization and formats the current instant with that locale, `Calendar.current`, `TimeZone.current`, and the product's exact weekday, wide-month, and day fields.
This keeps month-first and day-first localizations exact without accepting a partial or reordered date.

## Ordinary-launch acceptance helper

Use this helper in the same shell for every state.
It binds the exact installed executable, rejects presentation-only launch arguments, proves that the app opened the isolated database, and runs the accessibility and privacy assertions.

```zsh
stop_exact_app() {
  local candidate
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
      kill "$candidate"
      while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
    fi
  done
}

# BEGIN RUNBOOK SELF-TEST: database-quiescence
database_has_open_process() {
  lsof -t "$1" 2>/dev/null | grep -q .
}

wait_for_database_quiescence() {
  local database="$1"
  local attempts="${2:-40}"
  local delay_seconds="${3:-0.2}"

  for (( attempt = 1; attempt <= attempts; attempt += 1 )); do
    database_has_open_process "$database" || return 0
    sleep "$delay_seconds"
  done
  return 1
}
# END RUNBOOK SELF-TEST: database-quiescence

# BEGIN RUNBOOK SELF-TEST: ordinary-launch-command
ordinary_launch_command_is_valid() {
  local command_line="$1"
  [[ "$command_line" != *--qa-open-main* && "$command_line" != *--background-schedule* ]]
}
# END RUNBOOK SELF-TEST: ordinary-launch-command

# BEGIN RUNBOOK SELF-TEST: database-readiness
process_is_alive() {
  kill -0 "$1" 2>/dev/null
}

open_zoid_databases() {
  lsof -Fn -a -p "$1" 2>/dev/null \
    | sed -n 's/^n//p' \
    | grep -E '/zoid-coach\.sqlite$' \
    | sort -u \
    || true
}

wait_for_exact_database() {
  local pid="$1"
  local expected_database="$2"
  local attempts="${3:-40}"
  local delay_seconds="${4:-0.2}"
  local open_databases

  for (( attempt = 1; attempt <= attempts; attempt += 1 )); do
    process_is_alive "$pid" || return 1
    open_databases="$(open_zoid_databases "$pid")"
    if [[ "$open_databases" == "$expected_database" ]]; then
      return 0
    fi
    [[ -z "$open_databases" ]] || return 1
    sleep "$delay_seconds"
  done
  return 1
}
# END RUNBOOK SELF-TEST: database-readiness

verify_state() {
  local fixture_state="$1"
  local expected_state="$2"
  local candidate pid command_line
  stop_exact_app
  wait_for_database_quiescence "$DATABASE"
  "$FIXTURE" set "$fixture_state" --database "$DATABASE" --backup "$BACKUP"
  open "$APP"
  pid=""
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
      if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        pid="$candidate"
        break
      fi
    done
    test -n "$pid" && break
    sleep 0.2
  done
  test -n "$pid"
  command_line="$(ps -p "$pid" -o command=)"
  ordinary_launch_command_is_valid "$command_line"
  wait_for_exact_database "$pid" "$DATABASE"
  swift "$PROBE" \
    --pid "$pid" \
    --app-bundle "$APP" \
    --expected-state "$expected_state" \
    --reject "qa-zc013001-private-window-title" \
    --reject "qa-zc013001-private.invalid"
  "$FIXTURE" assert "$fixture_state" --database "$DATABASE" --backup "$BACKUP"
}

# BEGIN RUNBOOK SELF-TEST: failure-cleanup
cleanup_on_exit() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e
  stop_exact_app
  if test -f "$DATABASE"; then
    wait_for_database_quiescence "$DATABASE"
  fi
  if test "$FIXTURE_PREPARED" = true && test -f "$BACKUP" && test -f "$DATABASE"; then
    "$FIXTURE" cleanup --database "$DATABASE" --backup "$BACKUP" \
      2>&1 | tee "$EVIDENCE/failure-cleanup.log"
  fi
  if test -x "$APP_EXECUTABLE"; then
    "$APP_EXECUTABLE" --qa-unregister-agent || true
  fi
  ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
  ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
    Scripts/uninstall-signed-qa-runtime.sh || true
  exit "$exit_code"
}
trap cleanup_on_exit EXIT INT TERM
# END RUNBOOK SELF-TEST: failure-cleanup
```

## Prove every relevant state

Verify the no-snapshot header first while the helper is still unregistered.

```zsh
verify_state preparing "PREPARING TODAY" 2>&1 | tee "$EVIDENCE/preparing.log"
```

This proves that the date does not disappear while the local Today snapshot is unavailable.
It also proves that the fallback says the data is preparing instead of inventing a plan or task state.

Verify the full persisted planning lifecycle.

```zsh
verify_state invitation "PLAN NEEDED" 2>&1 | tee "$EVIDENCE/invitation.log"
verify_state snoozed "PLANNING SNOOZED" 2>&1 | tee "$EVIDENCE/snoozed.log"
verify_state dismissed "PLANNING DISMISSED" 2>&1 | tee "$EVIDENCE/dismissed.log"
verify_state planned "PLANNED DAY" 2>&1 | tee "$EVIDENCE/planned.log"
verify_state unplanned "UNPLANNED DAY" 2>&1 | tee "$EVIDENCE/unplanned.log"
verify_state active "ACTIVE WORK" 2>&1 | tee "$EVIDENCE/active-precedence.log"
```

The active fixture deliberately retains `unplanned` as its planning mode.
The visible `ACTIVE WORK` result therefore proves that active-task truth takes precedence over the lower-level planning lifecycle label.

Each probe requires exactly one `today.day-state` accessibility element.
Each probe requires the locale-formatted current date, the literal `Day state` semantic label, and the expected state.
Each probe rejects the private title and URL sentinels stored in the snapshot payload.

## Prove ordinary relaunch persistence

Keep the planned snapshot unchanged and relaunch twice.

```zsh
stop_exact_app
wait_for_database_quiescence "$DATABASE"
"$FIXTURE" set planned --database "$DATABASE" --backup "$BACKUP"
open "$APP"

for relaunch in first second; do
  pid=""
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
      if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        pid="$candidate"
        break
      fi
    done
    test -n "$pid" && break
    sleep 0.2
  done
  test -n "$pid"
  ordinary_launch_command_is_valid "$(ps -p "$pid" -o command=)"
  wait_for_exact_database "$pid" "$DATABASE"
  swift "$PROBE" \
    --pid "$pid" \
    --app-bundle "$APP" \
    --expected-state "PLANNED DAY" \
    --reject "qa-zc013001-private-window-title" \
    --reject "qa-zc013001-private.invalid" \
    2>&1 | tee "$EVIDENCE/relaunch-$relaunch.log"
  if test "$relaunch" = first; then
    stop_exact_app
    wait_for_database_quiescence "$DATABASE"
    open "$APP"
  fi
done
```

Both opens are ordinary and use the same unchanged persisted snapshot.

## Cleanup

Stop the exact installed app, restore the original snapshot, verify cleanup, and uninstall the isolated runtime.

```zsh
stop_exact_app
wait_for_database_quiescence "$DATABASE"
"$FIXTURE" cleanup --database "$DATABASE" --backup "$BACKUP" 2>&1 | tee "$EVIDENCE/cleanup.log"
FIXTURE_PREPARED=false
test ! -e "$BACKUP"
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
Scripts/uninstall-signed-qa-runtime.sh
test ! -e "$APP"
test ! -e "$QA_ROOT"
trap - EXIT INT TERM
```

Do not mark ZC-013-001 fully usable until the same signed identity passes every state, both ordinary relaunches, accessibility semantics, privacy rejection, exact snapshot restoration, and isolated runtime cleanup.
