# ZC-041-005 signed QA runbook

This runbook verifies the six-category Daily Review ledger against one exact installed signed candidate.
The product candidate is `330fe53ba2bebb819686a688a961eb3c5a5acf50`.
The signed build may be that commit or a reviewed integration descendant containing the candidate and the namespaced verifier tooling.

The fixture writes only `qa-zc041005-*` corrections, merges, and private-marker behavior rows in one bounded epoch range on the current local day.
Raw fixture observations remain Unknown or Gaming.
Persisted corrections create the effective Work truth.
Persisted merges prove the chosen-left truth contract in both directions.

## Install and bind the signed runtime

Install a clean QA package under an isolated install root and QA root.
Grant Accessibility permission to the terminal running the probe.
Establish the repository's supported 12-of-12 QA ready state before this post-onboarding scenario.
Do not use a product launch argument or product backdoor.

Set the exact paths and full signed commit.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc041005-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc041005-work-categories-fixture.sh"
PROBE="$PWD/Scripts/qa-zc041005-work-categories-ax-probe.swift"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
```

Verify the exact installed signature, package mode, build identity, and candidate ancestry.

```sh
test "$(git rev-parse "$EXPECTED_SIGNED_COMMIT")" = "$EXPECTED_SIGNED_COMMIT"
git merge-base --is-ancestor 330fe53ba2bebb819686a688a961eb3c5a5acf50 "$EXPECTED_SIGNED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT" --require-clean
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
test -x "$APP_EXECUTABLE"
test "$(plutil -extract ZoidCoachQARunRoot raw -o - "$APP/Contents/Info.plist")" = "$QA_ROOT"
```

Stop the registered helper and app before replacing the isolated root with the supported ready state.
Register the helper again so it recreates the production schema in the exact database.

```sh
"$APP_EXECUTABLE" --qa-unregister-agent
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
"$APP_EXECUTABLE" --qa-register-agent
open "$APP"
```

Resolve the one PID whose executable path belongs to the installed bundle.

```sh
for attempt in {1..40}; do
  PID="$(for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
    lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && printf '%s\n' "$candidate"
  done | head -n 1)"
  test -n "$PID" && break
  sleep 0.2
done
test -n "$PID"
swift "$WINDOW_PROBE" "$PID" --expect-today
```

The Today assertion proves onboarding is complete and the normal Reviews navigation is available.

## Prove the honest non-work empty state

Quit the app before fixture mutation.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare-empty "$DATABASE"
"$FIXTURE" assert-empty "$DATABASE"
open "$APP"
```

Resolve `PID` again with the same installed-executable loop.
Leave the normal Today window visible.
The probe presses the normal `Reviews` sidebar button and scrolls at most 16 pages to the ledger.

```sh
for attempt in {1..40}; do
  PID="$(for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
    lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && printf '%s\n' "$candidate"
  done | head -n 1)"
  test -n "$PID" && break
  sleep 0.2
done
swift "$PROBE" --pid "$PID" --phase empty
```

The empty phase requires `NO CORRECTED WORK TO CATEGORIZE`.
It requires all six category rows to be absent even though three persisted Gaming observations exist.

## Prove all six corrected-work category totals

Quit the app, clean the empty fixture, and prepare the full corrected-session fixture.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
open "$APP"
```

Resolve `PID` again with the installed-executable loop and leave Today visible.

```sh
for attempt in {1..40}; do
  PID="$(for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
    lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && printf '%s\n' "$candidate"
  done | head -n 1)"
  test -n "$PID" && break
  sleep 0.2
done
swift "$PROBE" --pid "$PID" --phase categories
```

The signed ledger must expose exactly these accessible rows:

- Deep work: 2 minutes.
- Creative work: 3 minutes.
- Research: 4 minutes.
- Communication: 5 minutes.
- Administration: 6 minutes.
- Uncategorized work: 8 minutes.

The six rows sum to 28 corrected Work minutes.
The Uncategorized total contains an unknown app, mixed recognized categories, partially unknown evidence, and a Work-left merge containing a Gaming observation.
The non-work-left merge and three standalone Gaming minutes remain excluded.
The detail copy must explain that saved corrected-session classification and the chosen left session after a merge control the totals.

The probe recursively scans the ledger and rejects fixture IDs, private window and URL markers, and every raw fixture application name.

## Prove store and UI persistence after relaunch

Quit and relaunch the same installed bundle without touching the database.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP"
```

Resolve `PID` again through the installed-executable loop.
Leave Today visible and repeat the category phase.

```sh
for attempt in {1..40}; do
  PID="$(for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
    lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" && printf '%s\n' "$candidate"
  done | head -n 1)"
  test -n "$PID" && break
  sleep 0.2
done
swift "$PROBE" --pid "$PID" --phase categories
"$FIXTURE" assert-relaunch "$DATABASE"
```

The repeated six-row result proves the signed app reconstructed the same effective sessions from persisted raw observations, corrections, and chosen-left merges after store reopen.

## Cleanup

Quit the app before cleanup.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup "$DATABASE"
```

Cleanup removes only namespaced corrections, merges, and private-marker observations.
Do not mark ZC-041-005 fully usable unless the empty phase, six-row phase, relaunch phase, privacy scan, database assertions, and cleanup all pass against the same signed identity.
