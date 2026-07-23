#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SOURCE="$REPOSITORY/Sources/ZoidCoachApp/Views/TodayDayStateHeader.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/TodayDayStatePresentationTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc056006-paused-day-state-fixture.sh"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc056006-paused-day-state-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc056006-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-006-SIGNED-QA-RUNBOOK.md"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    local file="$1"
    local literal="$2"
    local label="$3"
    grep -Fq -- "$literal" "$file" || fail "$label"
}

for file in "$SOURCE" "$TESTS" "$FIXTURE" "$AX_PROBE" "$PREFLIGHT" "$RUNBOOK"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
done

require_literal "$SOURCE" "case paused" "paused day-state kind is missing"
require_literal "$SOURCE" "case completed" "completed day-state kind is missing"
require_literal "$SOURCE" 'hasPausedTask: snapshot.taskRows.contains { $0.state == .paused }' "snapshot does not derive paused work"
require_literal "$SOURCE" 'snapshot.taskRows.allSatisfy { $0.state == .completed }' "snapshot does not derive all-completed work"
require_literal "$SOURCE" "title: \"WORK PAUSED\"" "paused title is missing"
require_literal "$SOURCE" "detail: \"A task is paused and ready to resume.\"" "paused explanation is missing"
require_literal "$SOURCE" ".accessibilityValue(presentation.accessibilityValue)" "stable state AX value is missing"
require_literal "$SOURCE" ".accessibilityIdentifier(\"today.day-state\")" "existing day-state AX identity was not preserved"

require_literal "$TESTS" "pausedTaskIsExplicitWhenNoTaskIsActive" "paused/no-active behavior test is missing"
require_literal "$TESTS" "activeTaskIsTheDayStateRegardlessOfPlanningLifecycle" "active precedence test is missing"
require_literal "$TESTS" "allCompletedTasksProduceAnExplicitCompletedDayState" "completed behavior test is missing"
require_literal "$TESTS" "activePausedAndCompletedStatesUseTruthfulPrecedence" "state precedence test is missing"
require_literal "$TESTS" "UNPLANNED DAY" "unplanned state regression test is missing"
require_literal "$TESTS" "PLANNED DAY" "planned state regression test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$AX_PROBE"
"$FIXTURE" self-test
swift "$AX_PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-056-006 paused day-state static and verifier self-tests\n'
