# ZC-042-001 signed QA runbook

This runbook verifies that Daily Review keeps observed facts, user context, and possible hypotheses visibly separate against one exact installed signed candidate.
The signed commit must contain candidate `8cc9f2187e74787c183e444140b8696b8e37e52f` and the bounded limited-evidence correction.
Every phase uses the production `behavior_records` and `daily_reviews` schemas in one isolated QA root.

## Bind the signed runtime

Install a clean signed QA package under isolated runtime and install roots.
Grant Accessibility permission to the terminal running the probes.
Set these values from the repository containing the exact signed commit.

```sh
APP="/absolute/path/to/Zoid 666 QA E2E.app"
QA_ROOT="/private/tmp/zoid-666-zc042001-runtime"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc042001-evidence-layers-fixture.sh"
PROBE="$PWD/Scripts/qa-zc042001-evidence-layers-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc042001-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
WINDOW_PROBE="$PWD/Scripts/qa-window-content-probe.swift"
"$FIXTURE" self-test
"$PREFLIGHT" --self-test
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
resolve_app_pid() {
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
```

The self-tests reject helper-before-foreground ordering, QA foreground arguments during relaunch, invalid fixture ownership, ambiguous main windows, and incomplete layer contracts.

Stop the exact installed app and helper before preparing the supported 12-of-12 ready state.
Launch the initial main window with the packaged QA argument while the helper remains unregistered.

```sh
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
swift "$WINDOW_PROBE" "$PID" --expect-today
```

Do not continue unless the same foreground PID remains alive and the installed helper holds the exact isolated database open.

## Positive persisted evidence

Quit the app, prepare positive production-schema evidence, and relaunch through ordinary scene restoration.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare-positive "$DATABASE"
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase positive
"$FIXTURE" assert-positive "$DATABASE"
```

Acceptance requires exactly three accessible layers.
Observed facts must report only persisted counts and durations.
Context must state the Unknown minute and the existence, but never the contents, of the personal note.
The possible hypothesis must retain uncertainty language and must not appear as fact.

Prove persistence by closing and ordinarily relaunching the same signed bundle without changing the database.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase positive
"$FIXTURE" assert-positive "$DATABASE"
```

## Limited persisted evidence

Replace only the namespaced fixture rows with Unknown-only evidence and a private personal note.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare-limited "$DATABASE"
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase limited
"$FIXTURE" assert-limited "$DATABASE"
```

The context layer must expose the Unknown limit explicitly.
The hypothesis layer must state that no possible explanation was generated because evidence is insufficient.
It must never claim that Work was the largest category when persisted Work is zero.

## Honest empty evidence

Remove the namespaced evidence and ordinarily relaunch once more.

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" prepare-empty "$DATABASE"
open "$APP"
PID="$(resolve_app_pid)"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" \
  --require-ordinary-open --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase empty
"$FIXTURE" assert-empty "$DATABASE"
```

The empty facts layer must say that no covered activity or completed task was recorded.
The hypothesis layer must remain explicitly insufficient rather than inventing an explanation.

## Cleanup and acceptance boundary

```sh
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
"$FIXTURE" cleanup "$DATABASE"
```

Do not mark ZC-042-001 fully usable unless all signed identity checks, four ordinary relaunch bindings, exact three-layer assertions, persistence checks, empty and limited states, privacy scans, and cleanup pass against the same installed commit and database.
