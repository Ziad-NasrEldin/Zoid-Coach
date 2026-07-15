# ZC-017-007 and ZC-037-002 signed QA runbook

This runbook proves that the installed Today interface presents open-ended active time as a live, trustworthy elapsed value.
The same journey accepts ZC-017-007 and the identical ZC-037-002 scenario contract.
The current canonical base is `ed5d07a363e0f64049c07b0e1d309d754caa035b`.
The reviewed product candidate is `d213c7bb0ace968c9a9847bf8b462bbc60d4c0c6`.
The reviewed tooling candidate is `47475d2b675662e0ad6e06f18b55753f1b2fdf23`.
The product stable patch ID is `07b53420dd8460831f99b94ef1e565e1f4a6dda7`.
The tooling stable patch ID is `fd2aefa977ce4c8b504b49b1735be9afd225d3ea`.
The preflight binds the exact current-base lineage, exact seven-file scope, package identity, installed executables, isolated database, and reviewed product blobs.

The journey uses a dedicated QA root and never reads or writes the user's production database.
Every branch starts from the same stopped, byte-exact baseline.
The final cleanup restores and independently compares the full baseline manifest.

## Acceptance contract

Full acceptance requires all of the following against one exact signed identity.

- Today shows one accessible live elapsed indicator for an active open-ended task.
- The displayed minute equals the confirmed elapsed minute when first observed.
- The displayed minute advances by exactly one without navigation or refresh.
- The live value survives one ordinary LaunchServices relaunch and continues advancing.
- A simulated wall-clock rollback never reduces nine confirmed minutes.
- A bounded active sprint does not show the open-ended indicator.
- A paused task does not show the open-ended indicator.
- Missing current open-interval metadata shows an honest nine-minute `LAST REFRESH` fallback.
- The visible and accessibility labels agree about the minute, live state, and fallback state.
- The private fixture note never appears anywhere in the main window accessibility tree.
- Cleanup restores every isolated QA-root file and symlink byte-for-byte.

## Bind the signed runtime

Grant Accessibility permission to the terminal running the probe.
Install one clean QA package that embeds the dedicated ZC-017-007 root.
Do not reuse another scenario's installed app or QA root.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc017007-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BASELINE_ROOT="/private/tmp/zoid-666-zc017007-byte-baseline"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc017007-open-ended-elapsed-fixture.sh"
PROBE="$PWD/Scripts/qa-zc017007-open-ended-elapsed-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc017007-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
BASELINE_MANIFEST="$BASELINE_ROOT.zc017007-manifest"
FINAL_MANIFEST="/private/tmp/zoid-666-zc017007-final-manifest"
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
```

Define bounded helpers for the isolated journey.

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
    --require-helper-unregistered --expected-app-pid "$PID"
  "$APP_EXECUTABLE" --qa-register-agent
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --expected-app-pid "$PID"
}

ordinary_relaunch() {
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  open "$APP"
  PID="$(resolve_pid)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open --expected-app-pid "$PID"
}

root_manifest() {
  (
    cd "$1"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
      /usr/bin/shasum -a 256 "$entry"
    done
    find . -type l -print | LC_ALL=C sort | while IFS= read -r entry; do
      printf 'SYMLINK %s -> %s\n' "$entry" "$(readlink "$entry")"
    done
  )
}
```

## Establish the byte baseline

The baseline must be captured while the app and helper are stopped.
The supported QA-ready-state fixture provides all normal first-run prerequisites before scenario-owned rows are added.

```sh
stop_runtime
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc017007-target" \
  "$BASELINE_ROOT.zc017007-manifest" "$BASELINE_ROOT.zc017007-restored-manifest" \
  "$FINAL_MANIFEST"
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
PID="$(resolve_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-helper-unregistered --expected-app-pid "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --expected-app-pid "$PID"
stop_runtime
sqlite3 "$DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);'
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
test -s "$BASELINE_MANIFEST"
```

## Prove live advance and ordinary relaunch

The live fixture starts near a minute boundary.
The probe allows one full minute boundary, rejects regressions on every poll, and requires an exact one-minute increment without clicking or navigating.
The proof is intentionally run after an ordinary relaunch so the same observation proves persistence and live advancement.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare live "$DATABASE"
start_branch
swift "$PROBE" --pid "$PID" --phase window --reject PRIVATE-ZC017007
ordinary_relaunch
swift "$PROBE" --pid "$PID" --phase live-advance --minimum-minutes 2 --reject PRIVATE-ZC017007
"$FIXTURE" verify live "$DATABASE"
stop_runtime
```

## Prove clock rollback cannot regress confirmed time

This fixture combines one exact nine-minute closed interval with an open interval whose start is twenty minutes in the future.
That is a deterministic database-level analogue of a wall clock moving backward while preserving confirmed elapsed work.
The signed Today UI must remain at nine minutes and label the value as live.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare rollback "$DATABASE"
start_branch
swift "$PROBE" --pid "$PID" --phase exact-live --expected-minutes 9 --reject PRIVATE-ZC017007
"$FIXTURE" verify rollback "$DATABASE"
stop_runtime
```

## Prove the honest last-refresh fallback

The execution state remains active while current open-interval metadata is deliberately absent.
Today must not imply a running timer and must retain the nine confirmed minutes.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare fallback "$DATABASE"
start_branch
swift "$PROBE" --pid "$PID" --phase fallback --expected-minutes 9 --reject PRIVATE-ZC017007
"$FIXTURE" verify fallback "$DATABASE"
stop_runtime
```

## Prove bounded and paused exclusions

Neither a bounded active sprint nor a paused task is an open-ended active session.
The dedicated elapsed indicator must be absent in both branches.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare bounded "$DATABASE"
start_branch
swift "$PROBE" --pid "$PID" --phase absent --reject PRIVATE-ZC017007
"$FIXTURE" verify bounded "$DATABASE"
stop_runtime

"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" prepare paused "$DATABASE"
start_branch
swift "$PROBE" --pid "$PID" --phase absent --reject PRIVATE-ZC017007
"$FIXTURE" verify paused "$DATABASE"
stop_runtime
```

## Restore and compare every byte

The final assertion uses the fixture's target binding and manifest comparison.
The independent comparison repeats the check without trusting only the fixture's success output.

```sh
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
root_manifest "$QA_ROOT" > "$FINAL_MANIFEST"
cmp -s "$BASELINE_MANIFEST" "$FINAL_MANIFEST"
rm -f -- "$FINAL_MANIFEST"
```

Only after every command above passes against one signed commit can ZC-017-007 and ZC-037-002 be promoted to fully implemented.
