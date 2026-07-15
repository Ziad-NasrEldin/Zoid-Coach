#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="0c6e749bdbafc732779ff1bd85a2829b8ea248e1"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift
    Scripts/qa-zc062001-healthy-workday-fixture.sh
    Scripts/qa-zc062001-healthy-workday-ax-probe.swift
    Scripts/qa-zc062001-signed-preflight.sh
    Scripts/verify-zc-062-001-healthy-workday-static.sh
    docs/ZC-062-001-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized_lines() { sed '/^$/d' | LC_ALL=C sort -u; }
require_text() { rg -Fq "$2" "$ROOT/$1" || fail "missing contract in $1: $2"; }

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "stacked parent is unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD \
    || fail "candidate is not stacked on the required parent"

expected_scope="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
actual_scope="$({
    git -C "$ROOT" diff --name-only "$PARENT" --
    git -C "$ROOT" ls-files --others --exclude-standard
} | normalized_lines)"
[[ "$actual_scope" == "$expected_scope" ]] || {
    diff -u <(print -- "$expected_scope") <(print -- "$actual_scope") >&2 || true
    fail "candidate differs from the exact six-file scope"
}

for owned_path in "${EXPECTED_PATHS[@]}"; do
    [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"
done
for executable_path in \
    Scripts/qa-zc062001-healthy-workday-fixture.sh \
    Scripts/qa-zc062001-healthy-workday-ax-probe.swift \
    Scripts/qa-zc062001-signed-preflight.sh \
    Scripts/verify-zc-062-001-healthy-workday-static.sh; do
    [[ -x "$ROOT/$executable_path" ]] || fail "script is not executable: $executable_path"
done

require_text Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift "zc062001ApprovedDayAndFiveHealthRowsRemainReadyAfterReopen"
require_text Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift "zc062001HealthBoundaryFailsClosed"
require_text Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift "zc062001DuplicateSnapshotSQLAndPrivacyFailuresAreRejected"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "FRESHNESS_LIMIT=240"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "one canonical Today snapshot"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "no stale or limited source fallback"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "one-source unhealthy"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "one-source missing"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "duplicate snapshot"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "SQL failure"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "privacy leakage"
require_text Scripts/qa-zc062001-healthy-workday-fixture.sh "cleanup mismatch"
require_text Scripts/qa-zc062001-healthy-workday-ax-probe.swift "exactly five privacy-safe planned-day health rows"
require_text Scripts/qa-zc062001-healthy-workday-ax-probe.swift "Screenwatch - Current and ingested"
require_text Scripts/qa-zc062001-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc062001-signed-preflight.sh "wrong database path accepted"
require_text Scripts/qa-zc062001-signed-preflight.sh "wrong helper path accepted"
require_text docs/ZC-062-001-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-062-001-SIGNED-QA-RUNBOOK.md "ordinary foreground app relaunch"
require_text docs/ZC-062-001-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'

zsh -n "$ROOT/Scripts/qa-zc062001-healthy-workday-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc062001-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-062-001-healthy-workday-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift"
swiftc -typecheck "$ROOT/Scripts/qa-zc062001-healthy-workday-ax-probe.swift"
swift "$ROOT/Scripts/qa-zc062001-healthy-workday-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc062001-healthy-workday-fixture.sh" self-test
"$ROOT/Scripts/qa-zc062001-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-062-001 exact scope, syntax, typecheck, fixture, AX, preflight, freshness, privacy, negatives, and restoration contracts"
