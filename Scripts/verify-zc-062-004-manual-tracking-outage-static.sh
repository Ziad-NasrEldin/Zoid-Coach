#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="355dd2bad31ca495699266613a6974fb20793a98"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift
    Scripts/qa-zc062004-manual-tracking-outage-fixture.sh
    Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift
    Scripts/qa-zc062004-signed-preflight.sh
    Scripts/verify-zc-062-004-manual-tracking-outage-static.sh
    docs/ZC-062-004-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized() { sed '/^$/d' | LC_ALL=C sort -u; }
require_text() { rg -Fq "$2" "$ROOT/$1" || fail "missing contract in $1: $2"; }

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "required parent unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD || fail "candidate is not stacked on ZC-062-003"
expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized)"
actual="$({ git -C "$ROOT" diff --name-only "$PARENT" --; git -C "$ROOT" ls-files --others --exclude-standard; } | normalized)"
[[ "$actual" == "$expected" ]] || { diff -u <(print -- "$expected") <(print -- "$actual") >&2 || true; fail "candidate differs from exact six-file scope"; }

for owned_path in "${EXPECTED_PATHS[@]}"; do [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"; done
for executable_path in Scripts/qa-zc062004-manual-tracking-outage-fixture.sh Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift Scripts/qa-zc062004-signed-preflight.sh Scripts/verify-zc-062-004-manual-tracking-outage-static.sh; do
    [[ -x "$ROOT/$executable_path" ]] || fail "script is not executable: $executable_path"
done

require_text Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift "zc062004ManualTrackingAdvancesThroughIsolatedOutageAndRelaunch"
require_text Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift "invalidReminderBootstrap"
require_text Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift "duplicateIntervals"
require_text Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift "elapsedFreeze"
require_text Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift "relaunchSnapshotLoss"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "invalid Reminder bootstrap cannot remove the local active task"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "stable interval identity"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "advanced elapsed Today state"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "fresh source accepted as stale"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "real Screenwatch path"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "SQL/schema failure"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "privacy leakage"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "duplicate snapshot"
require_text Scripts/qa-zc062004-manual-tracking-outage-fixture.sh "cleanup mismatch"
require_text Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift '"fresh", "stale", "missing"'
require_text Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift "pause \(taskTitle.lowercased())"
require_text Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift "complete focus \(taskTitle.lowercased())"
require_text Scripts/qa-zc062004-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc062004-signed-preflight.sh "wrong database path accepted"
require_text Scripts/qa-zc062004-signed-preflight.sh "wrong helper path accepted"
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md "ordinary foreground app relaunch"
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md "run_phase fresh"
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md "run_phase stale"
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md "run_phase missing"
require_text docs/ZC-062-004-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'

zsh -n "$ROOT/Scripts/qa-zc062004-manual-tracking-outage-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc062004-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-062-004-manual-tracking-outage-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC062004ManualTrackingOutageJourneyTests.swift"
swiftc -typecheck "$ROOT/Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift"
swift "$ROOT/Scripts/qa-zc062004-manual-tracking-outage-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc062004-manual-tracking-outage-fixture.sh" self-test
"$ROOT/Scripts/qa-zc062004-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-062-004 exact scope, syntax, source controls, singular interval, elapsed advance, bootstrap, manual controls, negatives, persistence, and restore contracts"
