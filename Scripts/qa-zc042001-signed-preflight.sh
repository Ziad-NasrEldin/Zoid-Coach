#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANDIDATE="8cc9f2187e74787c183e444140b8696b8e37e52f"
readonly HONESTY_FIX="cfcae6a2cdec3baca34d1c8a038e72f9bedf03f0"
readonly PROBE="$SCRIPT_DIR/qa-zc042001-evidence-layers-ax-probe.swift"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_ORDINARY_OPEN=0
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
has_argument() { [[ " $1 " == *" $2 "* ]]; }

assert_runbook_order() {
    local runbook="$REPOSITORY/docs/ZC-042-001-SIGNED-QA-RUNBOOK.md"
    local ready launch bind register relaunch_start qa_relaunch ordinary_open ordinary_bind
    ready="$(grep -nF '"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace' "$runbook" | head -n1 | cut -d: -f1)"
    launch="$(awk -v start="$ready" 'NR > start && /^open "\$APP" --args --qa-open-main$/ {print NR; exit}' "$runbook")"
    bind="$(awk -v start="$ready" 'NR > start && /--require-helper-unregistered/ {print NR; exit}' "$runbook")"
    register="$(awk -v start="$ready" 'NR > start && /"\$APP_EXECUTABLE" --qa-register-agent/ {print NR; exit}' "$runbook")"
    [[ "$ready" == <-> && "$launch" == <-> && "$bind" == <-> && "$register" == <-> \
        && ready -lt launch && launch -lt bind && bind -lt register ]] \
        || fail "runbook must bind the initial foreground app before helper registration"
    relaunch_start="$(grep -nF '## Positive persisted evidence' "$runbook" | head -n1 | cut -d: -f1)"
    qa_relaunch="$(awk -v start="$relaunch_start" 'NR > start && /^open "\$APP" --args --qa-open-main$/ {n++} END {print n+0}' "$runbook")"
    ordinary_open="$(awk -v start="$relaunch_start" 'NR > start && /^open "\$APP"$/ {n++} END {print n+0}' "$runbook")"
    ordinary_bind="$(awk -v start="$relaunch_start" 'NR > start && /--require-ordinary-open/ {n++} END {print n+0}' "$runbook")"
    [[ "$qa_relaunch" == 0 && "$ordinary_open" == 4 && "$ordinary_bind" == 4 ]] \
        || fail "runbook must use four bound ordinary relaunches after initial foreground launch"
}

if [[ "$APP" == "--self-test" ]]; then
    is_sha "8cc9f2187e74787c183e444140b8696b8e37e52f" || fail "valid SHA rejected"
    ! is_sha "8CC9F2187E74787C183E444140B8696B8E37E52F" || fail "uppercase SHA accepted"
    has_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "foreground argument rejected"
    ! has_argument "/tmp/Zoid666" "--qa-open-main" || fail "ordinary launch mistaken for foreground launch"
    assert_runbook_order
    "$PROBE" --self-test >/dev/null
    print -- "PASS: ZC-042-001 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main) REQUIRE_QA_OPEN_MAIN=1; shift ;;
        --require-ordinary-open) REQUIRE_ORDINARY_OPEN=1; shift ;;
        --require-helper-unregistered) REQUIRE_HELPER_UNREGISTERED=1; shift ;;
        --expected-app-pid) (( $# >= 2 )) || fail "--expected-app-pid requires a PID"; EXPECTED_APP_PID="$2"; shift 2 ;;
        *) fail "unsupported preflight option: $1" ;;
    esac
done
(( ! REQUIRE_QA_OPEN_MAIN || ! REQUIRE_ORDINARY_OPEN )) || fail "launch requirements are mutually exclusive"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
if (( ! REQUIRE_HELPER_UNREGISTERED )); then [[ -f "$DATABASE" ]] || fail "database is unavailable: $DATABASE"; fi

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
git -C "$REPOSITORY" merge-base --is-ancestor "$CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain candidate $CANDIDATE"
git -C "$REPOSITORY" merge-base --is-ancestor "$HONESTY_FIX" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain limited-evidence honesty fix $HONESTY_FIX"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$CANONICAL_APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "installed executables are unavailable"
[[ "$APP_ROOT" == "$QA_ROOT" && "$AGENT_ROOT" == "$QA_ROOT" ]] || fail "app and helper QA roots differ"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database does not match embedded QA root"

matching_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then print -- "$pid"; return 0; fi
        done
        sleep 0.2
    done
    return 1
}
readonly APP_PID="$(matching_pid)" || fail "installed app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_QA_OPEN_MAIN )); then has_argument "$APP_COMMAND" "--qa-open-main" || fail "foreground argument is absent"; fi
if (( REQUIRE_ORDINARY_OPEN )); then
    ! has_argument "$APP_COMMAND" "--qa-open-main" || fail "ordinary relaunch retained foreground argument"
    swift "$PROBE" --pid "$APP_PID" --phase window >/dev/null || fail "ordinary relaunch has no unique visible main window"
fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || fail "helper registered before foreground binding"
    readonly HELPER_PID="UNREGISTERED"
else
    readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper service unavailable"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "helper PID unavailable"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" || fail "helper executable mismatch"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 || fail "helper does not hold exact database open"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-042-001 signed runtime identity is bound"
