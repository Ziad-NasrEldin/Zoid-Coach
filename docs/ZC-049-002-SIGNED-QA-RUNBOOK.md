# ZC-049-002 Signed QA Runbook

This runbook verifies that limited Screenwatch coverage explicitly tells the user that drift detection is suspended.
It also verifies that the warning disappears when Screenwatch coverage becomes current.

## Immutable candidate

The canonical base is `7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b`.
The product commit is `a492acbae5641bbe41bfcdad93b8e7fb37612bdf`.
The tooling and signed candidate commits are bound by `Scripts/qa-zc049002-signed-preflight.sh` after the lineage commit is created.

## Local gates

Run these checks from a clean checkout of the signed candidate.

```zsh
set -euo pipefail
Scripts/qa-zc049002-coverage-drift-suspension-fixture.sh self-test
swift Scripts/qa-zc049002-coverage-drift-suspension-ax-probe.swift --self-test
Scripts/qa-zc049002-signed-preflight.sh --self-test
swift test --filter BehaviorEvidenceStateTests
swift build -c release
```

## Prepare isolated signed QA

Use an isolated QA root and database.
Do not run these fixture commands against the user's normal Zoid Coach database.

```zsh
set -euo pipefail
export APP="$PWD/dist/Zoid Coach.app"
export DATABASE="${ZOID_COACH_QA_ROOT:?}/Application Support/Zoid Coach/zoid-coach.sqlite3"
export EXPECTED_SIGNED_COMMIT="$(git rev-parse HEAD)"
export DAY="$(date +%F)"
export BACKUP="$(mktemp "${TMPDIR:-/tmp}/zc049002-snapshot.XXXXXX")"
export FIXTURE="$PWD/Scripts/qa-zc049002-coverage-drift-suspension-fixture.sh"
export PROBE="$PWD/Scripts/qa-zc049002-coverage-drift-suspension-ax-probe.swift"
export PREFLIGHT="$PWD/Scripts/qa-zc049002-signed-preflight.sh"

ZOID_COACH_PACKAGE_MODE=qa Scripts/verify-package.sh \
  "$APP" --expected-commit "$EXPECTED_SIGNED_COMMIT"
"$FIXTURE" snapshot "$DATABASE" "$BACKUP" "$DAY"
```

## Verify limited coverage

Quit the app and helper before changing the isolated fixture.
Set limited coverage, open the signed app normally, and open Behavior Evidence from Today.

```zsh
set -euo pipefail
"$FIXTURE" set-limited "$DATABASE" "$BACKUP" "$DAY"
open "$APP"
PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase limited \
  --forbid "$DATABASE" \
  --forbid 'No current Screenwatch observations are available.'
```

Confirm visually that the coverage card reads `LIMITED COVERAGE` and includes `Drift detection is suspended until Screenwatch coverage is current.`.
Confirm that no database path or fixture-only detail is visible.
Quit and reopen the app normally, reopen Behavior Evidence, and rerun the same preflight and limited probe to prove persistence across an ordinary relaunch.

## Verify recovery

Quit the app and helper before changing the fixture to current coverage.
Open the signed app normally and open Behavior Evidence again.

```zsh
set -euo pipefail
"$FIXTURE" set-current "$DATABASE" "$BACKUP" "$DAY"
open "$APP"
PID="$(pgrep -n -x 'Zoid Coach')"
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" --expected-app-pid "$PID"
swift "$PROBE" --pid "$PID" --phase current \
  --forbid "$DATABASE" \
  --forbid 'No current Screenwatch observations are available.'
```

Confirm visually that the card reads `CURRENT COVERAGE` and no suspension warning remains.

## Restore exact data

Quit the app and helper before restoring the original snapshot.

```zsh
set -euo pipefail
"$FIXTURE" restore "$DATABASE" "$BACKUP" "$DAY"
rm -f "$BACKUP"
```

The fixture fails unless the original payload bytes and timestamp are restored exactly.
This runbook leaves installed signed runtime execution and visual inspection as the only acceptance work that cannot be completed in a non-runtime build task.
