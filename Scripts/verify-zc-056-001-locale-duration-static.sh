#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FORMATTER="$REPOSITORY/Sources/ZoidCoachApp/LocaleAwareDurationFormatter.swift"
readonly STATE="$REPOSITORY/Sources/ZoidCoachApp/MenuBarCoachState.swift"
readonly FORMATTER_TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/LocaleAwareDurationFormatterTests.swift"
readonly MENU_TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/MenuBarCoachTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc056001-locale-duration-fixture.sh"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc056001-locale-duration-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc056001-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-001-SIGNED-QA-RUNBOOK.md"

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

require_absent() {
    local file="$1"
    local literal="$2"
    local label="$3"
    ! grep -Fq -- "$literal" "$file" || fail "$label"
}

for file in "$FORMATTER" "$STATE" "$FORMATTER_TESTS" "$MENU_TESTS" "$FIXTURE" "$AX_PROBE" "$PREFLIGHT" "$RUNBOOK"; do
    [[ -f "$file" ]] || fail "required file is missing: $file"
done

require_literal "$FORMATTER" "let locale: Locale" "formatter does not retain the injected locale"
require_literal "$FORMATTER" "usage: .asProvided" "formatter can silently convert minute values to another unit"
require_literal "$FORMATTER" "width: .wide" "wide duration style is missing"
require_literal "$FORMATTER" "width: .abbreviated" "compact duration style is missing"
require_absent "$FORMATTER" "minutes == 1" "formatter manually implements English singular/plural"
require_literal "$STATE" "locale: Locale = .current" "menu state has no deterministic locale injection boundary"
require_literal "$STATE" "duration.compact(minutes: task.estimateMinutes)" "estimate duration bypasses locale formatting"
require_literal "$STATE" "duration.compact(minutes: elapsedMinutes)" "tracked duration bypasses locale formatting"
require_literal "$STATE" "duration.wide(minutes: elapsedMinutes)" "elapsed accessibility duration is not wide"
require_absent "$STATE" "minuteDescription" "manual English minute description remains in active-time accessibility copy"

require_literal "$FORMATTER_TESTS" "Locale(identifier: \"en_US\")" "en-US formatter contract is untested"
require_literal "$FORMATTER_TESTS" "Locale(identifier: \"fr_FR\")" "non-English formatter contract is untested"
require_literal "$FORMATTER_TESTS" "wide(minutes: 0)" "zero-minute wide contract is untested"
require_literal "$FORMATTER_TESTS" "wide(minutes: 1)" "one-minute wide contract is untested"
require_literal "$FORMATTER_TESTS" "wide(minutes: 12)" "many-minute wide contract is untested"
require_literal "$MENU_TESTS" "compactActiveTaskDurationsRespectAnInjectedLocaleWithoutLosingMeaning" "menu semantics locale test is missing"
require_literal "$MENU_TESTS" "activeTimeAccessibilityUsesWideDurationsFromTheInjectedLocale" "wide accessibility integration test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$AX_PROBE"
"$FIXTURE" self-test
swift "$AX_PROBE" --self-test
zsh "$PREFLIGHT" --self-test

if [[ "${1:-}" == "--self-test" ]]; then
    require_absent "$FORMATTER" "String(format:" "locale formatter uses a manual numeric template"
fi

printf 'PASS: ZC-056-001 locale-duration static and verifier self-tests\n'
