#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY
readonly MODEL="$REPOSITORY/Sources/ZoidCoachApp/AppModel.swift"
readonly STATE="$REPOSITORY/Sources/ZoidCoachApp/CalendarPlanApprovalState.swift"
readonly VIEW="$REPOSITORY/Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/CalendarPlanApprovalStateTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc059001-priority-plan-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc059001-priority-plan-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc059001-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-059-001-SIGNED-QA-RUNBOOK.md"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

for file in "$MODEL" "$STATE" "$VIEW" "$TESTS" "$FIXTURE" "$PROBE" "$PREFLIGHT" "$RUNBOOK"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
done

require_literal "$MODEL" 'executionStatesByReminderID' "approval snapshot lacks execution states"
require_literal "$STATE" 'let executionState: TaskExecutionState?' "approval item state is not backward compatible"
require_literal "$STATE" 'isIncompletePriorityTask' "incomplete priority boundary is missing"
require_literal "$STATE" 'PRIORITY · INCOMPLETE' "explicit incomplete priority label is missing"
require_literal "$VIEW" 'calendar-plan-review.priority-state.' "review AX identity is missing"
require_literal "$VIEW" 'calendar-plan-receipt.priority-state.' "receipt AX identity is missing"
require_literal "$TESTS" 'legacy receipts decode without inventing task completion state' "legacy decoding test is missing"
require_literal "$TESTS" 'only an explicitly incomplete priority task is identified' "completed and non-priority boundary test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$PROBE"
"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-059-001 priority-plan static gates and QA self-tests\n'
