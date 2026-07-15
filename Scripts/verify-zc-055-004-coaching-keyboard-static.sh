#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"

fail() { print -u2 -- "FAIL: $*"; exit 1; }

require_literal() {
    local file="$1" literal="$2" label="$3"
    grep -Fq -- "$literal" "$ROOT/$file" || fail "$label"
}

verify() {
    local policy='Sources/ZoidCoachApp/PromptKeyboardShortcut.swift'
    local view='Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift'
    local tests='Tests/ZoidCoachAppTests/PromptKeyboardShortcutTests.swift'
    local fixture='Scripts/qa-zc055004-coaching-keyboard-fixture.sh'
    local probe='Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift'
    local runbook='docs/ZC-055-004-SIGNED-QA-RUNBOOK.md'

    for mapping in \
        '.startRecommendedTask: key = "t"' '.startShortSprint: key = "s"' \
        '.startWorkSprint: key = "w"' '.returnToActiveTask: key = "r"' \
        '.fiveMoreMinutes: key = "f"' '.startBreak: key = "b"' \
        '.continueIntentionally: key = "i"' '.pauseTask: key = "p"' \
        '.classifyAsSupportingWork: key = "u"' '.classifyAsGaming: key = "g"' \
        '.keepActivityUnknown: key = "n"' '.rescheduleTask: key = "e"' \
        '.markBlocked: key = "k"' '.endWorkday: key = "q"' '.ignore: key = "x"'; do
        require_literal "$policy" "$mapping" "coaching shortcut mapping is missing: $mapping"
    done
    require_literal "$policy" 'static let dismiss = PromptKeyboardShortcut(key: "d")' "dismiss shortcut is missing"
    require_literal "$policy" '!actionsDisabled && promptID == keyboardPromptID' "unambiguous availability gate is missing"
    require_literal "$view" 'timeline.awaitingResponse.first?.id' "first actionable prompt gate is missing"
    require_literal "$view" 'Button { choose(control.action, for: episode) }' "shortcut no longer uses the canonical action path"
    require_literal "$view" '.coachingKeyboardShortcut(shortcut)' "SwiftUI keyboard shortcut wiring is missing"
    require_literal "$view" 'Text(shortcut.displayLabel)' "visible shortcut label is missing"
    require_literal "$view" 'model.dismissPrompt(entry.episode)' "dismiss shortcut no longer uses canonical dismissal"
    require_literal "$tests" 'destructiveShortcutRetainsConfirmation' "destructive confirmation test is missing"
    require_literal "$tests" 'shortcutAvailabilityIsUnambiguous' "shortcut availability test is missing"
    require_literal "$fixture" 'SQL failed for deliberate broken SQL' "fixture SQL failure self-test is missing"
    require_literal "$fixture" 'database restore is not byte exact' "fixture exact restore is missing"
    require_literal "$probe" 'secondary prompt owns duplicate global shortcuts' "AX duplicate shortcut rejection is missing"
    require_literal "$probe" 'private prompt payload is visible' "AX privacy rejection is missing"
    require_literal "$probe" 'keyboard-opened blocked reason sheet' "AX destructive route assertion is missing"
    require_literal "$runbook" 'press Option Command K' "runbook destructive keyboard step is missing"
    require_literal "$runbook" 'press Option Command D' "runbook dismissal keyboard step is missing"
    require_literal "$runbook" 'reopen the app normally' "runbook ordinary restart is missing"
    print -- "PASS: ZC-055-004 static keyboard contract"
}

[[ "${1:-}" == --self-test && $# == 1 ]] || fail "usage: $0 --self-test"
verify
