# ZC-011-007 signed invalid-estimate QA runbook

This runbook verifies one exact installed signed Zoid 666 candidate against the full custom-estimate validation matrix.
It covers empty input, ASCII and Unicode whitespace, zero, negative values, decimal and text input, localized digits, localized decimal punctuation, values above 480 minutes, and a valid whitespace-padded recovery.
It also proves exact corrective copy, keyboard Return submission, retained input and focus after failure, no durable mutation on failure, valid persistence, accessibility, privacy, ordinary relaunch, and byte-exact restoration.

The current canonical base is `2cba674f8370fc16f9555cdb6f115f18df1f8ced`.
The exact patch-equivalent QA tooling replay is `c221005ea00f4be9efc895c8eccfd618a10501d1` with stable patch ID `54853a6c3d47fdbb9dec56ebc695e7143f7c5b92`.
The reviewed shared-editor product fix is `180367af761c0bd1abcdb952bd12e3077b7f300b` with stable patch ID `ca93eecc45fe7b252b3678a029aee68e79cc0477`.
The product fix introduces one shared custom-estimate editor interaction state and component used by both `DashboardView.swift` and `TodayDashboardCommandOverview.swift`.
`CustomEstimateEditorStateTests` bind ten invalid inputs, exact input and focus retention, active-path host exclusion, bounded single-mount re-render stability, independent surface state, exactly-once valid persistence, rapid resubmission, and legacy parser boundaries.
The preflight rejects any product drift after that reviewed commit and keeps `TaskEstimateInput.swift` plus its legacy tests byte-identical to canonical.

## Bind the exact signed package

Use a clean QA package whose embedded root is in the isolated ZC-011-007 namespace.
Grant Accessibility and event-posting permission to the terminal running the verifier before starting.
Do not change macOS permissions during this run.
Do not start while another signed-QA lane owns the installed app, LaunchAgent, or Mach service.

```sh
set -euo pipefail
set -o pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc011007-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE_SNAPSHOT="/private/tmp/zoid-666-zc011007-baseline"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc011007-invalid-estimate-fixture.sh"
AX_PROBE="$PWD/Scripts/qa-zc011007-invalid-estimate-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc011007-signed-preflight.sh"
APPROVED_FINAL_VALIDATOR="/absolute/path/from/pinned-validator-worktree/validate-zc011007-approved-final.sh"
SAFE_HOME="$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
TASK_ID="qa-zc011007-invalid-estimate"
PRIVATE_NOTE="qa-zc011007-private-estimate-note"

preflight() {
  /usr/bin/env -i \
    HOME="$SAFE_HOME" \
    TMPDIR=/private/tmp \
    PATH=/usr/bin:/bin \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_ATTR_NOSYSTEM=1 \
    /bin/zsh "$APPROVED_FINAL_VALIDATOR" "$PREFLIGHT" "$@"
}

test -x "$APPROVED_FINAL_VALIDATOR"
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor b97c2ce3177ccf89f60225c475062608db1920ad "$EXPECTED_SIGNED_COMMIT"
preflight --self-test
swift test --filter CustomEstimateEditorStateTests
swift test --filter customEstimate
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean

APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
test -x "$APP_EXECUTABLE"
test "$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")" = "$QA_ROOT"
```

The full signed commit must be repository HEAD.
The diff from canonical base must contain exactly twenty-three reviewed commits, ending with the externally approved two-file final lineage candidate.
The cumulative candidate is bound through the rank-one fixture fix, shared confirmation accessibility fix, persisted-evidence probe fix, explicit Dashboard/Today surface selection, exact surface-specific accessibility labels, canonical trace-path containment, exclusive isolated database ownership, atomic fixture seeding, fail-closed whole-root restoration, scrubbed validator execution, and the signed-runtime Dashboard reachability fix `ba087b3160098c9b37831ac42999889d3299a413`.
The full candidate scope remains exactly eight files, and the final lineage commit edits only this runbook and the signed preflight.
Tracker, registry, Lavish, backlog, parser, legacy parser-test, and unrelated verifier changes are rejected.
The pinned validator re-executes under an explicit minimal environment and invokes the candidate preflight with the same fixed `/usr/bin:/bin` path, actual account home, `/private/tmp`, and Git configuration suppression.
Ambient Git worktree overrides, fixture dates, approval variables, and executable-path injections are not inherited.

## Establish and snapshot the ready-state baseline

Stop the exact app and helper before replacing the isolated root.
Launch and bind the foreground app before helper registration.

```sh
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
  if /usr/sbin/lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
rm -rf -- "$BASELINE_SNAPSHOT" "$BASELINE_SNAPSHOT".zc011007-*(N)
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
FOREGROUND_OUTPUT="$(preflight "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered)"
printf '%s\n' "$FOREGROUND_OUTPUT"
PID="$(printf '%s\n' "$FOREGROUND_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
preflight "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
swift "$WINDOW_PROBE" "$PID" --expect-today
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$APP_EXECUTABLE" --qa-unregister-agent
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

The snapshot occurs only after both signed processes stop and SQLite checkpoints its WAL.
The snapshot directory, target marker, manifest, copied control directory, copied owner marker, and copied database must remain current-user-owned, canonical, non-symlinked, and single-linked where they are files.
The final restoration compares every file and symlink against this baseline.

## Prepare the exact missing-estimate task

The fixture replaces only the current isolated daily plan and adds one local main objective with no estimate and no active interval.
The entire root is restored later, including any baseline plan rows displaced by the deterministic fixture.

```sh
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-unmutated "$DATABASE"
open "$APP"
ORDINARY_OUTPUT="$(preflight "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --require-helper-unregistered)"
PID="$(printf '%s\n' "$ORDINARY_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
preflight "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
```

Every probe call rejects the raw task ID, private fixture note, database path, and QA root from the accessibility tree.

```sh
probe() {
  local surface="$1"
  shift
  swift "$AX_PROBE" --pid "$PID" "$@" \
    --surface "$surface" \
    --forbid "$TASK_ID" \
    --forbid "$PRIVATE_NOTE" \
    --forbid "$DATABASE" \
    --forbid "$QA_ROOT"
}

