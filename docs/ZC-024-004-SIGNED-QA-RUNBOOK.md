# ZC-024-004 signed QA runbook

This runbook verifies that the installed signed app refreshes visible Today behavior and source freshness without closing the main window.
The current-base candidate reassembles reviewed lineage `1bb3c27866bc3acbfd449d680371b0b340710738` on canonical base `ed5d07a363e0f64049c07b0e1d309d754caa035b` at merge `44c1bca116525709d7c4708b4f4a7089fa11c70f`.
The initial deterministic Today-scroll verifier fix is commit `fa95aeab65fb23a1971e6a7c3464ae87d51febf7`, its reviewed rebind is `cc2dc2a0c2cf2b7dea7d0db75a9d05ec03a43e57`, the separated-row capture correction is `69b16a3335867a43ef8ae7904705a3d40f3e738f`, and its reviewed rebind is `1e06a4807f12a9e78886cdca24eb23afe46d1772`.
The exact accessibility-label normalization correction is commit `d36cedc7da6146b4c8982c15733a3899e0d57013`.
The static verifier requires the signed commit to be the one preflight and runbook bind child of the normalization correction.
Each capture resets Today to the top, binds one app PID and main-window token, retains only normalized Working and Screenwatch values from the same bounded sequence, and reacquires a fresh unique Accessibility tree after every scroll step.
The verifier rejects within-tree or cross-generation ambiguity, changed values, stale generations, PID or window replacement, privacy leakage, and timeout.

The fixture owns only current-day `behavior_records` whose window title starts with `qa-zc024004-private-` inside one bounded epoch range.
The fixture never deletes or updates a non-owned row.
The fixture requires the supported isolated ready state to contain no pre-existing behavior rows for the current day so stale-to-current freshness and exact Work increments remain deterministic.
The probe writes every captured comparison snapshot under an explicitly external evidence root.
The probe rejects fixture IDs, private window markers, and private URL markers in Accessibility output.

## Static verifier checks

Run these before packaging.

```sh
FIXTURE="$PWD/Scripts/qa-zc024004-live-refresh-fixture.sh"
PROBE="$PWD/Scripts/qa-zc024004-live-refresh-ax-probe.swift"
"$FIXTURE" self-test
swift "$PROBE" --self-test
swiftc -typecheck "$PROBE"
Scripts/verify-zc-024-004-live-today-refresh-static.sh
git diff --check ed5d07a363e0f64049c07b0e1d309d754caa035b
```

Do not put build transcripts, screenshots, AX snapshots, temporary databases, or package staging under the repository.
Use an external build and evidence root when the signed candidate is packaged by the release owner.

```sh
REPOSITORY="$(pwd -P)"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
EVIDENCE_ROOT="/private/tmp/zoid-zc024004-evidence/$EXPECTED_SIGNED_COMMIT"
case "$EVIDENCE_ROOT/" in "$REPOSITORY/"*) echo "evidence root must be external" >&2; exit 1;; esac
rm -rf -- "$EVIDENCE_ROOT"
mkdir -p "$EVIDENCE_ROOT"
```

## Bind one exact installed candidate

Use a clean signed QA package with an isolated QA root and the supported 12-of-12 ready state.
Grant Accessibility permission to the terminal running the probe.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc024004-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
INFO_PLIST="$APP/Contents/Info.plist"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor ed5d07a363e0f64049c07b0e1d309d754caa035b "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor 1bb3c27866bc3acbfd449d680371b0b340710738 "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor fa95aeab65fb23a1971e6a7c3464ae87d51febf7 "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor 69b16a3335867a43ef8ae7904705a3d40f3e738f "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor d36cedc7da6146b4c8982c15733a3899e0d57013 "$EXPECTED_SIGNED_COMMIT"
Scripts/verify-zc-024-004-live-today-refresh-static.sh
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
test "$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")" = "$QA_ROOT"
test -x "$APP_EXECUTABLE"
test -f "$DATABASE"
export ZOID_666_QA_ZC024004_DAY="$(date '+%Y-%m-%d')"
export ZOID_666_QA_ZC024004_BASE_EPOCH="$(( $(date '+%s') - 2100 ))"
```

Use this bounded helper after every open to bind the process to the exact installed executable.

```sh
resolve_installed_pid() {
  local attempt candidate executable
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
      executable="$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
      if test "$executable" = "$APP_EXECUTABLE"; then printf '%s\n' "$candidate"; return 0; fi
    done
    sleep 0.2
  done
  return 1
}
```

## Establish the visible baseline

Keep the helper registered so each refresh exercises the normal XPC snapshot boundary.
Stop the exact installed app before preparing the fixture.

```sh
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
  lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && kill "$candidate"
