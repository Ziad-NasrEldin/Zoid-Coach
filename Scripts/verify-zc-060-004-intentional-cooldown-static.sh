#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY
readonly OUTCOME="$REPOSITORY/Sources/ZoidCoachApp/DashboardPromptActionOutcome.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/DashboardPromptTaskStartTests.swift"
readonly SERVICE_TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc060004-intentional-cooldown-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc060004-intentional-cooldown-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc060004-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-060-004-SIGNED-QA-RUNBOOK.md"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_literal() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

for file in "$OUTCOME" "$TESTS" "$SERVICE_TESTS" "$FIXTURE" "$PROBE" "$PREFLIGHT" "$RUNBOOK"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
done

require_literal "$OUTCOME" 'PromptNotificationCategory.gamingDrift.rawValue' "feedback is not gaming-specific"
require_literal "$OUTCOME" 'configured override window' "configured-window feedback is missing"
require_literal "$OUTCOME" 'Returning to aligned work ends the pause early.' "early-end feedback is missing"
! grep -Fq 'paused for 45 minutes' "$OUTCOME" || fail "feedback invents a fixed duration"
require_literal "$TESTS" 'intentionalGamingChoiceClosesPromptAndExplainsConfiguredOverride' "prompt-close outcome test is missing"
require_literal "$TESTS" 'intentionalGamingOutcomeRejectsNonGamingAndUnrelatedActions' "negative boundary test is missing"
require_literal "$SERVICE_TESTS" 'intentionalGamingOverrideRequiresTwoMinutesOfWorkBeforeEarlyReprompt' "early aligned-work boundary test is missing"
require_literal "$SERVICE_TESTS" 'intentionalGamingOverrideUsesConfiguredDurationAcrossRestart' "configured expiry boundary test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$PROBE"
"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-060-004 intentional cooldown static gates and QA self-tests\n'
