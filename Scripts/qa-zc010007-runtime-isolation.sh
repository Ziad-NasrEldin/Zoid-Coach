#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly APP="${2:-}"
readonly QA_ROOT="${3:-}"
readonly AGENT_LABEL="qa.ziadnasreldin.ZoidCoach.agent"
readonly REQUIRED_QUIET_PASSES=10
readonly MAXIMUM_ATTEMPTS=100
readonly QUIET_DELAY_SECONDS=0.2

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

await_sustained_quiet() {
    local maximum_attempts="$1"
    local required_quiet_passes="$2"
    local delay_seconds="$3"
    shift 3
    local quiet_passes=0 attempt
    for attempt in $(seq 1 "$maximum_attempts"); do
        if "$@"; then
            quiet_passes=$((quiet_passes + 1))
            (( quiet_passes >= required_quiet_passes )) && return 0
        else
            quiet_passes=0
        fi
        (( attempt < maximum_attempts )) && sleep "$delay_seconds"
    done
    return 1
}

executable_for_pid() {
    lsof -Fn -a -p "$1" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1
}

helper_iteration_is_quiet() {
    local agent_executable="$APP/Contents/MacOS/ZoidCoachAgentQA"
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
    local pid executable process_environment found=0
    for pid in ${(f)"$(pgrep -f ZoidCoachAgentQA 2>/dev/null || true)"}; do
        [[ -n "$pid" ]] || continue
        executable="$(executable_for_pid "$pid")"
        [[ "$executable" == "$agent_executable" ]] || continue
        process_environment="$(ps eww -p "$pid" -o command= 2>/dev/null || true)"
        [[ " $process_environment " == *" ZOID_COACH_QA_RUN_ROOT=$QA_ROOT "* ]] \
            || fail "exact QA helper executable has a mismatched QA root: pid=$pid"
        kill "$pid" >/dev/null 2>&1 || true
        found=1
    done
    launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 && found=1
    (( found == 0 ))
}

app_iteration_is_quiet() {
    local app_executable_name app_executable pid executable found=0
    app_executable_name="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
    app_executable="$APP/Contents/MacOS/$app_executable_name"
    for pid in ${(f)"$(pgrep -f "$app_executable_name" 2>/dev/null || true)"}; do
        [[ -n "$pid" ]] || continue
        executable="$(executable_for_pid "$pid")"
        [[ "$executable" == "$app_executable" ]] || continue
        kill "$pid" >/dev/null 2>&1 || true
        found=1
    done
    (( found == 0 ))
}

stop_helper() {
    [[ -d "$APP" && -n "$QA_ROOT" ]] || fail "stop-helper requires an installed QA app and root"
    await_sustained_quiet \
        "$MAXIMUM_ATTEMPTS" "$REQUIRED_QUIET_PASSES" "$QUIET_DELAY_SECONDS" \
        helper_iteration_is_quiet \
        || fail "exact QA helper did not remain absent for the sustained quiet window"
    print -- "PASS: exact QA helper label/process remained absent for $REQUIRED_QUIET_PASSES checks"
}

stop_app() {
    [[ -d "$APP" ]] || fail "stop-app requires an installed QA app"
    await_sustained_quiet \
        "$MAXIMUM_ATTEMPTS" "$REQUIRED_QUIET_PASSES" "$QUIET_DELAY_SECONDS" \
        app_iteration_is_quiet \
        || fail "exact QA app did not remain absent for the sustained quiet window"
    print -- "PASS: exact QA app remained absent for $REQUIRED_QUIET_PASSES checks"
}

typeset -gi SELF_TEST_PROBE_INDEX=0

delayed_reappearance_probe() {
    SELF_TEST_PROBE_INDEX=$((SELF_TEST_PROBE_INDEX + 1))
    (( SELF_TEST_PROBE_INDEX == 2 )) && return 1
    return 0
}

never_quiet_probe() {
    return 1
}

self_test() {
    SELF_TEST_PROBE_INDEX=0
    await_sustained_quiet 5 3 0 delayed_reappearance_probe \
        || fail "delayed reappearance did not restart and complete the quiet window"
    (( SELF_TEST_PROBE_INDEX == 5 )) \
        || fail "quiet window did not reset after delayed reappearance"
    if await_sustained_quiet 3 2 0 never_quiet_probe; then
        fail "never-quiet probe did not time out"
    fi
    print -- "PASS: ZC-010-007 sustained runtime isolation self-test"
}

case "$COMMAND" in
    stop-helper) stop_helper ;;
    stop-app) stop_app ;;
    --self-test) self_test ;;
    *) fail "usage: $0 {stop-helper|stop-app} APP QA_ROOT | --self-test" ;;
esac
