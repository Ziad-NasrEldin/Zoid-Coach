#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="361093b4a088c19eee927eaab2b58a40fb3b4c27"
readonly PRODUCT_CANDIDATE="c8ea11afe0d479269fa21d697dd63a5f80688019"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

assert_runbook_order() {
    local runbook="$REPOSITORY/docs/ZC-006-001-SIGNED-QA-RUNBOOK.md"
    local ready_line app_line helper_line
    ready_line="$(/usr/bin/grep -nF '"$READY_STATE" "$MANIFEST" "$QA_ROOT" --replace' "$runbook" | /usr/bin/head -1 | /usr/bin/cut -d: -f1)"
    app_line="$(/usr/bin/awk -v start="$ready_line" 'NR > start && /open "\$APP" --args --qa-open-main/ { print NR; exit }' "$runbook")"
    helper_line="$(/usr/bin/awk -v start="$ready_line" 'NR > start && /"\$APP_EXECUTABLE" --qa-register-agent/ { print NR; exit }' "$runbook")"
    [[ "$ready_line" == <-> && "$app_line" == <-> && "$helper_line" == <-> && app_line -lt helper_line ]] \
        || fail "runbook must prepare, launch and bind foreground, then register helper"
}

assert_fail_fast_blocks() {
    local runbook="$REPOSITORY/docs/ZC-006-001-SIGNED-QA-RUNBOOK.md"
    /usr/bin/awk '
        /^```sh$/ { checking = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking) exit 1 }
    ' "$runbook" || fail "every runbook shell block must fail fast"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$CANONICAL_BASE" || fail "canonical base is not a full SHA"
    is_full_sha "$PRODUCT_CANDIDATE" || fail "product candidate is not a full SHA"
    ! is_full_sha "c8ea11a" || fail "abbreviated SHA was accepted"
    assert_runbook_order
    assert_fail_fast_blocks
    print -- "PASS: ZC-006-001 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-helper-unregistered)
            REQUIRE_HELPER_UNREGISTERED=1
            shift
            ;;
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        *) fail "unsupported preflight option: $1" ;;
    esac
done

[[ -d "$APP" ]] || fail "signed app does not exist"
[[ "$EXPECTED_APP_PID" == "" || "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
is_full_sha "$EXPECTED_COMMIT" || fail "expected signed commit must be a full lowercase SHA"
git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain the current canonical base"
git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain product candidate"
readonly TOOLING_COMMIT="$(git -C "$REPOSITORY" log -1 --format=%H -- "$0")"
is_full_sha "$TOOLING_COMMIT" || fail "tooling commit cannot be resolved"
git -C "$REPOSITORY" merge-base --is-ancestor "$TOOLING_COMMIT" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain this verifier tooling"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
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
[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "installed executables are unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not share the isolated root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database is not the embedded isolated database"

matching_pid() {
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

APP_PID="$(matching_pid)" || fail "exact installed app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "app PID changed"
if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || fail "helper registered too early"
    HELPER_PID="UNREGISTERED"
else
    SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper service unavailable"
    HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "helper PID unavailable"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper executable mismatch"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the isolated database"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-006-001 signed identity and isolated runtime are bound"