done
"$FIXTURE" prepare "$DATABASE"
open "$APP" --args --qa-open-main
PID="$(resolve_installed_pid)"
swift "$PROBE" --pid "$PID" --command window --evidence-root "$EVIDENCE_ROOT"
sleep 20
swift "$PROBE" --pid "$PID" --command capture --evidence-root "$EVIDENCE_ROOT" --output baseline.json
```

The main window must remain open for every live phase below.
The baseline contains a stale Screenwatch row and a bounded Work total.

## Prove automatic visible refresh while Today remains open

```sh
"$FIXTURE" advance-live "$DATABASE"
sleep 20
swift "$PROBE" --pid "$PID" --command expect-change --evidence-root "$EVIDENCE_ROOT" \
  --from baseline.json --output live.json --require-source-change
```

This phase must increase visible Working minutes and change visible Screenwatch freshness from stale to current without a click, manual refresh, window close, or relaunch.

## Prove refresh pauses in Settings and restarts on Today return

```sh
swift "$PROBE" --pid "$PID" --command navigate-settings --evidence-root "$EVIDENCE_ROOT"
"$FIXTURE" advance-settings "$DATABASE"
sleep 20
swift "$PROBE" --pid "$PID" --command navigate-today --evidence-root "$EVIDENCE_ROOT"
swift "$PROBE" --pid "$PID" --command expect-stable --evidence-root "$EVIDENCE_ROOT" --from live.json
sleep 20
swift "$PROBE" --pid "$PID" --command expect-change --evidence-root "$EVIDENCE_ROOT" \
  --from live.json --output settings-return.json
```

The immediate comparison after returning to Today proves that Settings did not refresh the hidden Today surface.
The delayed comparison proves the loop restarted after Today became selected again.

## Prove refresh pauses in the background and restarts in the foreground

```sh
osascript -e 'tell application "Finder" to activate'
"$FIXTURE" advance-background "$DATABASE"
sleep 20
swift "$PROBE" --pid "$PID" --command expect-stable --evidence-root "$EVIDENCE_ROOT" --from settings-return.json
osascript -e "tell application id \"$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")\" to activate"
swift "$PROBE" --pid "$PID" --command expect-stable --evidence-root "$EVIDENCE_ROOT" --from settings-return.json
sleep 20
swift "$PROBE" --pid "$PID" --command expect-change --evidence-root "$EVIDENCE_ROOT" \
  --from settings-return.json --output foreground.json
```

The background comparison must remain stable for longer than one 15-second refresh interval.
The foreground comparison must then increase visible Working minutes without manual refresh.

## Prove ordinary relaunch

Advance the source while the app is stopped, then use an ordinary LaunchServices open with no QA foreground argument.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" advance-relaunch "$DATABASE"
open "$APP"
PID="$(resolve_installed_pid)"
swift "$PROBE" --pid "$PID" --command window --evidence-root "$EVIDENCE_ROOT"
sleep 20
swift "$PROBE" --pid "$PID" --command expect-change --evidence-root "$EVIDENCE_ROOT" \
  --from foreground.json --output relaunch.json
```

The ordinary relaunch must restore exactly one visible main window and show the newer source state.

## Cleanup and visible restoration

Cleanup removes only the fixture namespace while the signed app remains open.

```sh
"$FIXTURE" cleanup "$DATABASE"
sleep 20
swift "$PROBE" --pid "$PID" --command expect-restore --evidence-root "$EVIDENCE_ROOT" \
  --from relaunch.json --output restored.json
test "$(sqlite3 -batch -noheader "$DATABASE" \
  "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$ZOID_666_QA_ZC024004_DAY' AND window_title LIKE 'qa-zc024004-private-%';")" = 0
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
```

Do not mark ZC-024-004 usable end to end unless every automatic-change, Settings pause, foreground pause, ordinary-relaunch, privacy, database-cleanup, and visible-restoration assertion passes against the same signed identity.