run_invalid_case() {
  local surface="$1"
  local case_name="$2"
  local probe_status=0
  probe "$surface" --phase submit --case "$case_name" || probe_status=$?
  (( probe_status == 0 )) || return "$probe_status"
  "$FIXTURE" assert-unmutated "$DATABASE"
}

probe today --phase open
```

The open phase finds the exact task-specific Custom action through normal Today accessibility, opens it, and places keyboard focus in the labelled minutes field.
The editor must expose Save and Cancel without leaking fixture internals.

## Prove every invalid case with physical Return

Each submit phase focuses the same production field, uses Command-A and Delete to replace the previous correction, types the case through `CGEvent`, and submits with a physical Return key event at the HID event tap.
The editor must stay open with the exact raw input, keyboard focus, Save, Cancel, and the exact corrective sentence.
The database must remain missing-estimate truth after every failure.

```sh
run_invalid_case today empty
run_invalid_case today whitespace
run_invalid_case today unicode-whitespace
run_invalid_case today zero
run_invalid_case today negative
run_invalid_case today decimal
run_invalid_case today text
run_invalid_case today localized-digits
run_invalid_case today localized-decimal
run_invalid_case today too-large
```

The exact expected errors are:

- Empty, ASCII whitespace, and Unicode whitespace: `Enter an estimate in minutes.`
- Zero and negative values: `Estimate must be at least 1 minute.`
- Decimal, text, Arabic-Indic digits, and comma-decimal input: `Use a whole number of minutes, such as 25.`
- 481 minutes: `Estimate must be 480 minutes or less. Split larger work into smaller tasks.`

The localized inputs are intentionally rejected rather than silently misinterpreted.
No failure may show a confirmed estimate, close the editor, move focus away from correction, or write `estimate_minutes` or `estimate_is_uncertain`.

## Prove valid correction and durable recovery

Submit the whitespace-padded whole number ` 25 ` through the same focused field and physical Return path.

```sh
probe today --phase submit --case valid-padded
"$FIXTURE" assert-valid "$DATABASE"
```

After restoring the baseline root and preparing the fixture again, repeat the same exact matrix on the Dashboard surface.

```sh
probe dashboard --phase open
run_invalid_case dashboard empty
run_invalid_case dashboard whitespace
run_invalid_case dashboard unicode-whitespace
run_invalid_case dashboard zero
run_invalid_case dashboard negative
run_invalid_case dashboard decimal
run_invalid_case dashboard text
run_invalid_case dashboard localized-digits
run_invalid_case dashboard localized-decimal
run_invalid_case dashboard too-large
probe dashboard --phase submit --case valid-padded
"$FIXTURE" assert-valid "$DATABASE"
```

The editor must close, all stale error copy must disappear, and the exact accessible confirmation must read `Time estimate confirmed: 25 MIN`.
The fixture requires a durable value of exactly 25 minutes with uncertainty still false.

Quit and relaunch through an ordinary LaunchServices open without touching the database.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP"
RELAUNCH_OUTPUT="$(preflight "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open)"
PID="$(printf '%s\n' "$RELAUNCH_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
probe today --phase persisted
"$FIXTURE" assert-valid "$DATABASE"
```

The ordinary relaunch must restore exactly one main Today window and the same confirmed 25-minute estimate.
The custom editor and every prior validation error must remain closed and absent.

## Whole-root restoration and cleanup

Stop both signed processes before cleanup and restoration.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$APP_EXECUTABLE" --qa-unregister-agent
"$FIXTURE" checkpoint "$DATABASE"
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"
```

No SQL cleanup is allowed.
Whole-root restoration recovers the exact fixture-owned ready-state bytes and symlinks, including the original database, after both signed processes stop.
Immediately before deleting the live root, the fixture revalidates its canonical namespace, non-symlinked mode-700 current-user root, mode-700 control directory, exact private single-link owner marker, canonical single-link database, stopped QA processes, and absence of open database handles.
Any forged or linked snapshot metadata, changed live-root ownership, restarted signed QA process, or open database handle aborts restoration without deleting the live root.
After proof is archived, delete the entire isolated QA root and installed QA bundle rather than deleting rows from a database.

## Acceptance boundary

Do not mark ZC-011-007 fully usable unless every package, lineage, foreground-before-helper, ordinary relaunch, exact error, retained-focus, keyboard Return, no-mutation, valid-recovery, persistence, accessibility, privacy, cleanup, and byte-restoration assertion passes against one installed signed identity.
Static tests, source-code presence, or an AX value written without keyboard submission do not qualify.
