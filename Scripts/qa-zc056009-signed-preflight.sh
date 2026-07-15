#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-009-SIGNED-QA-RUNBOOK.md"
readonly APP="${1:-}"
readonly EXPECTED_COMMIT="${2:-}"
readonly EXPECTED_APP_PID="${3:-}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    [[ " $1 " == *" $2 "* ]]
}

commit_has_product_contract() {
    local commit="$1"
    local source
    if [[ "$commit" == "WORKTREE" ]]; then
        source="$(<"$REPOSITORY/Sources/ZoidCoachApp/Views/SettingsView.swift")"
    else
        source="$(git -C "$REPOSITORY" show "$commit:Sources/ZoidCoachApp/Views/SettingsView.swift")" \
            || fail "signed commit does not contain SettingsView"
    fi
    [[ "$source" == *'advancedGamingLimitsSection'* ]] || fail "signed commit lacks advanced gaming limits"
    [[ "$source" == *'settings.gaming.advanced-limits.toggle'* ]] || fail "signed commit lacks the disclosure identity"
    [[ "$source" == *'settings.gaming.work-hours-maximum'* ]] || fail "work-hours maximum was lost"
    [[ "$source" == *'settings.gaming.return-from-idle-grace'* ]] || fail "idle grace was lost"
}

assert_runbook_contract() {
    grep -Fq 'trap cleanup EXIT' "$RUNBOOK" || fail "runbook does not guarantee cleanup"
    grep -Fq 'FIXTURE" self-test' "$RUNBOOK" || fail "runbook does not execute fixture self-tests"
    grep -Fq 'swift "$PROBE" --pid "$PID"' "$RUNBOOK" || fail "runbook does not execute the bound AX probe"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "a002610ae3d8db3f1e88cfd8463a4ce103531e83" || fail "valid SHA was rejected"
    ! is_full_lowercase_sha "A002610AE3D8DB3F1E88CFD8463A4CE103531E83" || fail "uppercase SHA was accepted"
    command_has_exact_argument "/tmp/ZoidCoach --qa-open-main" "--qa-open-main" || fail "exact launch argument was rejected"
    ! command_has_exact_argument "/tmp/ZoidCoach --qa-open-main-extra" "--qa-open-main" || fail "prefixed launch argument was accepted"
    commit_has_product_contract WORKTREE
    assert_runbook_contract
    print -- "PASS: ZC-056-009 signed preflight self-test"
    exit 0
fi

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
readonly CANONICAL_APP="${APP:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$CANONICAL_APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null
readonly EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$EXECUTABLE_NAME"
[[ -x "$EXECUTABLE" ]] || fail "signed executable is unavailable"
kill -0 "$EXPECTED_APP_PID" 2>/dev/null || fail "expected app PID is not running"
lsof -Fn -a -p "$EXPECTED_APP_PID" -d txt 2>/dev/null \
    | sed -n 's/^n//p' \
    | grep -Fqx "$EXECUTABLE" \
    || fail "PID is not running the exact signed executable"
readonly APP_COMMAND="$(ps -ww -p "$EXPECTED_APP_PID" -o command=)"
command_has_exact_argument "$APP_COMMAND" "--qa-open-main" || fail "signed app lacks the supported foreground argument"
commit_has_product_contract "$EXPECTED_COMMIT"
assert_runbook_contract
print -- "APP_PID=$EXPECTED_APP_PID"
print -- "PASS: ZC-056-009 signed identity, foreground path, and product contract"
