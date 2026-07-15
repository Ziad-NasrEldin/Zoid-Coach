#!/usr/bin/env bash
set -euo pipefail

readonly STATUS_MESSAGE="Intentional gaming recorded. Equivalent gaming prompts are paused for your configured override window. Returning to aligned work ends the pause early."

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contract_for() {
    case "$1" in
        visible) printf '%s\t%s\n' "today.prompt.action-status" "$STATUS_MESSAGE" ;;
        suppressed) printf '%s\t%s\n' "intentionalOverrideActive" "Equivalent prompt suppressed" ;;
        early-end) printf '%s\t%s\n' "two aligned minutes" "Override ended early" ;;
        expiry) printf '%s\t%s\n' "configured boundary" "Override expired" ;;
        *) return 1 ;;
    esac
}

self_test() {
    [[ "$(contract_for visible)" == $'today.prompt.action-status\tIntentional gaming recorded. Equivalent gaming prompts are paused for your configured override window. Returning to aligned work ends the pause early.' ]] \
        || fail "visible status contract changed"
    [[ "$(contract_for suppressed)" == $'intentionalOverrideActive\tEquivalent prompt suppressed' ]] \
        || fail "suppression contract changed"
    [[ "$(contract_for early-end)" != "$(contract_for expiry)" ]] \
        || fail "early end and expiry contracts are indistinguishable"
    [[ "$STATUS_MESSAGE" != *[0-9]* ]] || fail "status invents a countdown"
    ! contract_for stale >/dev/null 2>&1 || fail "unknown state was accepted"
    printf 'PASS: ZC-060-004 intentional cooldown fixture self-test\n'
}

case "${1:-}" in
    visible|suppressed|early-end|expiry) contract_for "$1" ;;
    self-test) self_test ;;
    *) fail "usage: $0 {visible|suppressed|early-end|expiry|self-test}" ;;
esac
