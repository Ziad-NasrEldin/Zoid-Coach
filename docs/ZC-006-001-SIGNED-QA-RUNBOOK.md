# ZC-006-001 signed QA runbook

This runbook verifies the low-pressure planning invitation against one exact installed signed Zoid 666 QA candidate.
It covers zero, one, and three suggested commitments through the production agent draft path.
It proves that delivery is excluded before the configured morning boundary and delivered when that boundary has passed.
It then verifies the exact optional copy, privacy boundary, stable action order, Snooze, Dismiss, Work Unplanned, and ordinary relaunch persistence through native Accessibility.

## Bind the exact candidate

Install one clean signed QA package in an isolated root.
Grant Accessibility permission to the terminal running the native probe.
Close unrelated copies of Zoid 666.
Do not continue after a failed assertion.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
AGENT_PLIST="$(find "$APP/Contents/Library/LaunchAgents" -type f -name '*.plist' -maxdepth 1 -print)"
AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
TEMPLATE="$PWD/Scripts/fixtures/zc-006-001-planning-invitation-ready-state.json"
FIXTURE="$PWD/Scripts/qa-zc006001-planning-invitation-fixture.sh"
PROBE="$PWD/Scripts/qa-zc006001-planning-invitation-ax-probe.swift"
POLICY_READINESS="$PWD/Scripts/qa-zc006001-policy-readiness.sh"
POLICY_DECODER_SOURCE="$PWD/Scripts/qa-zc006001-policy-decode.swift"
PREFLIGHT="$PWD/Scripts/qa-zc006001-signed-preflight.sh"
WORK_ROOT="$(mktemp -d /private/tmp/zoid-666-zc006001-run.XXXXXX)"
BACKUP_ROOT="$WORK_ROOT/original-root"
ORIGINAL_HASHES="$WORK_ROOT/original-hashes.txt"
ORIGINAL_HELPER_REGISTERED=0
launchctl print "gui/$(id -u)/$(plutil -extract Label raw -o - "$AGENT_PLIST")" >/dev/null 2>&1 && ORIGINAL_HELPER_REGISTERED=1
"$PREFLIGHT" --self-test
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$POLICY_READINESS" --self-test
swiftc -package-name ZoidCoach "$PWD"/Sources/ZoidCoachCore/*.swift "$POLICY_DECODER_SOURCE" -o "$WORK_ROOT/policy-decoder"
POLICY_DECODER="$WORK_ROOT/policy-decoder"
```

The full signed commit must descend from current canonical base `361093b4a088c19eee927eaab2b58a40fb3b4c27`, contain refreshed product candidate `c8ea11afe0d479269fa21d697dd63a5f80688019`, and contain the committed verifier files used by this run.
The refreshed product candidate preserves source candidate `1270c4a874247bce410b7c9b641303166725621d` with stable patch ID `03b7fa8a5624af605d1ef2fdc5cc363b051fed36`.
The preflight rejects an abbreviated commit, another executable, another QA root, another database, or helper registration before the foreground app is bound.

## Preserve the isolated root byte for byte

Stop the app and helper before reading or replacing the isolated root.
The backup remains outside the repository and is mode 700.

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
```

The final cleanup compares the same relative file hashes after restoration.
No production root, Reminder, notification, Screenwatch source, or permission is used.

## Run one deterministic boundary case

Define the reusable case runner once in the same shell.
`future` proves that the native notification fixture remains scheduled and undelivered before the configured time.
`past` proves immediate delivery after the configured time and opens the installed app for native inspection.

```sh
set -euo pipefail
run_case() {
  local cardinality="$1" mode="$2" action_phase="${3:-inspect}" expected_count manifest preflight_output pid state_file
  case "$cardinality" in
    zero) expected_count=0 ;;
    one) expected_count=1 ;;
    many) expected_count=3 ;;
    *) return 2 ;;
  esac
  manifest="$WORK_ROOT/$cardinality-$mode.json"
  "$APP_EXECUTABLE" --qa-unregister-agent || true
  pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
  "$FIXTURE" materialize "$cardinality" "$manifest"
  MANIFEST="$manifest"
  "$READY_STATE" "$MANIFEST" "$QA_ROOT" --replace
  open "$APP" --args --qa-open-main
  preflight_output="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-helper-unregistered)"
  pid="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
  test -n "$pid"
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
  "$FIXTURE" seed-policy "$BACKUP_ROOT/root/Application Support/Zoid 666/zoid-coach.sqlite" "$DATABASE"
  open "$APP" --args --qa-open-main
  preflight_output="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-helper-unregistered)"
  pid="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
  test -n "$pid"
  "$POLICY_READINESS" wait "$DATABASE" "$pid" "$(plutil -extract Label raw -o - "$AGENT_PLIST")" "$POLICY_DECODER"
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
  "$FIXTURE" configure-boundary "$mode" "$DATABASE"
  "$AGENT_EXECUTABLE" --draft-plan --once
  "$FIXTURE" assert-database "$cardinality" "$DATABASE"
  state_file="$QA_ROOT/OS Fixtures/state.json"
  "$FIXTURE" assert-notification "$mode" "$cardinality" "$state_file"
  if test "$mode" = future; then
    return 0
  fi
  open "$APP" --args --qa-open-main
  preflight_output="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --require-helper-unregistered)"
  pid="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
  "$APP_EXECUTABLE" --qa-register-agent
  preflight_output="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --expected-app-pid "$pid")"
  test "$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')" = "$pid"
  swift "$PROBE" --pid "$pid" --phase inspect --count "$expected_count"
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
  open "$APP" --args --qa-open-main
  preflight_output="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT")"
  pid="$(printf '%s\n' "$preflight_output" | sed -n 's/^APP_PID=//p')"
  swift "$PROBE" --pid "$pid" --phase persisted --count "$expected_count"
  swift "$PROBE" --pid "$pid" --phase "$action_phase" --count "$expected_count"
  kill "$pid"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
}
```

The agent executable uses the package's embedded QA root and the supported `--draft-plan --once` path.
The verifier never inserts a prompt directly.
The database assertion requires one canonical `PLAN_READY` episode with exact title, cardinality copy, payload count, five stable action identities in order, and no private sentinel.

## Prove future exclusion and past delivery for every cardinality

Use fresh ready-state roots so no plan or prompt from one case can satisfy another.
The future and past checks use the same product code and differ only in the configured Cairo morning boundary.

```sh
set -euo pipefail
run_case zero future
run_case zero past work-unplanned
run_case one future
run_case one past dismiss
run_case many future
run_case many past snooze
```

The zero case proves that the product never invents a suggestion.
The one case proves singular grammar.
The many case proves plural grammar without leaking task names into the invitation copy.
Every past case is inspected, quit normally, relaunched from the same installed bundle, inspected again, and only then acted on.
The three action cases cover starting without a plan, temporary dismissal, and the fifteen-minute snooze through visible production controls.

## Restore the isolated root and registration state

Cleanup runs with the app and helper stopped.
It removes only the temporary ZC-006 workspace and restores the prior isolated root exactly.

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
if test "$ORIGINAL_HELPER_REGISTERED" = 1; then
  "$APP_EXECUTABLE" --qa-register-agent
fi
rm -rf -- "$WORK_ROOT"
```

Record the exact signed commit, package identity, app PID, helper registration state, fixture PASS lines, AX PASS lines, and cleanup hash comparison in the immutable evidence report.
Do not mark ZC-006-001 Fully implemented from tooling or builder evidence alone.
