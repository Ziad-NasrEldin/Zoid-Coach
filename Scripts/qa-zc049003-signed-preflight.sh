#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE='ede57d92e568904495118b8a6cccdfed6cabde4f'

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "Usage: $0 --self-test"
    print -u2 -- "       $0 APP DATABASE OS_STATE EXPECTED_COMMIT --expected-app-pid PID"
    exit 64
}

is_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

assert_exact() {
    [[ "$1" == "$2" ]] || fail "$3"
}

verify_lineage() {
    local expected="$1" expected_scope actual_scope
    is_sha "$expected" || fail "expected commit must be a full lowercase SHA"
    git -C "$REPOSITORY" cat-file -e "$expected^{commit}" 2>/dev/null || fail "expected commit is unavailable"
    assert_exact "$(git -C "$REPOSITORY" rev-parse "$expected^")" "$CANONICAL_BASE" "candidate is not a direct child of canonical"
    assert_exact "$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")" 1 "candidate must contain exactly one commit"
    expected_scope=$'Scripts/qa-zc049003-signed-preflight.sh\nScripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift\nScripts/qa-zc049003-stale-prompt-suppression-fixture.sh\nScripts/verify-zc-049-003-stale-prompt-suppression-static.sh\ndocs/ZC-049-003-SIGNED-QA-RUNBOOK.md'
    actual_scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE..$expected" | LC_ALL=C sort)"
    assert_exact "$actual_scope" "$expected_scope" "candidate scope is not the exact five reviewed files"
    if print -r -- "$actual_scope" | grep -Eq '(^|/)(CHANGELOG\.md|scenario-registry|scenario_registry|scenario-tracker|ScenarioTracker|\.lavish|\.audit)(/|$)'; then
        fail "candidate touches a protected generated, registry, tracker, Lavish, or audit path"
    fi
}

verify_committed_contract() {
    local expected="$1" fixture probe runbook static
    fixture="$(git -C "$REPOSITORY" show "${expected}:Scripts/qa-zc049003-stale-prompt-suppression-fixture.sh")"
    probe="$(git -C "$REPOSITORY" show "${expected}:Scripts/qa-zc049003-stale-prompt-suppression-ax-probe.swift")"
    runbook="$(git -C "$REPOSITORY" show "${expected}:docs/ZC-049-003-SIGNED-QA-RUNBOOK.md")"
    static="$(git -C "$REPOSITORY" show "${expected}:Scripts/verify-zc-049-003-stale-prompt-suppression-static.sh")"
    print -r -- "$fixture" | grep -Fq 'initial unresolved prompt' || fail "committed fixture does not fail closed on a missing initial prompt"
    print -r -- "$fixture" | grep -Fq 'SQL failed for' || fail "committed fixture does not fail closed on SQL errors"
    print -r -- "$fixture" | grep -Fq 'stale prompt notification was not removed' || fail "committed notification-removal assertion is missing"
    print -r -- "$fixture" | grep -Fq 'preserved user dismissal count' || fail "committed dismissal preservation assertion is missing"
    print -r -- "$probe" | grep -Fq 'private fixture value is visible' || fail "committed AX privacy assertion is missing"
    print -r -- "$probe" | grep -Fq 'fresh same-session recovery prompt' || fail "committed AX recovery assertion is missing"
    print -r -- "$runbook" | grep -Fq 'ordinary app and helper restart' || fail "committed ordinary restart journey is missing"
    print -r -- "$runbook" | grep -Fq 'Do not continue if the initial prompt is absent' || fail "committed initial-prompt fail-closed instruction is missing"
    print -r -- "$static" | grep -Fq 'GamingDriftPromptServiceTests' || fail "committed focused static contract is missing"
    "$SCRIPT_DIR/verify-zc-049-003-stale-prompt-suppression-static.sh" --treeish "$expected"
}

self_test() {
    is_sha "$CANONICAL_BASE" || fail "canonical SHA validation failed"
    ! is_sha deadbeef || fail "short SHA was accepted"
    local head
    head="$(git -C "$REPOSITORY" rev-parse HEAD)"
    verify_lineage "$head"
    verify_committed_contract "$head"
    "$SCRIPT_DIR/qa-zc049003-stale-prompt-suppression-fixture.sh" self-test
    swift "$SCRIPT_DIR/qa-zc049003-stale-prompt-suppression-ax-probe.swift" --self-test
    print -- "PASS: ZC-049-003 signed preflight self-test"
}

if [[ "${1:-}" == --self-test ]]; then
    (( $# == 1 )) || usage
    self_test
    exit 0
fi

(( $# == 6 )) || usage
APP="${1:A}"
DATABASE="${2:A}"
OS_STATE="${3:A}"
EXPECTED_COMMIT="$4"
[[ "$5" == --expected-app-pid ]] || usage
EXPECTED_APP_PID="$6"

verify_lineage "$EXPECTED_COMMIT"
verify_committed_contract "$EXPECTED_COMMIT"
assert_exact "$(git -C "$REPOSITORY" rev-parse HEAD)" "$EXPECTED_COMMIT" "checkout does not match expected candidate"
[[ -d "$APP" ]] || fail "app bundle does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
[[ -f "$OS_STATE" ]] || fail "OS fixture state does not exist: $OS_STATE"
[[ "$DATABASE" != "$HOME/Library/Application Support/Zoid 666/"* ]] || fail "normal user database is forbidden"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

INFO_PLIST="$APP/Contents/Info.plist"
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
APP_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent"
AGENT_PLIST="${AGENT_PLISTS[1]}"
AGENT_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
EXPECTED_OS_STATE="${QA_ROOT:A}/OS Fixtures/state.json"
[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "signed executables are unavailable"
[[ "$APP_ROOT" == "$QA_ROOT" && "$AGENT_ROOT" == "$QA_ROOT" ]] || fail "app and helper QA roots differ"
[[ "$DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database does not match embedded isolated QA root"
[[ "$OS_STATE" == "$EXPECTED_OS_STATE" ]] || fail "OS state does not match embedded isolated QA root"

[[ "$EXPECTED_APP_PID" =~ '^[0-9]+$' ]] || fail "expected app PID is invalid"
kill -0 "$EXPECTED_APP_PID" 2>/dev/null || fail "expected app PID is not running"
lsof -Fn -a -p "$EXPECTED_APP_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" \
    || fail "app PID is not running the exact signed executable"
APP_COMMAND="$(ps -ww -p "$EXPECTED_APP_PID" -o command=)"
[[ " $APP_COMMAND " != *' --qa-open-main '* ]] || fail "app was not opened through an ordinary launch"

SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "signed helper service is unavailable"
HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "signed helper PID is unavailable"
lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
    || fail "helper is not running the exact signed executable"
lsof -a -p "$HELPER_PID" "$DATABASE" >/dev/null 2>&1 \
    || fail "helper does not hold the exact isolated database open"

print -- "APP_PID=$EXPECTED_APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=$DATABASE"
print -- "OS_STATE=$OS_STATE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-049-003 signed runtime identity is bound"
