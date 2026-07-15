# ZC-025-006 signed QA runbook

This runbook proves that a materially ambiguous Unknown activity session is genuinely usable from the signed Today interface.
The original reviewed product candidate is `730677a66c265823ef9417af8abe55a8f0b0e998`.
The current canonical base is `15d8e6ec42bf178e9de2ee055dd6915c8c74b786`.
The exact current-base product commit is `c552ea29472ccb1de30a7f896e30f159003aa374`.
The exact current-base tooling commit is `e659575a3ecfcc9379e0c97332b32da4c5fd9ba7`.
The reviewed signed-runtime baseline fixture fix is `5482a1ed6bb7b73a255137937f0f458e9dd68294`.
The raw product change has stable patch ID `b19bb45f10aa9dabcb1bde528139a75c3ef2f05f`.
The raw signed acceptance tooling has stable patch ID `1570803ab40dc2f57785fb23babd984c93d3fc32`.
The complete-baseline fixture fix has stable patch ID `467749eff5875502ea2f5a7c45276a4e6024806c`.
The preflight binds the exact current-base lineage, exact 12-file ownership scope, all three reviewed raw patch identities, and two two-file lineage-contract maintenance commits.

The acceptance journey uses an isolated QA root and never touches the user's production database.
Every action branch and boundary branch starts from the same byte baseline.
Every branch stops the app and helper before replacing the isolated root.
The final cleanup restores every baseline file and independently compares SHA-256 manifests.

## Acceptance contract

Full acceptance requires all of the following against one exact signed identity.

- One fresh ten-minute Unknown Safari session overlapping one active task produces exactly one waiting prompt.
- The prompt explains that application and duration cannot prove intent.
- The prompt never exposes the private window title or URL.
- Today exposes exactly three accessible response actions: supporting work, gaming, and keep unknown.
- Supporting work writes one exact Work correction attached to the active task.
- Gaming writes one exact Gaming correction with no task attachment.
- Keep unknown writes no correction.
- Each action produces exact visible success copy and one resolved history row.
- Each action survives a helper restart and an ordinary app relaunch without another prompt.
- No prompt appears with nine minutes, no active task, only five minutes of task overlap, stale evidence, or already-certain Work evidence.
- Raw observations remain unchanged by every response.
- Cleanup restores the isolated QA root byte-for-byte.

## Install and bind the signed runtime

Grant Accessibility permission to the terminal running the probe.
Install one clean QA package using the dedicated ZC-025-006 QA root.
Do not reuse another scenario's installed app or QA root.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc025006-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE_ROOT="/private/tmp/zoid-666-zc025006-byte-baseline"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc025006-ambiguity-fixture.sh"
PROBE="$PWD/Scripts/qa-zc025006-ambiguity-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc025006-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
BASELINE_MANIFEST="$BASELINE_ROOT.zc025006-manifest"
FINAL_MANIFEST="/private/tmp/zoid-666-zc025006-final-manifest"
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
```

The preflight binds the package signature, build identity, reviewed stable patch, exact app executable, exact helper executable, embedded QA root, and isolated database.
It also rejects a duplicate or missing main window and distinguishes the initial QA foreground launch from every ordinary persistence relaunch.
If the foreground app completes its first inbox refresh before the helper finishes startup, the AX probe presses the visible `REFRESH` control once and continues through the same public Today interface.
The probe never invokes a private product method or writes a prompt directly.

Define bounded runtime helpers for this isolated journey.

```sh
resolve_pid() {
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
      if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    sleep 0.2
  done
  return 1
}

stop_runtime() {
  "$APP_EXECUTABLE" --qa-unregister-agent || true
  for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
    if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
      kill "$candidate"
      while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
    fi
  done
}

start_branch() {
  open "$APP" --args --qa-open-main
  PID="$(resolve_pid)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-qa-open-main --require-helper-unregistered --expected-app-pid "$PID"
  "$APP_EXECUTABLE" --qa-register-agent
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-qa-open-main --expected-app-pid "$PID"
}

wait_for_prompt() {
  for attempt in {1..50}; do
    "$FIXTURE" assert-prompt "$DATABASE" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  "$FIXTURE" assert-prompt "$DATABASE"
}

restart_helper_without_reprompt() {
  "$APP_EXECUTABLE" --qa-unregister-agent
  "$APP_EXECUTABLE" --qa-register-agent
  sleep 2
  "$FIXTURE" assert-no-reprompt "$DATABASE"
}

ordinary_relaunch() {
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  open "$APP"
  PID="$(resolve_pid)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open --expected-app-pid "$PID"
}
```

## Establish and snapshot the exact baseline

Stop all isolated runtime processes before replacing the QA root.
Establish the repository's supported 12-of-12 QA ready state.
Each scenario fixture also establishes exactly seven complete baseline-observation days so the production behavior-prompt gate is open before exercising ambiguity-specific eligibility.
Launch the foreground app before registering the helper so the helper cannot create a windowless first-run state.

```sh
stop_runtime
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc025006-target" \
  "$BASELINE_ROOT.zc025006-manifest" "$BASELINE_ROOT.zc025006-restored-manifest" \
  "$FINAL_MANIFEST"
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
PID="$(resolve_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered --expected-app-pid "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
stop_runtime
sqlite3 "$DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);'
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
test -s "$BASELINE_MANIFEST"
```

The byte baseline is captured only while the app and helper are stopped.
Every subsequent branch restores that baseline before adding its fixture.

## Prove supporting work end to end

Restore the baseline, prepare the qualifying ten-minute Unknown session, and start the signed app before its helper.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare qualifying "$DATABASE"
start_branch
wait_for_prompt
ordinary_relaunch
"$FIXTURE" assert-prompt "$DATABASE"
swift "$PROBE" --pid "$PID" --phase prompt
swift "$PROBE" --pid "$PID" --phase choose-work
"$FIXTURE" assert-effect work "$DATABASE"
restart_helper_without_reprompt
ordinary_relaunch
swift "$PROBE" --pid "$PID" --phase history-work
"$FIXTURE" assert-effect work "$DATABASE"
"$FIXTURE" assert-no-reprompt "$DATABASE"
stop_runtime
```

