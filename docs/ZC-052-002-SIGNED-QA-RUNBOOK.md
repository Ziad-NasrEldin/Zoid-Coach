# ZC-052-002 signed QA runbook

This runbook proves that Local System Diagnostics tells the user exactly which actions are available, read-only, or temporarily unavailable when local storage changes state.
The reviewed candidate is bound directly to canonical base `7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b`.
It preserves product commit `141906e6f4315f09f160e891985fb772909454e0` with patch ID `eea4bee3990884b7c018b1f53a230d904e7a0f75` and tooling commit `4675cc1d017bcdc8d5d5b6443767568762eb1cee` with patch ID `6c74d693ad887ef854847fb87aa5df89a96756cf`.
The final commit changes only immutable lineage bindings in the preflight, static verifier, and this runbook.
Every phase uses one exact installed signed Zoid 666 candidate and one isolated QA root.
The helper remains unregistered while the fixture replaces the isolated database path.
The fixture captures and later restores the exact original database, WAL, and SHM presence and bytes.
It never operates outside a `/private/tmp` Zoid 666 QA database layout.

## Bind the exact candidate

Grant Accessibility permission to the terminal that runs the probe.
Do not start this run while another signed QA lane owns the installed-app runtime.
Keep generated evidence outside the repository.

```sh
REPOSITORY="$PWD"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc052002-runtime"
INSTALL_ROOT="/private/tmp/zoid-666-zc052002-install"
EVIDENCE_ROOT="/private/tmp/zoid-zc052002-evidence/$EXPECTED_SIGNED_COMMIT"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
BACKUP_ROOT="$QA_ROOT/.zc052002-original-bytes"
FIXTURE="$REPOSITORY/Scripts/qa-zc052002-local-database-actions-fixture.sh"
PROBE="$REPOSITORY/Scripts/qa-zc052002-local-database-actions-ax-probe.swift"
PREFLIGHT="$REPOSITORY/Scripts/qa-zc052002-signed-preflight.sh"
STATIC="$REPOSITORY/Scripts/verify-zc-052-002-local-database-actions-static.sh"
INSTALLER="$REPOSITORY/Scripts/install-signed-qa-runtime.sh"
UNINSTALLER="$REPOSITORY/Scripts/uninstall-signed-qa-runtime.sh"
test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
mkdir -p "$EVIDENCE_ROOT"
exec > >(tee -a "$EVIDENCE_ROOT/runbook.log") 2>&1
"$STATIC"
"$FIXTURE" --self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
  "$INSTALLER"
```

The installer must finish package, signing, LaunchServices, helper-path, and isolated-database checks.
Stop the exact helper and foreground app before capturing the original storage bytes.

```sh
INFO_PLIST="$APP/Contents/Info.plist"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
  if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
! launchctl print "gui/$(id -u)/com.zoidcoach.agent.qa" >/dev/null 2>&1
"$FIXTURE" capture "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" assert-healthy "$DATABASE" "$BACKUP_ROOT"
```

Use these bounded helpers for exact-process binding and ordinary relaunches.

```sh
resolve_app_pid() {
  for attempt in {1..40}; do
    for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
      if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    sleep 0.25
  done
  return 1
}
stop_app() {
  kill "$PID"
  while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
}
ordinary_open() {
  open "$APP"
  PID="$(resolve_app_pid)"
  "$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
    --require-ordinary-open --expected-app-pid "$PID"
}
```

## Healthy storage names available actions

Open one QA foreground window while the helper remains unregistered.

```sh
open "$APP" --args --qa-open-main
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase healthy --refresh
screencapture -x "$EVIDENCE_ROOT/healthy.png"
```

The Local System card must say `ACTIONS AVAILABLE` and explain that planning, task, coaching, and review changes are available.
It must not show an unavailable-action list or recovery button.
The complete Accessibility tree must contain no raw fixture sentinel or backup path.

Quit and ordinarily reopen without changing storage.

```sh
stop_app
ordinary_open
swift "$PROBE" --pid "$PID" --phase healthy --refresh
screencapture -x "$EVIDENCE_ROOT/healthy-ordinary-relaunch.png"
```

The ordinary process must not retain `--qa-open-main` and must restore one unique main window with the same healthy guidance.

## Readable outdated storage becomes read-only

Replace only the isolated on-disk database path while the foreground process keeps its prior handles.
The new read-only diagnostics connection must observe a valid database whose schema version is one revision behind the signed product.

```sh
"$FIXTURE" set-read-only "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" assert-read-only "$DATABASE" "$BACKUP_ROOT"
swift "$PROBE" --pid "$PID" --phase read-only --refresh --press-retry
screencapture -x "$EVIDENCE_ROOT/read-only.png"
"$FIXTURE" assert-read-only "$DATABASE" "$BACKUP_ROOT"
```

