# ZC-013-001 signed QA runbook

This runbook verifies that Today always exposes the current date and one explicit day state.
The product candidate is `db0a5305604bfb372da20fb95c8f05d22c4660b8`.
The signed build may be that commit or a reviewed descendant that contains the candidate and this verifier tooling.

The journey uses an isolated QA root and install root.
The fixture backs up only the current-day Today snapshot to an external runtime file, drives the UI through the real persisted snapshot boundary, and restores the original payload byte-for-byte during cleanup.
No evidence is written inside the repository before package cleanliness verification.

## Preflight and installation

Run the full journey from one shell rooted at the candidate repository.

```sh
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
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"

test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor db0a5305604bfb372da20fb95c8f05d22c4660b8 "$EXPECTED_SIGNED_COMMIT"
"$FIXTURE" self-test
swift "$PROBE" --self-test
mkdir -p "$EVIDENCE"

ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
Scripts/install-signed-qa-runtime.sh 2>&1 | tee "$EVIDENCE/install.log"

ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
```

The evidence directory is external to the repository, so installer logs cannot invalidate the clean-package gate.

Resolve the exact packaged identities and establish the supported ready state.

```sh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_PLIST=("$APP"/Contents/Library/LaunchAgents/*.plist)
test "${#AGENT_PLIST[@]}" = 1
AGENT_LABEL="$(plutil -extract Label raw -o - "${AGENT_PLIST[0]}")"

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

```sh
"$APP_EXECUTABLE" --qa-unregister-agent
pkill -x "$APP_EXECUTABLE_NAME" || true
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
"$FIXTURE" prepare --database "$DATABASE" --backup "$BACKUP"
```

The accessibility probe resolves the installed bundle's preferred localization and formats the current instant with that locale, `Calendar.current`, `TimeZone.current`, and the product's exact weekday, wide-month, and day fields.
This keeps month-first and day-first localizations exact without accepting a partial or reordered date.

## Ordinary-launch acceptance helper

Use this helper in the same shell for every state.
It binds the exact installed executable, rejects presentation-only launch arguments, proves that the app opened the isolated database, and runs the accessibility and privacy assertions.

```sh
stop_exact_app() {
  local candidate
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
      kill "$candidate"
      while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
    fi
  done
}

verify_state() {
  local fixture_state="$1"
  local expected_state="$2"
  local candidate pid command_line
  stop_exact_app
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
  test "$command_line" != *"--qa-open-main"*
  test "$command_line" != *"--background-schedule"*
  lsof -Fn -a -p "$pid" "$DATABASE" 2>/dev/null | grep -Fqx "n$DATABASE"
  swift "$PROBE" \
    --pid "$pid" \
    --app-bundle "$APP" \
    --expected-state "$expected_state" \
    --reject "qa-zc013001-private-window-title" \
    --reject "qa-zc013001-private.invalid"
  "$FIXTURE" assert "$fixture_state" --database "$DATABASE" --backup "$BACKUP"
}
```

## Prove every relevant state

Verify the no-snapshot header first while the helper is still unregistered.

```sh
verify_state preparing "PREPARING TODAY" 2>&1 | tee "$EVIDENCE/preparing.log"
```

This proves that the date does not disappear while the local Today snapshot is unavailable.
It also proves that the fallback says the data is preparing instead of inventing a plan or task state.

Verify the full persisted planning lifecycle.

```sh
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

```sh
stop_exact_app
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
  test "$(ps -p "$pid" -o command=)" != *"--qa-open-main"*
  swift "$PROBE" \
    --pid "$pid" \
    --app-bundle "$APP" \
    --expected-state "PLANNED DAY" \
    --reject "qa-zc013001-private-window-title" \
    --reject "qa-zc013001-private.invalid" \
    2>&1 | tee "$EVIDENCE/relaunch-$relaunch.log"
  if test "$relaunch" = first; then
    stop_exact_app
    open "$APP"
  fi
done
```

Both opens are ordinary and use the same unchanged persisted snapshot.

## Cleanup

Stop the exact installed app, restore the original snapshot, verify cleanup, and uninstall the isolated runtime.

```sh
stop_exact_app
"$FIXTURE" cleanup --database "$DATABASE" --backup "$BACKUP" 2>&1 | tee "$EVIDENCE/cleanup.log"
test ! -e "$BACKUP"
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
Scripts/uninstall-signed-qa-runtime.sh
test ! -e "$APP"
test ! -e "$QA_ROOT"
```

Do not mark ZC-013-001 fully usable until the same signed identity passes every state, both ordinary relaunches, accessibility semantics, privacy rejection, exact snapshot restoration, and isolated runtime cleanup.
