#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PARENT_TECHNICAL_CONTEXT="a17f1c2c697b769dc80af959b2385d418d8074c8"

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

assert_runbook_shell_blocks_fail_fast() {
    local runbook="$REPOSITORY/docs/ZC-061-002-SIGNED-QA-RUNBOOK.md"
    [[ -f "$runbook" ]] || fail "signed QA runbook is missing"
    awk '
        /^```sh$/ { checking = 1; found = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking || !found) exit 1 }
    ' "$runbook" || fail "every runbook shell block must begin with set -euo pipefail"
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_full_lowercase_sha "$PARENT_TECHNICAL_CONTEXT" || fail "parent technical-context SHA is invalid"
    is_full_lowercase_sha "0123456789abcdef0123456789abcdef01234567" || fail "valid SHA rejected"
    ! is_full_lowercase_sha "0123456" || fail "abbreviated SHA accepted"
    command_has_exact_argument "/tmp/ZoidCoach --qa-open-main" "--qa-open-main" || fail "exact foreground argument rejected"
    ! command_has_exact_argument "/tmp/ZoidCoach --qa-open-main-extra" "--qa-open-main" || fail "prefixed foreground argument accepted"
    git -C "$REPOSITORY" cat-file -e "$PARENT_TECHNICAL_CONTEXT^{commit}" || fail "parent technical-context commit is unavailable"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc061002-related-tutorial-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc061002-related-tutorial-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-061-002 signed preflight self-test"
    exit 0
fi

(( $# == 3 )) || fail "usage: $0 --self-test | <app> <database> <expected-signed-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly EXPECTED_COMMIT="$3"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected signed commit must be a full lowercase SHA"
git -C "$REPOSITORY" merge-base --is-ancestor "$PARENT_TECHNICAL_CONTEXT" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain the technical-context parent"

ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
[[ -x "$EXECUTABLE" ]] || fail "signed app executable is unavailable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "signed helper executable is unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not share the isolated QA root"
[[ "${DATABASE:A}" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the exact app/helper QA database: $EXPECTED_DATABASE"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT"* ]] \
    || fail "helper does not resolve the isolated QA runtime"

matching_app_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

app_pid="$(matching_app_pid)" || fail "app is not running from the expected signed bundle"
readonly APP_PID="$app_pid"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
    || fail "signed app was not launched with the supported foreground argument"
service="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" \
    || fail "installed helper service is unavailable"
readonly SERVICE="$service"
readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "installed helper has no running PID"
lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
    || fail "running helper does not belong to the signed bundle"
lsof -a -p "$HELPER_PID" "$DATABASE" >/dev/null 2>&1 \
    || fail "running helper does not hold the exact isolated database"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=${DATABASE:A}"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PARENT_TECHNICAL_CONTEXT=$PARENT_TECHNICAL_CONTEXT"
print -- "PASS: signed candidate, technical-context parent, and isolated app/helper database are bound"
