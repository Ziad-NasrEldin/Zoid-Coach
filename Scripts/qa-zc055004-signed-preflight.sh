#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly ROOT="${SCRIPT_DIR:h}"
readonly BASE='ede57d92e568904495118b8a6cccdfed6cabde4f'

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }

verify_lineage() {
    local expected="$1" scope expected_scope
    is_sha "$expected" || fail "expected commit must be a full lowercase SHA"
    git -C "$ROOT" cat-file -e "$expected^{commit}" 2>/dev/null || fail "expected commit is unavailable"
    [[ "$(git -C "$ROOT" rev-parse "$expected^")" == "$BASE" ]] || fail "candidate is not a direct child of canonical"
    [[ "$(git -C "$ROOT" rev-list --count "$BASE..$expected")" == 1 ]] || fail "candidate must contain exactly one commit"
    expected_scope=$'Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift\nScripts/qa-zc055004-coaching-keyboard-fixture.sh\nScripts/qa-zc055004-signed-preflight.sh\nScripts/verify-zc-055-004-coaching-keyboard-static.sh\nSources/ZoidCoachApp/PromptKeyboardShortcut.swift\nSources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift\nTests/ZoidCoachAppTests/PromptKeyboardShortcutTests.swift\ndocs/ZC-055-004-SIGNED-QA-RUNBOOK.md'
    scope="$(git -C "$ROOT" diff --name-only "$BASE..$expected" | LC_ALL=C sort)"
    [[ "$scope" == "$expected_scope" ]] || fail "candidate scope is not the exact eight reviewed files"
    ! print -r -- "$scope" | grep -Eq '(^|/)(CHANGELOG\.md|scenario-registry|scenario_registry|scenario-tracker|\.lavish|\.audit)(/|$)' \
        || fail "candidate touches a protected path"
}

verify_contract() {
    local expected="$1" policy view fixture probe runbook
    policy="$(git -C "$ROOT" show "${expected}:Sources/ZoidCoachApp/PromptKeyboardShortcut.swift")"
    view="$(git -C "$ROOT" show "${expected}:Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift")"
    fixture="$(git -C "$ROOT" show "${expected}:Scripts/qa-zc055004-coaching-keyboard-fixture.sh")"
    probe="$(git -C "$ROOT" show "${expected}:Scripts/qa-zc055004-coaching-keyboard-ax-probe.swift")"
    runbook="$(git -C "$ROOT" show "${expected}:docs/ZC-055-004-SIGNED-QA-RUNBOOK.md")"
    print -r -- "$policy" | grep -Fq 'static let dismiss' || fail "committed dismiss shortcut is missing"
    print -r -- "$view" | grep -Fq 'timeline.awaitingResponse.first?.id' || fail "committed first-prompt gate is missing"
    print -r -- "$view" | grep -Fq 'choose(control.action, for: episode)' || fail "committed canonical action path is missing"
    print -r -- "$fixture" | grep -Fq 'deliberate broken SQL' || fail "committed SQL negative self-test is missing"
    print -r -- "$probe" | grep -Fq 'secondary prompt owns duplicate' || fail "committed AX duplicate guard is missing"
    print -r -- "$runbook" | grep -Fq 'press Option Command K' || fail "committed keyboard journey is missing"
}

self_test() {
    is_sha "$BASE" || fail "canonical SHA validation failed"
    ! is_sha deadbeef || fail "short SHA was accepted"
    local head="$(git -C "$ROOT" rev-parse HEAD)"
    verify_lineage "$head"
    verify_contract "$head"
    "$SCRIPT_DIR/verify-zc-055-004-coaching-keyboard-static.sh" --self-test
    "$SCRIPT_DIR/qa-zc055004-coaching-keyboard-fixture.sh" self-test
    swift "$SCRIPT_DIR/qa-zc055004-coaching-keyboard-ax-probe.swift" --self-test
    print -- "PASS: ZC-055-004 signed preflight self-test"
}

if [[ "${1:-}" == --self-test ]]; then
    (( $# == 1 )) || fail "--self-test takes no arguments"
    self_test
    exit 0
fi

(( $# == 5 )) || fail "usage: $0 APP DATABASE EXPECTED_COMMIT --expected-app-pid PID"
APP="${1:A}"
DATABASE="${2:A}"
EXPECTED="$3"
[[ "$4" == --expected-app-pid && "$5" =~ '^[0-9]+$' ]] || fail "valid --expected-app-pid is required"
APP_PID="$5"
verify_lineage "$EXPECTED"
verify_contract "$EXPECTED"
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$EXPECTED" ]] || fail "checkout does not match expected commit"
[[ -d "$APP" && -f "$DATABASE" ]] || fail "signed app or isolated database is unavailable"
[[ "$DATABASE" != "$HOME/Library/Application Support/Zoid 666/"* ]] || fail "normal user database is forbidden"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" --expected-commit "$EXPECTED" --require-clean >/dev/null

INFO="$APP/Contents/Info.plist"
APP_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO")"
EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ "$DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database does not match embedded QA root"
kill -0 "$APP_PID" 2>/dev/null || fail "expected app PID is not running"
lsof -Fn -a -p "$APP_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" || fail "app PID executable mismatch"
[[ " $(ps -ww -p "$APP_PID" -o command=) " != *' --qa-open-main '* ]] || fail "app was not opened normally"

AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain one LaunchAgent"
AGENT_PLIST="${AGENT_PLISTS[1]}"
AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper is unavailable"
HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "helper PID is unavailable"
lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" || fail "helper executable mismatch"
lsof -a -p "$HELPER_PID" "$DATABASE" >/dev/null 2>&1 || fail "helper does not hold the exact isolated database open"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "BUILD_COMMIT=$EXPECTED"
print -- "PASS: ZC-055-004 signed runtime identity is bound"
