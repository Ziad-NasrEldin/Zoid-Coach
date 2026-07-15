#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY
readonly VIEW="$REPOSITORY/Sources/ZoidCoachApp/MenuBarCoachView.swift"
readonly PRESENTATION="$REPOSITORY/Sources/ZoidCoachApp/MenuBarVoiceControlsPresentation.swift"
readonly TESTS="$REPOSITORY/Tests/ZoidCoachAppTests/MenuBarVoiceControlsPresentationTests.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc056007-menu-visual-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc056007-menu-visual-ax-probe.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc056007-signed-preflight.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-007-SIGNED-QA-RUNBOOK.md"

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

require_literal "$VIEW" "voiceControlsSection" "Sumi voice section is missing"
require_literal "$VIEW" ".background(Sumi.softPaper)" "flat Sumi paper treatment is missing"
require_literal "$VIEW" "Divider().overlay(Sumi.rule)" "Sumi rule is missing"
require_literal "$VIEW" '.accessibilityIdentifier("menu-bar.voice-controls.toggle")' "toggle AX identity is missing"
require_literal "$VIEW" '.accessibilityIdentifier("menu-bar.voice-controls.content")' "content AX identity is missing"
! grep -Fq 'DisclosureGroup("VOICE CONTROLS")' "$VIEW" || fail "native disclosure chrome remains"
require_literal "$PRESENTATION" 'isExpanded ? "chevron.down" : "chevron.right"' "stateful Sumi disclosure symbol is missing"
require_literal "$PRESENTATION" 'isExpanded ? "Expanded" : "Collapsed"' "stateful AX value is missing"
require_literal "$TESTS" "collapsedStateUsesForwardDisclosureAndExplainsTheAction" "collapsed behavior test is missing"
require_literal "$TESTS" "expandedStateUsesDownDisclosureAndExplainsTheAction" "expanded behavior test is missing"

bash -n "$FIXTURE"
zsh -n "$PREFLIGHT"
swiftc -frontend -parse "$PROBE"
"$FIXTURE" self-test
swift "$PROBE" --self-test
zsh "$PREFLIGHT" --self-test

printf 'PASS: ZC-056-007 menu visual static gates and QA self-tests\n'
