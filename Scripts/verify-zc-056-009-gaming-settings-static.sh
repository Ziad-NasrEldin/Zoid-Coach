#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY
readonly VIEW="$REPOSITORY/Sources/ZoidCoachApp/Views/SettingsView.swift"
readonly PRESENTATION="$REPOSITORY/Sources/ZoidCoachApp/GamingSettingsDisclosurePresentation.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/GamingSettingsDisclosurePresentationTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc056009-gaming-settings-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc056009-gaming-settings-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc056009-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-009-SIGNED-QA-RUNBOOK.md"

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

require_literal "$VIEW" "advancedGamingLimitsSection" "advanced gaming section is missing"
require_literal "$VIEW" 'settings.gaming.advanced-limits.toggle' "disclosure identity is missing"
require_literal "$VIEW" 'settings.gaming.advanced-limits.content' "advanced content identity is missing"
require_literal "$VIEW" 'Text("WORK-HOURS BOUNDARY")' "work-hours group is missing"
require_literal "$VIEW" 'Text("PROMPT TIMING")' "prompt timing group is missing"
require_literal "$VIEW" "value: \$controller.draft.gamingWorkHoursDailyMaximumMinutes" "work-hours binding changed"
require_literal "$VIEW" "value: \$controller.draft.gamingDailyPromptCap" "prompt cap binding changed"
require_literal "$VIEW" "value: \$controller.draft.gamingReturnFromIdleGraceMinutes" "idle grace binding changed"
require_literal "$PRESENTATION" 'isExpanded ? "Expanded" : "Collapsed"' "truthful AX state is missing"
require_literal "$TESTS" "collapsedStateNamesTheHiddenLimitsWithoutCompetingWithTheAllowance" "collapsed test is missing"
require_literal "$TESTS" "expandedStateMakesTheReturnActionExplicit" "expanded test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$PROBE"
"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-056-009 gaming settings static gates and QA self-tests\n'