The card must say `READ-ONLY SAFETY` and state that changes are paused while the schema is out of date.
It must name task mutations, settings and coaching writes, gaming adjustments, and review changes as temporarily unavailable.
It must offer `RETRY AFTER RESTART`, explain the restart sequence, and state that failed verification leaves the database unchanged.
Pressing the control must perform only another read-only check and must not migrate, repair, or delete the fixture.

An ordinary relaunch is the advertised recovery path for this state.

```sh
stop_app
ordinary_open
"$FIXTURE" assert-healthy "$DATABASE" "$BACKUP_ROOT"
swift "$PROBE" --pid "$PID" --phase healthy --refresh
screencapture -x "$EVIDENCE_ROOT/read-only-recovered-after-relaunch.png"
```

The normal startup migration must recover the disposable outdated fixture to the current schema before the UI claims actions are available again.

## Missing storage explains unavailable actions

Remove only the isolated database bundle while the foreground process remains alive.

```sh
"$FIXTURE" set-missing "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" assert-missing "$DATABASE" "$BACKUP_ROOT"
swift "$PROBE" --pid "$PID" --phase missing --refresh --press-retry
screencapture -x "$EVIDENCE_ROOT/missing.png"
"$FIXTURE" assert-missing "$DATABASE" "$BACKUP_ROOT"
```

The card must say `ACTIONS UNAVAILABLE`, explain that durable state cannot be safely loaded or recorded, and repeat the three named unavailable-action groups.
It must offer `RETRY STORAGE CHECK` and honestly state that the check performs no database repair or deletion.
The retry must leave the missing path missing.

An ordinary relaunch may safely bootstrap a fresh disposable database.

```sh
stop_app
ordinary_open
"$FIXTURE" assert-healthy "$DATABASE" "$BACKUP_ROOT"
swift "$PROBE" --pid "$PID" --phase healthy --refresh
screencapture -x "$EVIDENCE_ROOT/missing-recovered-after-relaunch.png"
```

The product must not claim recovery until the new database passes integrity and current-schema checks.

## Unverified storage remains fail-closed

Replace only the isolated database path with private non-SQLite bytes.

```sh
"$FIXTURE" set-unverified "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" assert-unverified "$DATABASE" "$BACKUP_ROOT"
swift "$PROBE" --pid "$PID" --phase unverified --refresh --press-retry
screencapture -x "$EVIDENCE_ROOT/unverified.png"
"$FIXTURE" assert-unverified "$DATABASE" "$BACKUP_ROOT"
```

The card must distinguish this state from a missing database by saying that storage could not be verified.
It must keep every storage-backed mutation unavailable, expose the same non-destructive retry guidance, and never reveal the raw private bytes through Accessibility.

Quit and ordinarily reopen against the unchanged unverified fixture.

```sh
stop_app
ordinary_open
swift "$PROBE" --pid "$PID" --phase unverified --refresh --press-retry
screencapture -x "$EVIDENCE_ROOT/unverified-ordinary-relaunch.png"
"$FIXTURE" assert-unverified "$DATABASE" "$BACKUP_ROOT"
```

The ordinary relaunch must keep the state fail-closed if startup cannot safely migrate it.
It must not silently replace, repair, or delete the unverified bytes.

## Exact restoration and cleanup

Stop the exact foreground process before restoring the original captured bundle.

```sh
stop_app
"$FIXTURE" restore "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" assert-restored "$DATABASE" "$BACKUP_ROOT"
"$FIXTURE" cleanup "$DATABASE" "$BACKUP_ROOT"
test ! -e "$BACKUP_ROOT"
ordinary_open
swift "$PROBE" --pid "$PID" --phase healthy --refresh
screencapture -x "$EVIDENCE_ROOT/restored-healthy.png"
stop_app
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
  "$UNINSTALLER"
test ! -e "$APP"
test ! -e "$QA_ROOT"
test ! -e "$INSTALL_ROOT"
! launchctl print "gui/$(id -u)/com.zoidcoach.agent.qa" >/dev/null 2>&1
```

The fixture must prove byte-identical restoration before deleting its backup.
The final ordinary launch must show healthy actions from the restored current-schema database.
The uninstaller must remove the isolated app, helper registration, database root, and install root.

Do not mark ZC-052-002 fully usable unless every exact candidate, package, unique-window, healthy, read-only, missing, unverified, retry, privacy, ordinary-relaunch, byte-restoration, cleanup, and removal assertion passes in one signed run.
