#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY
readonly VIEW="$REPOSITORY/Sources/ZoidCoachApp/Views/BehaviorEvidenceSheet.swift"
readonly PRESENTATION="$REPOSITORY/Sources/ZoidCoachApp/DriftCoachingEvidenceBoundaryPresentation.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/DriftCoachingEvidenceBoundaryPresentationTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc058007-alignment-boundary-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc058007-alignment-boundary-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc058007-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-058-007-SIGNED-QA-RUNBOOK.md"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

for file in "$VIEW" "$PRESENTATION" "$TESTS" "$FIXTURE" "$PROBE" "$PREFLIGHT" "$RUNBOOK"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
done

require_literal "$VIEW" "coachingBoundaryCard" "coaching boundary card is missing"
require_literal "$VIEW" 'hasSourceIssue: evidence.hasSourceIssue' "source issue input is missing"
require_literal "$VIEW" 'unknownMinutes: evidence.unknownMinutes' "unknown evidence input is missing"
require_literal "$VIEW" 'today.behavior-evidence.coaching-boundary' "boundary AX identity is missing"
require_literal "$VIEW" '.background(Sumi.softPaper)' "restrained Sumi treatment is missing"
require_literal "$PRESENTATION" 'COACHING HOLDS WHEN EVIDENCE IS LIMITED' "limited state is missing"
require_literal "$PRESENTATION" 'UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING' "unknown state is missing"
require_literal "$PRESENTATION" 'CLASSIFICATION IS NOT INTENT' "current state is missing"
require_literal "$TESTS" "limitedCoverageExplainsWhyStrongCoachingHoldsAndWhatToDo" "limited behavior test is missing"
require_literal "$TESTS" "unknownTimeIsExplicitlyExcludedFromStrongCoachingEvidence" "unknown behavior test is missing"
require_literal "$TESTS" "currentEvidenceStillRefusesToInferIntentFromAnAppName" "current behavior test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$PROBE"
"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-058-007 alignment boundary static gates and QA self-tests\n'
