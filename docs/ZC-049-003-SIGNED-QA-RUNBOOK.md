# ZC-049-003 Signed QA Runbook

This runbook verifies that stale or invalid Screenwatch evidence withdraws a gaming-drift prompt and its fixture notification.
It verifies that fresh evidence can recover one new prompt for the same session without weakening explicit user dismissal, cooldown, or daily-cap gates.

## Candidate boundary

The canonical base is `ede57d92e568904495118b8a6cccdfed6cabde4f`.
The candidate must be one direct child that adds only the five ZC-049-003 QA tooling files.
`Scripts/qa-zc049003-signed-preflight.sh` rejects any other lineage or file scope.

## Non-runtime gates

Run these checks from the exact candidate checkout.

```zsh
set -euo pipefail
zsh -n Scripts/qa-zc049003-stale-prompt-suppression-fixture.sh
zsh -n Scripts/qa-zc049003-signed-preflight.sh
zsh -n Scripts/verify-zc-049-003-stale-prompt-suppression-static.sh
swiftc -typecheck Scripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift
Scripts/qa-zc049003-stale-prompt-suppression-fixture.sh self-test
swift Scripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift --self-test
Scripts/verify-zc-049-003-stale-prompt-suppression-static.sh --self-test
Scripts/qa-zc049003-signed-preflight.sh --self-test
swift test --filter GamingDriftPromptServiceTests
```

## Prepare isolated signed QA

Use a signed QA package with an isolated QA root, granted fixture notifications, a current work window, completed behavior baseline, zero unlocked gaming minutes, and one incomplete priority task.
Never use the normal user database or normal notification center.
Stop both the app and helper before every fixture mutation or restoration.

```zsh
set -euo pipefail
export APP="$PWD/dist/Zoid Coach.app"
export QA_ROOT="${ZOID_COACH_QA_ROOT:?}"
export DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
export OS_STATE="$QA_ROOT/OS Fixtures/state.json"
export EXPECTED_COMMIT="$(git rev-parse HEAD)"
export DAY="$(date +%F)"
export BACKUP="$(mktemp -d "${TMPDIR:-/tmp}/zc049003-backup.XXXXXX")"
export GUARD="$(mktemp "${TMPDIR:-/tmp}/zc049003-guard.XXXXXX")"
export FIXTURE="$PWD/Scripts/qa-zc049003-stale-prompt-suppression-fixture.sh"
export PROBE="$PWD/Scripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift"
export PREFLIGHT="$PWD/Scripts/qa-zc049003-signed-preflight.sh"

"$FIXTURE" snapshot "$DATABASE" "$OS_STATE" "$BACKUP"
"$FIXTURE" seed-initial "$DATABASE" "$OS_STATE" "$DAY"
```

## Initial prompt and ordinary restart

Open the signed app and let the signed helper register against the same isolated database.
Open Today Decisions and prove the initial prompt before any stale transition.

```zsh
set -euo pipefail
open "$APP"
APP_PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$OS_STATE" "$EXPECTED_COMMIT" --expected-app-pid "$APP_PID"
"$FIXTURE" assert-initial "$DATABASE" "$OS_STATE" "$DAY"
swift "$PROBE" --pid "$APP_PID" --phase initial
```

Quit the app normally and restart the helper through its ordinary launchd lifecycle.
Open the app normally, reopen Today Decisions, rerun the preflight, and rerun both initial assertions.
Do not continue if the initial prompt is absent because every later transition would otherwise be a false pass.

## Stale withdrawal and notification removal

Stop the app and helper, stage future-invalid Screenwatch evidence, and restart the helper normally.
Wait for one normal helper reconciliation cycle before reopening Today Decisions.

```zsh
set -euo pipefail
"$FIXTURE" invalidate-evidence "$DATABASE" "$OS_STATE" "$DAY"
open "$APP"
APP_PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$OS_STATE" "$EXPECTED_COMMIT" --expected-app-pid "$APP_PID"
"$FIXTURE" assert-stale "$DATABASE" "$OS_STATE" "$DAY"
swift "$PROBE" --pid "$APP_PID" --phase stale
```

The database assertion requires the exact `system` plus `screenwatch_evidence_invalid` resolution pair.
The OS fixture assertion requires the original scheduled or delivered notification to be absent.
The AX assertion requires the original decision to be non-actionable while its truthful history remains visible.
Quit and ordinarily restart both processes, then rerun the stale assertions to prove persistence.

## Fresh same-session recovery

Stop both processes and restore the latest observation to the current time without changing the earlier session rows.
Restart the helper normally and wait for one normal reconciliation cycle.

```zsh
set -euo pipefail
"$FIXTURE" refresh-evidence "$DATABASE" "$OS_STATE" "$DAY"
open "$APP"
APP_PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$OS_STATE" "$EXPECTED_COMMIT" --expected-app-pid "$APP_PID"
"$FIXTURE" assert-fresh "$DATABASE" "$OS_STATE" "$DAY"
FRESH_PROMPT_ID="$(sqlite3 -batch -noheader "$DATABASE" \
  "SELECT id FROM prompt_episodes WHERE id != 'qa-zc049003-initial' AND prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented') ORDER BY created_at_utc DESC LIMIT 1;")"
[[ -n "$FRESH_PROMPT_ID" ]]
swift "$PROBE" --pid "$APP_PID" --phase fresh --prompt-id "$FRESH_PROMPT_ID"
```

The fixture requires exactly one unresolved replacement using the original logical decision key and exactly one matching fixture notification.

## Preserve dismissal, cooldown, and daily cap

Dismiss the fresh prompt from Today and confirm that its history appears.
Capture the durable prompt counts only after the user-origin dismissal is visible in the database.

```zsh
set -euo pipefail
"$FIXTURE" capture-guard "$DATABASE" "$GUARD"
swift "$PROBE" --pid "$APP_PID" --phase preserved --prompt-id "$FRESH_PROMPT_ID"
```

Keep evidence current and allow another normal helper cycle during the configured cooldown.
Rerun `assert-guard-preserved` and the preserved AX probe after an ordinary app and helper restart.
Repeat with the QA policy daily prompt cap already consumed.

```zsh
set -euo pipefail
"$FIXTURE" assert-guard-preserved "$DATABASE" "$GUARD"
swift "$PROBE" --pid "$APP_PID" --phase preserved --prompt-id "$FRESH_PROMPT_ID"
```

The guard fails if any new gaming prompt appears, if the user dismissal changes origin, or if an unresolved prompt reappears.
The focused `GamingDriftPromptServiceTests` independently distinguish cooldown and daily-cap suppression from same-session system recovery.

## Privacy and exact restoration

Every AX phase rejects the private application, window, and URL sentinels embedded only in fixture evidence and prompt payload.
Stop the app and helper before restoration.

```zsh
set -euo pipefail
"$FIXTURE" restore "$DATABASE" "$OS_STATE" "$BACKUP"
rm -rf "$BACKUP"
rm -f "$GUARD"
```

Restoration fails unless the isolated database and OS fixture state match their saved SHA-256 bytes exactly.
The remaining acceptance work is the signed app and helper journey described above.
