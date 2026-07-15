#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANDIDATE="ce8f8d9c00f100dae55595a1ac995592ec381ed0"
readonly PROBE="$SCRIPT_DIR/qa-zc048010-diagnostic-package-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc048010-diagnostic-package-fixture.sh"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
readonly EVIDENCE_ROOT="${4:-}"
shift $(( $# < 4 ? $# : 4 ))
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_HELPER_UNREGISTERED=0
WAIT_FOR_FOREGROUND_DATABASE=0
EXPECTED_APP_PID=""

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
has_argument() { [[ " $1 " == *" $2 "* ]]; }
is_visible_foreground_command() {
    has_argument "$1" "--qa-open-main" && ! has_argument "$1" "--background-schedule"
}
is_external_path() {
    local candidate="${1:A}"
    [[ "$candidate" != "$REPOSITORY" && "$candidate" != "$REPOSITORY"/* ]]
}
exact_pid_is_running() {
    local pid="$1"
    local expected_executable="$2"
    kill -0 "$pid" 2>/dev/null || return 3
    lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$expected_executable" \
        || return 5
}
database_is_open_readable() {
    local database="$1"
    [[ -f "$database" ]] || return 1
    sqlite3 -readonly "$database" 'PRAGMA schema_version;' >/dev/null 2>&1
}
readiness_sleep() { sleep 0.1; }
wait_for_foreground_database() {
    local pid="$1"
    local expected_executable="$2"
    local database="$3"
    local expected_database="$4"
    local pid_probe="${5:-exact_pid_is_running}"
    local database_probe="${6:-database_is_open_readable}"
    local sleeper="${7:-readiness_sleep}"
    local maximum_attempts="${8:-300}"
    local attempt readiness_result
    [[ "${database:A}" == "${expected_database:A}" ]] || return 2
    for attempt in {1..$maximum_attempts}; do
        "$pid_probe" "$pid" "$expected_executable" "$attempt" || {
            readiness_result=$?
            return "$readiness_result"
        }
        if "$database_probe" "$database" "$attempt"; then
            return 0
        fi
        (( attempt < maximum_attempts )) && "$sleeper" "$attempt"
    done
    return 4
}
test_pid_probe() {
    [[ "${READINESS_TEST_CASE:-}" != "pid-exit" || "$3" -lt 2 ]] || return 3
}
test_database_probe() {
    [[ "${READINESS_TEST_CASE:-}" == "delayed-success" && "$2" -ge 3 ]]
}
test_readiness_sleep() { :; }
assert_readiness_self_tests() {
    local readiness_result
    READINESS_TEST_CASE="delayed-success"
    wait_for_foreground_database 41 /tmp/ZoidCoachQA /tmp/qa/zoid-coach.sqlite \
        /tmp/qa/zoid-coach.sqlite test_pid_probe test_database_probe test_readiness_sleep 4 \
        || fail "delayed database readiness was rejected"
    READINESS_TEST_CASE="never-appears"
    if wait_for_foreground_database 41 /tmp/ZoidCoachQA /tmp/qa/zoid-coach.sqlite \
        /tmp/qa/zoid-coach.sqlite test_pid_probe test_database_probe test_readiness_sleep 3; then
        fail "database readiness timeout was accepted"
    else
        readiness_result=$?
        [[ "$readiness_result" == 4 ]] || fail "database readiness timeout returned $readiness_result"
    fi
    READINESS_TEST_CASE="pid-exit"
    if wait_for_foreground_database 41 /tmp/ZoidCoachQA /tmp/qa/zoid-coach.sqlite \
        /tmp/qa/zoid-coach.sqlite test_pid_probe test_database_probe test_readiness_sleep 4; then
        fail "foreground PID exit was accepted"
    else
        readiness_result=$?
        [[ "$readiness_result" == 3 ]] || fail "foreground PID exit returned $readiness_result"
    fi
    READINESS_TEST_CASE="delayed-success"
    if wait_for_foreground_database 41 /tmp/ZoidCoachQA /tmp/wrong/zoid-coach.sqlite \
        /tmp/qa/zoid-coach.sqlite test_pid_probe test_database_probe test_readiness_sleep 4; then
        fail "wrong database root was accepted"
    else
        readiness_result=$?
        [[ "$readiness_result" == 2 ]] || fail "wrong database root returned $readiness_result"
    fi
    unset READINESS_TEST_CASE
}
assert_shared_main_window_contract() {
    local source="$REPOSITORY/Sources/ZoidCoachApp/ApplicationLaunchPresentation.swift"
    local tests="$REPOSITORY/Tests/ZoidCoachAppTests/ApplicationLaunchPresentationTests.swift"
    local open_line activate_line reuse_line foreground_line request_line
    open_line="$(grep -nF '    func open() {' "$source" | head -n1 | cut -d: -f1)"
    activate_line="$(awk -v start="$open_line" 'NR > start && /activateApplication\(\)/ { print NR; exit }' "$source")"
    reuse_line="$(awk -v start="$open_line" 'NR > start && /MainApplicationWindowSelector.select\(from: availableWindows\(\)\)/ { print NR; exit }' "$source")"
    foreground_line="$(awk -v start="$open_line" 'NR > start && /foregroundWindow\(mainWindow.windowNumber\)/ { print NR; exit }' "$source")"
    request_line="$(awk -v start="$open_line" 'NR > start && /requestMainWindow\(\)/ { print NR; exit }' "$source")"
    [[ "$open_line" == <-> && "$activate_line" == <-> && "$reuse_line" == <-> \
        && "$foreground_line" == <-> && "$request_line" == <-> \
        && open_line -lt activate_line && activate_line -lt reuse_line \
        && reuse_line -lt foreground_line && foreground_line -lt request_line ]] \
        || fail "QA main opening must reuse an existing main scene before requesting another"
    rg -F '@Test func qaMainWindowLaunchReusesExistingMainWithoutRequestingDuplicate()' "$tests" >/dev/null \
        || fail "shared QA main-window reuse test is absent"
    rg -F '#expect(events == ["activate", "foreground-42"])' "$tests" >/dev/null \
        || fail "shared QA main-window reuse assertion is absent"
    rg -F 'selectMainWindow([main, fallback]) == .ambiguous' "$PROBE" >/dev/null \
        || fail "real duplicate main-window rejection is absent"
}
assert_runbook_order() {
    local runbook="$REPOSITORY/docs/ZC-048-010-SIGNED-QA-RUNBOOK.md"
    local install unregister terminate ready launch initial_bind database_ready register same_pid preview cancel prepare save inspect existing retry finder cleanup
    install="$(grep -nF 'Scripts/install-signed-qa-runtime.sh' "$runbook" | head -n1 | cut -d: -f1)"
    unregister="$(grep -nF '"$APP_EXECUTABLE" --qa-unregister-agent' "$runbook" | head -n1 | cut -d: -f1)"
    terminate="$(grep -nF 'kill "$candidate"' "$runbook" | head -n1 | cut -d: -f1)"
    ready="$(grep -nF '"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace' "$runbook" | head -n1 | cut -d: -f1)"
    launch="$(grep -nF 'open "$APP" --args --qa-open-main' "$runbook" | head -n1 | cut -d: -f1)"
    initial_bind="$(grep -nF -- '--require-qa-open-main --require-helper-unregistered' "$runbook" | head -n1 | cut -d: -f1)"
    database_ready="$(grep -nF -- '--wait-for-foreground-database' "$runbook" | head -n1 | cut -d: -f1)"
    register="$(grep -nF '"$APP_EXECUTABLE" --qa-register-agent' "$runbook" | head -n1 | cut -d: -f1)"
    same_pid="$(grep -nF -- '--require-qa-open-main --expected-app-pid "$PID"' "$runbook" | head -n1 | cut -d: -f1)"
    preview="$(grep -nF -- '--phase preview' "$runbook" | head -n1 | cut -d: -f1)"
    cancel="$(grep -nF -- '--phase cancel' "$runbook" | head -n1 | cut -d: -f1)"
    prepare="$(grep -nF '"$FIXTURE" prepare "$DATABASE"' "$runbook" | head -n1 | cut -d: -f1)"
    save="$(grep -nF -- '--phase save' "$runbook" | head -n1 | cut -d: -f1)"
    inspect="$(grep -nF '"$FIXTURE" assert-package "$DATABASE" "$PACKAGE"' "$runbook" | head -n1 | cut -d: -f1)"
    existing="$(grep -nF 'Existing-destination rejection' "$runbook" | head -n1 | cut -d: -f1)"
    retry="$(grep -nF 'Fresh retry' "$runbook" | head -n1 | cut -d: -f1)"
    finder="$(grep -nF -- '--phase finder' "$runbook" | head -n1 | cut -d: -f1)"
    cleanup="$(grep -nF '"$FIXTURE" cleanup "$DATABASE"' "$runbook" | tail -n1 | cut -d: -f1)"
    [[ "$install" == <-> && "$unregister" == <-> && "$terminate" == <-> && "$ready" == <-> \
        && "$launch" == <-> && "$initial_bind" == <-> && "$database_ready" == <-> && "$register" == <-> && "$same_pid" == <-> \
        && "$preview" == <-> && "$cancel" == <-> && "$prepare" == <-> && "$save" == <-> \
        && "$inspect" == <-> && "$existing" == <-> && "$retry" == <-> && "$finder" == <-> && "$cleanup" == <-> \
        && install -lt unregister && unregister -lt terminate && terminate -lt ready && ready -lt launch \
        && launch -lt initial_bind && initial_bind -lt database_ready && database_ready -lt register \
        && register -lt same_pid && same_pid -lt preview \
        && preview -lt cancel && cancel -lt prepare && prepare -lt save && save -lt inspect \
        && inspect -lt existing && existing -lt retry && retry -lt finder && finder -lt cleanup ]] \
        || fail "runbook must bind the foreground app before helper registration and preserve every acceptance phase"
}

if [[ "$APP" == "--self-test" ]]; then
    is_sha "$CANDIDATE" || fail "candidate SHA rejected"
    ! is_sha "${CANDIDATE:u}" || fail "uppercase SHA accepted"
    is_visible_foreground_command "/tmp/ZoidCoachQA --qa-open-main" || fail "foreground command rejected"
    ! is_visible_foreground_command "/tmp/ZoidCoachQA --background-schedule" || fail "background command accepted"
    ! is_visible_foreground_command "/tmp/ZoidCoachQA --qa-open-main --background-schedule" || fail "mixed background command accepted"
    is_external_path "/private/tmp/zoid-zc048010-evidence" || fail "external evidence root rejected"
    ! is_external_path "$REPOSITORY/.audit/zc048010" || fail "repository evidence root accepted"
    assert_readiness_self_tests
    assert_shared_main_window_contract
    assert_runbook_order
    "$FIXTURE" self-test >/dev/null
    "$PROBE" --self-test >/dev/null
    print -- "PASS: ZC-048-010 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main) REQUIRE_QA_OPEN_MAIN=1; shift ;;
        --require-helper-unregistered) REQUIRE_HELPER_UNREGISTERED=1; shift ;;
        --wait-for-foreground-database) WAIT_FOR_FOREGROUND_DATABASE=1; shift ;;
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        *) fail "unsupported preflight option: $1" ;;
    esac
done

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ -n "$EVIDENCE_ROOT" ]] || fail "external evidence root is required"
is_external_path "$EVIDENCE_ROOT" || fail "evidence root must remain outside the repository"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly CANONICAL_EVIDENCE="${EVIDENCE_ROOT:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"

git -C "$REPOSITORY" merge-base --is-ancestor "$CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain ZC-048-010 candidate $CANDIDATE"
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
(( ! REQUIRE_HELPER_UNREGISTERED || WAIT_FOR_FOREGROUND_DATABASE )) \
    || fail "helper-absent binding requires foreground database readiness"

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
readonly APP_PID="$(matching_pid)" || fail "installed app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "visible app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
! has_argument "$APP_COMMAND" "--background-schedule" || fail "app process is background-only"
if (( REQUIRE_QA_OPEN_MAIN )); then
    has_argument "$APP_COMMAND" "--qa-open-main" || fail "visible foreground argument is absent"
fi
if (( WAIT_FOR_FOREGROUND_DATABASE )); then
    if wait_for_foreground_database "$APP_PID" "$APP_EXECUTABLE" "$CANONICAL_DATABASE" "$EXPECTED_DATABASE"; then
        :
    else
        readiness_status=$?
        case "$readiness_status" in
            2) fail "database does not match embedded QA root" ;;
            3) fail "foreground app exited before database readiness" ;;
            4) fail "isolated database did not become readable before timeout" ;;
            5) fail "foreground PID executable changed before database readiness" ;;
            *) fail "foreground database readiness failed with status $readiness_status" ;;
        esac
    fi
fi
if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || fail "helper registered before foreground binding"
    readonly HELPER_PID="UNREGISTERED"
else
    readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper service unavailable"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "helper PID unavailable"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper executable mismatch"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the exact database open"
fi
mkdir -p "$CANONICAL_EVIDENCE"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "EVIDENCE_ROOT=$CANONICAL_EVIDENCE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-048-010 signed runtime identity is bound"
