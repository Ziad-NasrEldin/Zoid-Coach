# ZC-056-001 signed locale-duration QA runbook

This runbook verifies that the primary menu-bar task summary and its accessibility actions format minute durations for the locale of one exact installed signed candidate.
The product candidate is `2e6ee58663b5d4991d7bd7ef10e529e92bdaf34b`.
The signed integration commit must contain that candidate.
Run every command from the repository containing the signed integration commit.

The fixture owns only the `qa-zc056001-locale-duration` task namespace.
It refuses to replace a foreign active task and removes only its own rows.
The AX proof runs the same installed bundle under en-US and Arabic Egypt locales.
This proves both ordinary Latin formatting and a non-English locale with localized digits and unit names.

## Preconditions

Install a clean signed QA package under an isolated QA root.
Grant Accessibility permission to the terminal that runs the probe.
Close every unrelated copy of Zoid 666.
Do not continue after any failed assertion.

Set the exact installed paths and full signed integration commit.
The database must be the SQLite database embedded in the installed QA bundle runtime root.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
DATABASE="/private/tmp/zc056001/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_INTEGRATION_COMMIT"
FIXTURE="$PWD/Scripts/qa-zc056001-locale-duration-fixture.sh"
PROBE="$PWD/Scripts/qa-zc056001-locale-duration-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc056001-signed-preflight.sh"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
TASK_TITLE="Review localized duration copy"
ENGLISH_ESTIMATE="45 min"
ENGLISH_UNIT=" min"
ENGLISH_BREAK="15 minutes"
ARABIC_ESTIMATE="٤٥ د"
ARABIC_UNIT=" د"
ARABIC_BREAK="١٥ دقيقة"
PID=""

cleanup() {
  if test -n "${PID:-}" && kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
  fi
  "$FIXTURE" cleanup --database "$DATABASE" || true
}
trap cleanup EXIT

"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test
```

The self-tests reject fallback spacing, missing wide accessibility duration copy, unsafe fixture cleanup, malformed identity, and incomplete runbook sequencing.

## Seed one deterministic active task

The app must be stopped before fixture mutation.
The fixture creates one 45-minute main-objective estimate and one open active interval that the production snapshot path reads.

```sh
set -euo pipefail
"$FIXTURE" seed --database "$DATABASE"
"$FIXTURE" verify --database "$DATABASE"
```

## Prove en-US compact and wide duration copy

Launch the installed bundle with an explicit en-US locale and the supported QA foreground argument.
Bind the exact process, signed commit, locale arguments, and isolated database before inspecting UI.

```sh
set -euo pipefail
open "$APP" --args -AppleLocale en_US -AppleLanguages "(en)" --qa-open-main
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" en_US "$PID"
swift "$PROBE" \
  --pid "$PID" \
  --task-title "$TASK_TITLE" \
  --compact-estimate "$ENGLISH_ESTIMATE" \
  --compact-unit "$ENGLISH_UNIT" \
  --wide-break-duration "$ENGLISH_BREAK"
```

The menu summary must retain the separate estimate and tracked meanings.
The break action must expose a wide 15-minute duration through accessibility copy.

## Prove Arabic compact and wide duration copy

Terminate the en-US process before changing locale.
Relaunch the same installed bundle and same database under Arabic Egypt.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
open "$APP" --args -AppleLocale ar_EG -AppleLanguages "(ar)" --qa-open-main
for _ in {1..80}; do
  PID="$(pgrep -x "$APP_EXECUTABLE_NAME" | head -n 1 || true)"
  test -n "$PID" && break
  sleep 0.1
done
test -n "$PID"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" ar_EG "$PID"
swift "$PROBE" \
  --pid "$PID" \
  --task-title "$TASK_TITLE" \
  --compact-estimate "$ARABIC_ESTIMATE" \
  --compact-unit "$ARABIC_UNIT" \
  --wide-break-duration "$ARABIC_BREAK"
```

The Arabic phase must expose Arabic-Indic digits and localized minute units.
The probe rejects an English ASCII fallback even if the semantic labels remain present.

## Cleanup and acceptance

Stop the app and prove the fixture namespace is empty.

```sh
set -euo pipefail
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
PID=""
"$FIXTURE" cleanup --database "$DATABASE"
"$FIXTURE" verify-clean --database "$DATABASE"
trap - EXIT
```

Accept ZC-056-001 only when both locale phases pass against the same signed commit and isolated database.
Do not infer installed-app acceptance from unit or static checks alone.
