# ZC-035-011 signed QA runbook

This runbook proves that unresolved gaming-drift coaching is fully usable, fresh aligned work withdraws it through the running product, an ordinary relaunch stays observation-only, and later fresh gaming creates one new coaching decision.
Every phase runs against one exact installed signed Zoid 666 candidate and one isolated app/helper database.
The fixture uses production policy, plan, behavior, baseline, and prompt schemas.
It never injects a Today snapshot or fabricates a rendered SwiftUI state.
The candidate merges reviewed product and tooling lineage tip `f950272b94c2fa4f3290aa6d5cb2437e2a9996a1` onto canonical base `76149705b3a301fafa832102a2e599358a16ff25`.
The preflight binds both exact parents, the reviewed seven-file scope, and the two original stable patch IDs.

## Bind the exact candidate

Grant Accessibility permission to the terminal that runs the probe.
Start from a clean worktree containing the complete reviewed ZC-035-011 lineage.
Keep generated evidence outside the repository.

```sh
REPOSITORY="$PWD"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc035011-runtime"
INSTALL_ROOT="/private/tmp/zoid-666-zc035011-install"
EVIDENCE_ROOT="/private/tmp/zoid-zc035011-evidence/$EXPECTED_SIGNED_COMMIT"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
FIXTURE="$REPOSITORY/Scripts/qa-zc035011-gaming-observation-fixture.sh"
PROBE="$REPOSITORY/Scripts/qa-zc035011-gaming-observation-ax-probe.swift"
PREFLIGHT="$REPOSITORY/Scripts/qa-zc035011-signed-preflight.sh"
READY_STATE="$REPOSITORY/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$REPOSITORY/Scripts/fixtures/zc-035-011-gaming-observation-ready-state.json"
INSTALLER="$REPOSITORY/Scripts/install-signed-qa-runtime.sh"
UNINSTALLER="$REPOSITORY/Scripts/uninstall-signed-qa-runtime.sh"
test "$(git rev-parse HEAD)" = "$EXPECTED_SIGNED_COMMIT"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
git merge-base --is-ancestor 76149705b3a301fafa832102a2e599358a16ff25 "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor f950272b94c2fa4f3290aa6d5cb2437e2a9996a1 "$EXPECTED_SIGNED_COMMIT"
mkdir -p "$EVIDENCE_ROOT"
exec > >(tee -a "$EVIDENCE_ROOT/runbook.log") 2>&1
"$FIXTURE" self-test
swift "$PROBE" --self-test
"$PREFLIGHT" --self-test
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
  "$INSTALLER"
```

The installer creates the signed package and proves LaunchServices, signing, the helper path, the writable database, and the prompt-timeline XPC surface.
Stop the installed helper and foreground app before replacing the QA root with the supported ready state.

```sh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
  if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
FOREGROUND_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --require-helper-unregistered)"
printf '%s\n' "$FOREGROUND_OUTPUT"
PID="$(printf '%s\n' "$FOREGROUND_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-qa-open-main --expected-app-pid "$PID"
```

Do not continue unless the same foreground PID remains alive, the installed helper holds the exact isolated database open, and package identity matches `EXPECTED_SIGNED_COMMIT`.

Use these bounded helpers for ordinary relaunch and database-state polling.

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
wait_for_fixture() {
  local command="$1"
  for attempt in {1..40}; do
    if "$FIXTURE" "$command" "$DATABASE"; then return 0; fi
    sleep 0.5
  done
  return 1
}
wait_for_later_gaming() {
  for attempt in {1..130}; do
    if "$FIXTURE" advance-gaming "$DATABASE"; then return 0; fi
    sleep 5
  done
  return 1
}
```

## Unresolved coaching is visible and usable

Prepare a complete baseline, a zero-minute gaming allowance, one unfinished priority objective, and a fresh ten-minute gaming session.
The helper must consume those durable inputs through its normal cycle and create one prompt.

```sh
"$FIXTURE" prepare-gaming "$DATABASE"
wait_for_fixture assert-coaching
stop_app
ordinary_open
swift "$PROBE" --pid "$PID" --phase coaching
screencapture -x "$EVIDENCE_ROOT/coaching.png"
```

The accessible Today decision must explain the ten observed Steam minutes without claiming intent.
Return to task, recovery sprint, five more minutes, continue intentionally, and dismiss must all be usable controls.
The raw private window title and URL must remain absent from the complete Accessibility tree.

## Fresh aligned work withdraws coaching

Insert one newer certain Work observation while the coaching decision remains unresolved.
The running helper must withdraw the prompt on its next ordinary cycle with system origin and `screenwatch_evidence_invalid` reason.

```sh
"$FIXTURE" advance-aligned "$DATABASE"
wait_for_fixture assert-observation
stop_app
ordinary_open
swift "$PROBE" --pid "$PID" --phase observation
screencapture -x "$EVIDENCE_ROOT/aligned-observation.png"
```

The UI must contain no waiting decision or actionable stale coaching.
It must retain exactly one dismissed history row so the system action is transparent rather than silently erased.

## Ordinary relaunch remains observation-only

Quit and ordinarily reopen the same signed app without changing the database.

```sh
stop_app
ordinary_open
"$FIXTURE" assert-observation "$DATABASE"
swift "$PROBE" --pid "$PID" --phase observation
screencapture -x "$EVIDENCE_ROOT/observation-relaunch.png"
```

The ordinary launch must not retain `--qa-open-main`.
It must restore exactly one visible main window and the same observation-only decision history.

## Later fresh gaming coaches again

Keep the signed app and helper running until ten real minutes have elapsed after the aligned-work observation.
The fixture fails closed before the new ten-minute session can truthfully fit after that boundary and also fails if the freshness window is missed.
Run it every five seconds until it accepts the later session.

```sh
wait_for_later_gaming
wait_for_fixture assert-recoaching
stop_app
ordinary_open
swift "$PROBE" --pid "$PID" --phase recoaching
screencapture -x "$EVIDENCE_ROOT/recoaching.png"
```

The UI must show exactly one new waiting decision and exactly one dismissed history row.
The new decision must use a different durable prompt ID, preserve the uncertainty explanation, expose usable recovery controls, and keep raw private evidence absent.

## Cleanup and restoration

Stop both exact installed processes before restoring the fixture-owned policy payload and deleting every namespaced row.
Then remove the isolated signed runtime and prove no app, helper registration, database, or install root remains.

```sh
stop_app
"$APP_EXECUTABLE" --qa-unregister-agent
"$FIXTURE" cleanup "$DATABASE"
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
  "$UNINSTALLER"
test ! -e "$APP"
test ! -e "$QA_ROOT"
test ! -e "$INSTALL_ROOT"
! launchctl print "gui/$(id -u)/com.zoidcoach.agent.qa" >/dev/null 2>&1
```

Do not mark ZC-035-011 fully usable unless every package, runtime identity, database, Accessibility, privacy, ordinary relaunch, distinct recoaching, cleanup, and removal assertion passes against one exact signed commit.
