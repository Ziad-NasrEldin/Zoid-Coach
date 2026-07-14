#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PRODUCT_CANDIDATE="03ed2a3ef6e14bd91cb0903d4c8b98be6ecdfa87"
readonly VERIFIER_BASE="0068cd2d9da540818feea90ff1e39fc5270b97ee"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
readonly PRESENTATION_REQUIREMENT="${4:-}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    local command="$1"
    local expected_argument="$2"
    [[ " $command " == *" $expected_argument "* ]]
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "b3ff3d3e8eff70f60301c5be3faffb9c00ccfc2a" \
        || fail "valid SHA was rejected without extendedglob"
    ! is_full_lowercase_sha "B3FF3D3E8EFF70F60301C5BE3FAFFB9C00CCFC2A" \
        || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "b3ff3d3" || fail "abbreviated SHA was accepted"
    command_has_exact_argument "/tmp/ZoidCoachQA --qa-open-main" "--qa-open-main" \
        || fail "exact QA foreground argument was rejected"
    ! command_has_exact_argument "/tmp/ZoidCoachQA --qa-open-main-extra" "--qa-open-main" \
        || fail "prefixed QA foreground argument was accepted"
    print -- "PASS: ZC-044-004 signed preflight validation self-test"
    exit 0
fi

[[ -z "$PRESENTATION_REQUIREMENT" || "$PRESENTATION_REQUIREMENT" == "--require-qa-open-main" ]] \
    || fail "unsupported presentation requirement: $PRESENTATION_REQUIREMENT"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full 40-character lowercase SHA"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"

git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "expected signed commit does not contain product candidate $PRODUCT_CANDIDATE"
git -C "$REPOSITORY" merge-base --is-ancestor "$VERIFIER_BASE" "$EXPECTED_COMMIT" \
    || fail "expected signed commit does not contain verifier base $VERIFIER_BASE"

ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$CANONICAL_APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"

[[ -x "$APP_EXECUTABLE" ]] || fail "app executable is unavailable: $APP_EXECUTABLE"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "helper executable is unavailable: $AGENT_EXECUTABLE"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not embed the same isolated QA root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the exact app/helper QA database: expected $EXPECTED_DATABASE"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT" ]] \
    || fail "helper does not resolve the embedded isolated QA root: $HELPER_RUNTIME"

matching_app_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

app_pid="$(matching_app_pid)" || fail "app is not running from the expected installed bundle"
readonly APP_PID="$app_pid"
if [[ "$PRESENTATION_REQUIREMENT" == "--require-qa-open-main" ]]; then
    readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
    command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
        || fail "installed QA app was not launched through the supported foreground main-window argument"
fi
service="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" \
    || fail "installed helper service is unavailable: $AGENT_LABEL"
readonly SERVICE="$service"
readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "installed helper has no running PID"
lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
    || fail "helper is not running from the expected installed bundle"
lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
    || fail "helper does not hold the exact isolated database open"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: signed candidate identity, executable paths, and isolated app/helper runtime are bound"
