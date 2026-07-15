#!/bin/zsh
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="361093b4a088c19eee927eaab2b58a40fb3b4c27"
readonly PRODUCT_CANDIDATE="c8ea11afe0d479269fa21d697dd63a5f80688019"
readonly FIXTURE="$SCRIPT_DIR/qa-zc006001-planning-invitation-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc006001-planning-invitation-ax-probe.swift"
readonly POLICY_READINESS="$SCRIPT_DIR/qa-zc006001-policy-readiness.sh"
readonly POLICY_DECODER="$SCRIPT_DIR/qa-zc006001-policy-decode.swift"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc006001-signed-preflight.sh"
readonly TEMPLATE="$SCRIPT_DIR/fixtures/zc-006-001-planning-invitation-ready-state.json"
readonly RUNBOOK="$REPOSITORY/docs/ZC-006-001-SIGNED-QA-RUNBOOK.md"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

for path in "$FIXTURE" "$PROBE" "$POLICY_READINESS" "$POLICY_DECODER" "$PREFLIGHT" "$TEMPLATE" "$RUNBOOK"; do
    [[ -f "$path" && ! -L "$path" ]] || fail "required verifier file is unavailable or unsafe: $path"
done

/bin/zsh -n "$FIXTURE"
/bin/zsh -n "$POLICY_READINESS"
/bin/zsh -n "$PREFLIGHT"
/bin/zsh -n "$0"
/usr/bin/jq -e . "$TEMPLATE" >/dev/null
"$FIXTURE" self-test
/usr/bin/swift "$PROBE" --self-test
/usr/bin/swiftc -typecheck "$PROBE"
"$PREFLIGHT" --self-test

for phrase in \
    'run_case zero future' \
    'run_case zero past work-unplanned' \
    'run_case one future' \
    'run_case one past dismiss' \
    'run_case many future' \
    'run_case many past snooze' \
    '"$FIXTURE" seed-policy' \
    '"$POLICY_READINESS" wait' \
    'cmp "$ORIGINAL_HASHES" "$RESTORED_HASHES"'; do
    /usr/bin/grep -Fq "$phrase" "$RUNBOOK" || fail "runbook is missing required step: $phrase"
done

for phrase in \
    'Planning is available when you are ready' \
    'Nothing is blocked.' \
    'review_plan' \
    'accept_plan' \
    'snooze_planning' \
    'work_unplanned' \
    'dismiss_planning'; do
    /usr/bin/grep -Fq "$phrase" "$FIXTURE" || fail "fixture assertion is missing: $phrase"
done

/usr/bin/git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" HEAD \
    || fail "current branch does not contain the product candidate"
/usr/bin/git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" HEAD \
    || fail "current branch does not contain the current canonical base"

/usr/bin/swift test --package-path "$REPOSITORY" --filter PlanningInvitation >/dev/null
/usr/bin/swift test --package-path "$REPOSITORY" --filter PromptNotificationCoordinatorTests >/dev/null

print -- "PASS: ZC-006-001 static tooling, fixtures, AX probe, preflight, runbook, and focused product tests"
