#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE='ede57d92e568904495118b8a6cccdfed6cabde4f'

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

read_path() {
    local treeish="$1" file_path="$2"
    if [[ "$treeish" == WORKTREE ]]; then
        [[ -f "$REPOSITORY/$file_path" ]] || fail "required file is absent: $file_path"
        sed -n '1,$p' "$REPOSITORY/$file_path"
    else
        git -C "$REPOSITORY" show "${treeish}:$file_path" || fail "required committed file is absent: $file_path"
    fi
}

require_literal() {
    local content="$1" literal="$2" label="$3"
    print -r -- "$content" | grep -Fq -- "$literal" || fail "$label"
}

verify() {
    local treeish="$1" service tests coordinator fixture probe preflight runbook
    service="$(read_path "$treeish" Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift)"
    tests="$(read_path "$treeish" Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift)"
    coordinator="$(read_path "$treeish" Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift)"
    fixture="$(read_path "$treeish" Scripts/qa-zc049003-stale-prompt-suppression-fixture.sh)"
    probe="$(read_path "$treeish" Scripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift)"
    preflight="$(read_path "$treeish" Scripts/qa-zc049003-signed-preflight.sh)"
    runbook="$(read_path "$treeish" docs/ZC-049-003-SIGNED-QA-RUNBOOK.md)"

    require_literal "$service" 'guard (0 ... 180).contains(observationAge)' "future and stale evidence age gate is missing"
    require_literal "$service" 'try dismissUnresolvedGamingDriftPrompts()' "invalid evidence no longer withdraws unresolved prompts"
    require_literal "$service" "COALESCE(resolution_origin, '') = 'system'" "system recovery origin gate is missing"
    require_literal "$service" "COALESCE(resolution_reason, '') = 'screenwatch_evidence_invalid'" "Screenwatch recovery reason gate is missing"
    require_literal "$coordinator" 'unresolvedPromptIDs.contains(notification.desired.promptID)' "fixture notification reconciliation gate is missing"
    require_literal "$coordinator" 'removeDeliveredNotifications' "delivered notification removal is missing"
    require_literal "$coordinator" 'removePendingNotificationRequests' "pending notification removal is missing"

    require_literal "$tests" 'gamingDriftSuppressesPromptsWhenScreenwatchBecomesStaleAndRecoversWithFreshEvidence' "stale-to-fresh focused test is missing"
    require_literal "$tests" 'invalidScreenwatchWithdrawalAloneAllowsSafeSameSessionRecovery' "same-session recovery focused test is missing"
    require_literal "$tests" '.suppressed(.cooldownActive)' "cooldown preservation assertion is missing"
    require_literal "$tests" '.suppressed(.dailyLimitReached)' "daily-cap preservation assertion is missing"
    require_literal "$tests" 'resolutionOrigin == .user' "user dismissal origin assertion is missing"

    require_literal "$fixture" 'initial unresolved prompt' "fixture does not reject an absent initial prompt"
    require_literal "$fixture" 'SQL failed for' "fixture SQL failure gate is missing"
    require_literal "$fixture" 'stale prompt notification was not removed' "fixture notification removal assertion is missing"
    require_literal "$fixture" 'fresh same-session recovery prompt' "fixture fresh recovery assertion is missing"
    require_literal "$fixture" 'database restore is not byte exact' "fixture exact database restore is missing"
    require_literal "$fixture" 'OS fixture restore is not byte exact' "fixture exact OS restore is missing"
    require_literal "$fixture" 'preserved user dismissal count' "fixture dismissal preservation assertion is missing"

    require_literal "$probe" 'initial visible prompt is absent' "AX initial-prompt absence rejection is missing"
    require_literal "$probe" 'stale prompt remains visibly actionable' "AX stale prompt rejection is missing"
    require_literal "$probe" 'fresh same-session recovery prompt' "AX fresh recovery assertion is missing"
    require_literal "$probe" 'user-dismissed prompt became actionable again' "AX dismissal preservation assertion is missing"
    require_literal "$probe" 'private fixture value is visible' "AX privacy assertion is missing"

    require_literal "$preflight" "$CANONICAL_BASE" "preflight canonical base is missing"
    require_literal "$preflight" 'verify-package.sh' "signed package verification is missing"
    require_literal "$preflight" 'helper does not hold the exact isolated database open' "helper database binding is missing"
    require_literal "$runbook" 'Do not continue if the initial prompt is absent' "runbook initial-prompt fail-closed rule is missing"
    require_literal "$runbook" 'ordinary app and helper restart' "runbook ordinary restart coverage is missing"
    require_literal "$runbook" '--phase stale' "runbook stale AX phase is missing"
    require_literal "$runbook" '--phase fresh' "runbook fresh AX phase is missing"
    require_literal "$runbook" '--phase preserved' "runbook dismissal preservation phase is missing"
    require_literal "$runbook" 'swift test --filter GamingDriftPromptServiceTests' "runbook focused test gate is missing"
    print -- "PASS: ZC-049-003 static acceptance contract"
}

case "${1:-}" in
    --self-test)
        (( $# == 1 )) || fail "--self-test takes no additional arguments"
        verify WORKTREE
        ;;
    --treeish)
        (( $# == 2 )) || fail "--treeish requires one commit"
        git -C "$REPOSITORY" cat-file -e "$2^{commit}" 2>/dev/null || fail "treeish commit is unavailable"
        verify "$2"
        ;;
    *)
        fail "usage: $0 --self-test | --treeish COMMIT"
        ;;
esac
