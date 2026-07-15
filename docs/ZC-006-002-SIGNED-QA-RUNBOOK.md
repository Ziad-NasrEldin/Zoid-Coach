# ZC-006-002 signed QA runbook

This runbook verifies the first-use-after-inactivity planning invitation in one exact installed signed QA package.
It proves that the configured time zone and planning time own the missed boundary, an existing valid plan is retained, one privacy-safe invitation is persisted, one notification is due, the checkpoint prevents a duplicate after restart, and the visible app exposes the invitation without task or behavior details.
It does not justify a Full claim by itself.

Do not run the signed journey without an orchestration runtime lease.
Complete the product tests, release build, tooling self-tests, scope check, and clean candidate commit before requesting that lease.

## Bind the candidate

Use one clean signed QA package rooted outside production.
Close unrelated Zoid 666 copies and grant Accessibility permission to the terminal running the probe.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_CANDIDATE_COMMIT"
PREFLIGHT="$PWD/Scripts/qa-zc006002-signed-preflight.sh"
FIXTURE="$PWD/Scripts/qa-zc006002-missed-invitation-fixture.sh"
PROBE="$PWD/Scripts/qa-zc006002-missed-invitation-ax-probe.swift"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
TEMPLATE="$PWD/Scripts/fixtures/zc-006-001-planning-invitation-ready-state.json"
WORK_ROOT="$(mktemp -d /private/tmp/zoid-zc006002-run.XXXXXX)"
MANIFEST="$WORK_ROOT/ready-state.json"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_PLIST="$(find "$APP/Contents/Library/LaunchAgents" -type f -name '*.plist' -maxdepth 1 -print)"
AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
BACKUP_ROOT="$WORK_ROOT/original-root"
ORIGINAL_HASHES="$WORK_ROOT/original-hashes.txt"
"$PREFLIGHT" --self-test
"$FIXTURE" self-test
swift "$PROBE" --self-test
```

The preflight rejects abbreviated revisions, packages that do not descend from canonical `b73a1c1c489eb02017d8609eab7a056296065819`, packages that omit the committed verifier, another executable, another QA root, or a helper that does not own the isolated database.

## Preserve and prepare the isolated root

Stop the app and helper before backup or fixture mutation.
The baseline and restoration remain limited to the embedded QA root.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
mkdir -m 700 "$BACKUP_ROOT"
if test -d "$QA_ROOT"; then
  ditto "$QA_ROOT" "$BACKUP_ROOT/root"
  (cd "$BACKUP_ROOT/root" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$ORIGINAL_HASHES"
else
  : > "$ORIGINAL_HASHES"
fi
jq '.osFixture.reminders = .osFixture.reminders[:1]
  | .osFixture.reminders[0].title = "Prepare quarterly launch outline"' "$TEMPLATE" > "$MANIFEST"
"$READY_STATE" "$MANIFEST" "$QA_ROOT" --replace
"$APP_EXECUTABLE" --qa-register-agent
BOOTSTRAP_READY=0
for _ in {1..120}; do
  if test -f "$DATABASE"; then
    SCHEMA_TABLES="$(sqlite3 -batch -noheader "$DATABASE" \
      "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('settings','processing_checkpoints','prompt_episodes','policy_versions');" 2>/dev/null || true)"
    POLICY_ROWS="$(sqlite3 -batch -noheader "$DATABASE" \
      "SELECT COUNT(*) FROM settings WHERE key='user_policy' AND json_valid(value_json);" 2>/dev/null || true)"
    if test "$SCHEMA_TABLES" = 4 && test "$POLICY_ROWS" = 1 \
      && sqlite3 -batch "$DATABASE" \
        'BEGIN IMMEDIATE; UPDATE settings SET updated_at_utc=updated_at_utc WHERE 0; ROLLBACK;' \
        >/dev/null 2>&1; then
      CHECKPOINT="$(sqlite3 -batch -noheader "$DATABASE" 'PRAGMA wal_checkpoint(PASSIVE);')"
      IFS='|' read -r CHECKPOINT_BUSY CHECKPOINT_LOG CHECKPOINT_DONE <<<"$CHECKPOINT"
      if test "$CHECKPOINT_BUSY" = 0 && test "$CHECKPOINT_LOG" = "$CHECKPOINT_DONE"; then
        BOOTSTRAP_READY=1
        break
      fi
    fi
  fi
  sleep 0.25
done
test "$BOOTSTRAP_READY" = 1
"$APP_EXECUTABLE" --qa-unregister-agent
if launchctl print "gui/$(id -u)/qa.ziadnasreldin.ZoidCoach.agent" >/dev/null 2>&1; then
  echo "QA helper remained registered after bootstrap" >&2
  exit 1
fi
fixture_output="$("$FIXTURE" configure "$DATABASE")"
printf '%s\n' "$fixture_output"
EXPECTED_LOCAL_DAY="$(printf '%s\n' "$fixture_output" | sed -n 's/^EXPECTED_LOCAL_DAY=//p')"
test -n "$EXPECTED_LOCAL_DAY"
```

