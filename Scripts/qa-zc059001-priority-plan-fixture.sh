#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contract_for() {
    local surface="$1"
    local task_id="$2"
    [[ -n "$task_id" ]] || return 1
    case "$surface" in
        review|receipt)
            printf 'calendar-plan-%s.priority-state.%s\t%s\t%s\t%s\n' \
                "$surface" "$task_id" \
                "PRIORITY · INCOMPLETE" \
                "Priority task status" \
                "Incomplete"
            ;;
        *) return 1 ;;
    esac
}

self_test() {
    local review receipt
    review="$(contract_for review qa-priority-task)"
    receipt="$(contract_for receipt qa-priority-task)"
    [[ "$review" == $'calendar-plan-review.priority-state.qa-priority-task\tPRIORITY · INCOMPLETE\tPriority task status\tIncomplete' ]] \
        || fail "review contract changed"
    [[ "$receipt" == $'calendar-plan-receipt.priority-state.qa-priority-task\tPRIORITY · INCOMPLETE\tPriority task status\tIncomplete' ]] \
        || fail "receipt contract changed"
    [[ "$review" != "$receipt" ]] || fail "review and receipt identities are indistinguishable"
    ! contract_for stale qa-priority-task >/dev/null 2>&1 || fail "unknown surface was accepted"
    ! contract_for review "" >/dev/null 2>&1 || fail "empty task identity was accepted"
    printf 'PASS: ZC-059-001 priority-plan fixture self-test\n'
}

case "${1:-}" in
    review|receipt)
        [[ -n "${2:-}" ]] || fail "task identity is required"
        contract_for "$1" "$2"
        ;;
    self-test) self_test ;;
    *) fail "usage: $0 {review|receipt TASK_ID|self-test}" ;;
esac
