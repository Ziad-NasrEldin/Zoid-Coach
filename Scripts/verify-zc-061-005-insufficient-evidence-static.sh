#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="0f82cbc3dd12252a3ed8f08a65210cfc72dcf6b2"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift
    Scripts/qa-zc061005-insufficient-evidence-fixture.sh
    Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift
    Scripts/qa-zc061005-signed-preflight.sh
    Scripts/verify-zc-061-005-insufficient-evidence-static.sh
    docs/ZC-061-005-SIGNED-QA-RUNBOOK.md
)

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

normalized_lines() {
    sed '/^$/d' | LC_ALL=C sort -u
}

require_text() {
    rg -Fq "$2" "$ROOT/$1" || fail "missing required contract in $1: $2"
}

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "stacked parent is unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD \
    || fail "candidate is not stacked on ZC-061-002"

expected_scope="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
actual_scope="$({
    git -C "$ROOT" diff --name-only "$PARENT" --
    git -C "$ROOT" ls-files --others --exclude-standard
} | normalized_lines)"
[[ "$actual_scope" == "$expected_scope" ]] || {
    print -u2 -- "FAIL: candidate scope differs from the exact six-file contract"
    diff -u <(print -- "$expected_scope") <(print -- "$actual_scope") >&2 || true
    exit 1
}

for owned_path in "${EXPECTED_PATHS[@]}"; do
    [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"
done
for executable in \
    Scripts/qa-zc061005-insufficient-evidence-fixture.sh \
    Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift \
    Scripts/qa-zc061005-signed-preflight.sh \
    Scripts/verify-zc-061-005-insufficient-evidence-static.sh; do
    [[ -x "$ROOT/$executable" ]] || fail "owned script is not executable: $executable"
done

require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".screenwatchEvidenceInvalid"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".suppressed(.limitedCoverage)"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".suppressed(.belowMaterialThreshold)"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".suppressed(.staleEvidence)"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".suppressed(.noActiveTask)"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift ".suppressed(.alreadyHandled)"
require_text Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift "zc061005UncertainOverlapWithdrawsStrongDriftAndQueuesOneSafeConfirmation"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "resolution_reason = 'screenwatch_evidence_invalid'"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "qualifying-scheduled|qualifying-delivered|below-threshold|stale|no-active-task|already-handled"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "strong scheduled or delivered notification remains"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "duplicate ambiguity"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "SQL/schema failure"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "privacy leakage"
require_text Scripts/qa-zc061005-insufficient-evidence-fixture.sh "byte-exact restoration"
require_text Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift "strong gaming-drift wording remains visible"
require_text Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift "incorrectly labeled Research"
require_text Scripts/qa-zc061005-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc061005-signed-preflight.sh 'case "--once"'
require_text docs/ZC-061-005-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-061-005-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'
require_text docs/ZC-061-005-SIGNED-QA-RUNBOOK.md "Never classify the session as Research."

zsh -n "$ROOT/Scripts/qa-zc061005-insufficient-evidence-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc061005-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-061-005-insufficient-evidence-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift"
swift "$ROOT/Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc061005-insufficient-evidence-fixture.sh" self-test
"$ROOT/Scripts/qa-zc061005-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-061-005 exact scope, syntax, journey parse, fixture, AX, preflight, privacy, and restoration contracts"
