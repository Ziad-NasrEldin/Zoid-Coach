# ZC-055-004 Signed QA Runbook

This runbook verifies discoverable keyboard-only coaching actions in Today Decisions.
It proves that only the first actionable prompt owns global shortcuts, destructive actions retain their existing confirmation flow, dismissal affects only the intended prompt, private payload data stays hidden, and state survives an ordinary restart.

## Candidate boundary

The canonical base is `ede57d92e568904495118b8a6cccdfed6cabde4f`.
The candidate must be one direct child containing exactly the eight ZC-055-004 files.

## Non-runtime gates

```zsh
set -euo pipefail
swift test --filter PromptKeyboardShortcutTests
zsh -n Scripts/qa-zc055004-coaching-keyboard-fixture.sh
zsh -n Scripts/qa-zc055004-signed-preflight.sh
zsh -n Scripts/verify-zc-055-004-coaching-keyboard-static.sh
swiftc -typecheck Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift
Scripts/qa-zc055004-coaching-keyboard-fixture.sh self-test
swift Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift --self-test
Scripts/verify-zc-055-004-coaching-keyboard-static.sh --self-test
Scripts/qa-zc055004-signed-preflight.sh --self-test
```

## Prepare isolated signed QA

Use only a signed QA package and isolated QA root.
Stop the app and helper before fixture mutation or restoration.

```zsh
set -euo pipefail
export APP="$PWD/dist/Zoid Coach.app"
export QA_ROOT="${ZOID_COACH_QA_ROOT:?}"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export EXPECTED_COMMIT="$(git rev-parse HEAD)"
export BACKUP="$(mktemp "${TMPDIR:-/tmp}/zc055004-backup.XXXXXX")"
rm -f "$BACKUP"
export FIXTURE="$PWD/Scripts/qa-zc055004-coaching-keyboard-fixture.sh"
export PROBE="$PWD/Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift"
export PREFLIGHT="$PWD/Scripts/qa-zc055004-signed-preflight.sh"

"$FIXTURE" snapshot "$DATABASE" "$BACKUP"
"$FIXTURE" seed "$DATABASE"
```

## Ready keyboard state

Open the app normally and open Today Decisions without using a pointer.

```zsh
set -euo pipefail
open "$APP"
PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_COMMIT" --expected-app-pid "$PID"
"$FIXTURE" assert-ready "$DATABASE"
swift "$PROBE" --pid "$PID" --phase ready
```

Confirm that the primary coaching row visibly shows `⌥⌘R`, `⌥⌘K`, and `⌥⌘D` among its shortcut labels.
Confirm that the secondary row shows no duplicate global shortcut labels.
Quit and reopen the app normally, reopen Today Decisions, and repeat the ready probe.

## Destructive keyboard route

With Today Decisions visible, press Option Command K.
Do not click the Mark blocked button.

```zsh
set -euo pipefail
swift "$PROBE" --pid "$PID" --phase blocked-sheet
```

The probe requires the same blocked-reason sheet and input used by pointer activation.
Cancel the sheet with Escape and confirm the coaching decision remains waiting.

## Keyboard dismissal

With the primary row visible, press Option Command D.
Do not click Dismiss.

```zsh
set -euo pipefail
"$FIXTURE" assert-dismissed "$DATABASE"
swift "$PROBE" --pid "$PID" --phase dismissed
```

The fixture requires a user-origin dismissal for the primary prompt and an untouched unresolved secondary prompt.
Quit and reopen the app normally, reopen Today Decisions, and repeat the dismissed assertions.

## Privacy and exact restoration

Every AX phase rejects the private fixture payload sentinel.
Stop the app and helper before restoring the database.

```zsh
set -euo pipefail
"$FIXTURE" restore "$DATABASE" "$BACKUP"
rm -f "$BACKUP" "$BACKUP.sha256"
```

Restoration fails unless the isolated database matches the saved SHA-256 bytes exactly.
The remaining acceptance work is the signed keyboard-only app and helper journey above.