The fixture places the previous heartbeat before yesterday's configured planning boundary while today's boundary remains in the future.
It places today's invitation boundary in the past, preserving a genuine inactive crossing without changing the system clock.
The one Reminder title is intentionally separate from the private sentinel checked by every verifier.

## Exercise first use and restart

Start the packaged helper through its supported registration path.
Wait for the persisted checkpoint and invitation before opening the foreground app.
Foreground open must not reuse a background-schedule process.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-register-agent
for _ in {1..100}; do
  if "$FIXTURE" assert-database "$DATABASE" "$EXPECTED_LOCAL_DAY" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
"$FIXTURE" assert-database "$DATABASE" "$EXPECTED_LOCAL_DAY"
"$FIXTURE" assert-notification "$QA_ROOT/OS Fixtures/state.json"
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
  candidate_executable="$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
  if test "$candidate_executable" = "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
open "$APP" --args --qa-open-main
preflight_output=""
for _ in {1..60}; do
  if preflight_output="$("$PREFLIGHT" "$APP" "$EXPECTED_SIGNED_COMMIT" 2>/dev/null)"; then
    break
  fi
  sleep 0.2
done
test -n "$preflight_output"
printf '%s\n' "$preflight_output"
APP_PID="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
swift "$PROBE" --pid "$APP_PID"
before_restart_count="$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='PLAN_READY';")"
"$APP_EXECUTABLE" --qa-unregister-agent
"$APP_EXECUTABLE" --qa-register-agent
sleep 2
after_restart_count="$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='PLAN_READY';")"
test "$before_restart_count" = 1
test "$after_restart_count" = 1
"$FIXTURE" assert-database "$DATABASE" "$EXPECTED_LOCAL_DAY"
```

The database assertion requires one unresolved canonical invitation, the exact configured local day, one successful nightly checkpoint with the missed heartbeat, the stable dismissal contract, and no private sentinel.
The restart assertion rejects a second prompt.
The native Accessibility probe binds the exact foreground PID and requires the low-pressure invitation language without task or behavior evidence.

## Restore exactly

Stop both processes before replacing the QA root.
Compare every restored file hash and restore the prior helper registration state separately if the orchestration lease requires it.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
rm -rf -- "$QA_ROOT"
if test -d "$BACKUP_ROOT/root"; then
  ditto "$BACKUP_ROOT/root" "$QA_ROOT"
  RESTORED_HASHES="$WORK_ROOT/restored-hashes.txt"
  (cd "$QA_ROOT" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$RESTORED_HASHES"
  cmp "$ORIGINAL_HASHES" "$RESTORED_HASHES"
else
  test ! -e "$QA_ROOT"
fi
rm -rf -- "$WORK_ROOT"
```

Record the exact signed commit, package verification output, app PID, helper PID, configured boundary output, checkpoint row, prompt count before and after restart, notification assertion, AX assertion, and byte-restoration comparison in immutable evidence.
Do not update the tracker or registry from builder or static evidence.
