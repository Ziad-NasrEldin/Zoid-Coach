#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contract_for() {
    case "$1" in
        limited)
            printf '%s\t%s\n' \
                "COACHING HOLDS WHEN EVIDENCE IS LIMITED" \
                "Limited evidence"
            ;;
        unknown)
            printf '%s\t%s\n' \
                "UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING" \
                "Unknown evidence excluded"
            ;;
        current)
            printf '%s\t%s\n' \
                "CLASSIFICATION IS NOT INTENT" \
                "Current evidence boundary"
            ;;
        *) return 1 ;;
    esac
}

self_test() {
    [[ "$(contract_for limited)" == $'COACHING HOLDS WHEN EVIDENCE IS LIMITED\tLimited evidence' ]] \
        || fail "limited contract changed"
    [[ "$(contract_for unknown)" == $'UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING\tUnknown evidence excluded' ]] \
        || fail "unknown contract changed"
    [[ "$(contract_for current)" == $'CLASSIFICATION IS NOT INTENT\tCurrent evidence boundary' ]] \
        || fail "current contract changed"
    [[ "$(contract_for limited)" != "$(contract_for unknown)" ]] || fail "limited and unknown states are indistinguishable"
    [[ "$(contract_for unknown)" != "$(contract_for current)" ]] || fail "unknown and current states are indistinguishable"
    ! contract_for stale >/dev/null 2>&1 || fail "unknown fixture state was accepted"
    printf 'PASS: ZC-058-007 alignment boundary fixture self-test\n'
}

case "${1:-}" in
    limited|unknown|current) contract_for "$1" ;;
    self-test) self_test ;;
    *) fail "usage: $0 {limited|unknown|current|self-test}" ;;
esac
