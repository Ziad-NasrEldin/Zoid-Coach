#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contract_for() {
    case "$1" in
        collapsed) printf '%s\t%s\t%s\n' "Voice controls" "Collapsed" "Expand voice controls" ;;
        expanded) printf '%s\t%s\t%s\n' "Voice controls" "Expanded" "Collapse voice controls" ;;
        *) return 1 ;;
    esac
}

assert_contract() {
    local state="$1"
    local expected="$2"
    local actual
    actual="$(contract_for "$state")" || fail "unknown disclosure state: $state"
    [[ "$actual" == "$expected" ]] || fail "$state contract changed: $actual"
}

self_test() {
    assert_contract collapsed $'Voice controls\tCollapsed\tExpand voice controls'
    assert_contract expanded $'Voice controls\tExpanded\tCollapse voice controls'
    ! contract_for stale >/dev/null 2>&1 || fail "unknown state was accepted"
    [[ "$(contract_for collapsed)" != "$(contract_for expanded)" ]] \
        || fail "collapsed and expanded contracts are indistinguishable"
    printf 'PASS: ZC-056-007 menu visual fixture self-test\n'
}

case "${1:-}" in
    collapsed|expanded) contract_for "$1" ;;
    self-test) self_test ;;
    *) fail "usage: $0 {collapsed|expanded|self-test}" ;;
esac