The visible success copy must state that the session now counts as supporting work for `QA focus task`.
The database must contain one exact Work correction covering the prompt's start and end epochs and attached to `qa-zc025006-task`.
The ten raw observations must remain Unknown.

## Prove gaming end to end

Repeat from the byte baseline so this branch cannot inherit the Work response.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare qualifying "$DATABASE"
start_branch
wait_for_prompt
ordinary_relaunch
"$FIXTURE" assert-prompt "$DATABASE"
swift "$PROBE" --pid "$PID" --phase prompt
swift "$PROBE" --pid "$PID" --phase choose-gaming
"$FIXTURE" assert-effect gaming "$DATABASE"
restart_helper_without_reprompt
ordinary_relaunch
swift "$PROBE" --pid "$PID" --phase history-gaming
"$FIXTURE" assert-effect gaming "$DATABASE"
"$FIXTURE" assert-no-reprompt "$DATABASE"
stop_runtime
```

The visible success copy must state that the session now counts as gaming.
The database must contain one exact Gaming correction covering the prompt's start and end epochs with no task attachment.
The ten raw observations must remain Unknown.

## Prove keep unknown end to end

Repeat from the byte baseline so this branch cannot inherit either classification.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare qualifying "$DATABASE"
start_branch
wait_for_prompt
ordinary_relaunch
"$FIXTURE" assert-prompt "$DATABASE"
swift "$PROBE" --pid "$PID" --phase prompt
swift "$PROBE" --pid "$PID" --phase choose-unknown
"$FIXTURE" assert-effect unknown "$DATABASE"
restart_helper_without_reprompt
ordinary_relaunch
swift "$PROBE" --pid "$PID" --phase history-unknown
"$FIXTURE" assert-effect unknown "$DATABASE"
"$FIXTURE" assert-no-reprompt "$DATABASE"
stop_runtime
```

The visible success copy must state that the session remains unknown and coaching was not changed.
The database must contain no correction for the session.
The durable response and applied effect marker must still prevent another prompt after helper and app restart.

## Prove every ineligible boundary remains absent

Each boundary starts from the byte baseline and runs the real signed helper startup path.
The three-second observation window exceeds the helper's synchronous startup production pass.

### Nine minutes is below the material threshold

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare short "$DATABASE"
start_branch
sleep 3
"$FIXTURE" assert-absent "$DATABASE"
swift "$PROBE" --pid "$PID" --phase absent
stop_runtime
```

### An Unknown session without an active task remains unprompted

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare no-task "$DATABASE"
start_branch
sleep 3
"$FIXTURE" assert-absent "$DATABASE"
swift "$PROBE" --pid "$PID" --phase absent
stop_runtime
```

### Only five minutes of active-task overlap remains unprompted

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare late-task "$DATABASE"
start_branch
sleep 3
"$FIXTURE" assert-absent "$DATABASE"
swift "$PROBE" --pid "$PID" --phase absent
stop_runtime
```

### Evidence older than three minutes remains unprompted

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare stale "$DATABASE"
start_branch
sleep 3
"$FIXTURE" assert-absent "$DATABASE"
swift "$PROBE" --pid "$PID" --phase absent
stop_runtime
```

### Already-certain Work evidence remains unprompted

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare certain "$DATABASE"
start_branch
sleep 3
"$FIXTURE" assert-absent "$DATABASE"
swift "$PROBE" --pid "$PID" --phase absent
stop_runtime
```

## Restore and independently prove cleanup

Stop the exact app and helper before final restoration.
Restore the byte baseline with the guarded fixture command.
Then create a second manifest independently instead of trusting only the restore command's internal comparison.

```sh
stop_runtime
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
(
  cd "$QA_ROOT"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
    /usr/bin/shasum -a 256 "$entry"
  done
  find . -type l -print | LC_ALL=C sort | while IFS= read -r entry; do
    printf 'SYMLINK %s -> %s\n' "$entry" "$(readlink "$entry")"
  done
) > "$FINAL_MANIFEST"
cmp -s "$BASELINE_MANIFEST" "$FINAL_MANIFEST"
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc025006-target" \
  "$BASELINE_ROOT.zc025006-manifest" "$BASELINE_ROOT.zc025006-restored-manifest" \
  "$FINAL_MANIFEST"
```

Do not mark ZC-025-006 fully usable unless all three action branches, all five absence branches, both privacy layers, helper restart, ordinary app relaunch, no-reprompt assertions, and both byte-restore comparisons pass against the same signed build identity.
