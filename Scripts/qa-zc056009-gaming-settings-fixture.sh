#!/usr/bin/env bash
set -euo pipefail

readonly CORE_CONTROLS=(
    settings.gaming.budget-enabled
    settings.gaming.daily-budget
    settings.gaming.priority-reward
    settings.gaming.intentional-override
)
readonly ADVANCED_CONTROLS=(
    settings.gaming.work-hours-maximum-enabled
    settings.gaming.work-hours-maximum
    settings.gaming.daily-prompt-cap
    settings.gaming.prompt-cooldown
    settings.gaming.task-start-grace
    settings.gaming.return-from-idle-grace
)

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

print_group() {
    case "$1" in
        core) printf '%s\n' "${CORE_CONTROLS[@]}" ;;
        advanced) printf '%s\n' "${ADVANCED_CONTROLS[@]}" ;;
        *) return 1 ;;
    esac
}

self_test() {
    [[ "${#CORE_CONTROLS[@]}" == 4 ]] || fail "core allowance must remain four decisions"
    [[ "${#ADVANCED_CONTROLS[@]}" == 6 ]] || fail "advanced tuning inventory changed"
    local core advanced
    for core in "${CORE_CONTROLS[@]}"; do
        for advanced in "${ADVANCED_CONTROLS[@]}"; do
            [[ "$core" != "$advanced" ]] || fail "control appears in both groups: $core"
        done
    done
    ! print_group unknown >/dev/null 2>&1 || fail "unknown group was accepted"
    printf 'PASS: ZC-056-009 gaming settings fixture self-test\n'
}

case "${1:-}" in
    core|advanced) print_group "$1" ;;
    self-test) self_test ;;
    *) fail "usage: $0 {core|advanced|self-test}" ;;
esac
