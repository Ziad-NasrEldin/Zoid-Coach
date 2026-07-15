#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="b97c2ce3177ccf89f60225c475062608db1920ad"
readonly TOOLING_CANDIDATE="37de851fb06299fd3878bb84c5c3728898304fc5"
readonly PRODUCT_CANDIDATE="51fdd09c0a996e9819ee4a8d8f3cd0a6bccd1771"
readonly TOOLING_PATCH_ID="9a9cad283c5216b12cb4ecaf698526de4e50e8b3"
readonly PRODUCT_PATCH_ID="f07976b068b580063b2dbdec5b05505e5944a5bd"
readonly INPUT_BLOB="bed2a04559d1db66706622e9d8ec5288d458b138"
readonly INPUT_TEST_BLOB="7858f5b20d1ddbb9f357a5f2d71beaeeb4c56180"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc011007-invalid-estimate-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc011007-invalid-estimate-fixture.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-011-007-SIGNED-QA-RUNBOOK.md"
readonly TOOLING_FILES=(
    Scripts/qa-zc011007-invalid-estimate-ax-probe.swift
    Scripts/qa-zc011007-invalid-estimate-fixture.sh
    Scripts/qa-zc011007-signed-preflight.sh
    docs/ZC-011-007-SIGNED-QA-RUNBOOK.md
)
readonly PRODUCT_FILES=(
    Sources/ZoidCoachApp/Views/CustomEstimateEditor.swift
    Sources/ZoidCoachApp/Views/DashboardView.swift
    Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
    Tests/ZoidCoachAppTests/CustomEstimateEditorStateTests.swift
)
readonly BINDING_FILES=(
    Scripts/qa-zc011007-invalid-estimate-ax-probe.swift
    Scripts/qa-zc011007-signed-preflight.sh
    docs/ZC-011-007-SIGNED-QA-RUNBOOK.md
)

APP="${1:-}"
DATABASE="${2:-}"
EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_ORDINARY_OPEN=0
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    local command="$1"
    local expected="$2"
    [[ " $command " == *" $expected "* ]]
}

normalized_lines() {
    print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u
}

has_exact_lines() {
    [[ "$(normalized_lines "$1")" == "$(normalized_lines "$2")" ]]
}

commit_patch_id() {
    git -C "$REPOSITORY" show --pretty=format: --binary "$1" | git patch-id --stable | awk 'NR == 1 { print $1 }'
}

assert_lineage() {
    local expected="$1"
    local head scope reviewed_scope head_scope product_scope tooling_scope commit_count file
    head="$(git -C "$REPOSITORY" rev-parse HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$expected" ]] || fail "repository HEAD $head does not match signed commit $expected"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$expected" || fail "candidate does not descend from canonical base"
    [[ "$(git -C "$REPOSITORY" rev-parse "$TOOLING_CANDIDATE^")" == "$CANONICAL_BASE" ]] || fail "tooling candidate does not directly follow canonical base"
    [[ "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE^")" == "$TOOLING_CANDIDATE" ]] || fail "product candidate does not directly follow tooling replay"
    [[ "$(commit_patch_id "$TOOLING_CANDIDATE")" == "$TOOLING_PATCH_ID" ]] || fail "replayed QA tooling patch identity drifted"
    [[ "$(commit_patch_id "$PRODUCT_CANDIDATE")" == "$PRODUCT_PATCH_ID" ]] || fail "reviewed product patch identity drifted"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected:Sources/ZoidCoachApp/TaskEstimateInput.swift")" == "$INPUT_BLOB" ]] || fail "TaskEstimateInput product blob changed"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected:Tests/ZoidCoachAppTests/TaskEstimateInputTests.swift")" == "$INPUT_TEST_BLOB" ]] || fail "focused product tests changed"
    for file in "${PRODUCT_FILES[@]}"; do
        [[ "$(git -C "$REPOSITORY" rev-parse "$expected:$file")" == "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE:$file")" ]] \
            || fail "reviewed product file changed after acceptance: $file"
    done

    reviewed_scope="$(printf '%s\n' "${TOOLING_FILES[@]}" "${PRODUCT_FILES[@]}")"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE" "$expected")" || fail "candidate scope is unavailable"
    has_exact_lines "$scope" "$reviewed_scope" || fail "signed candidate differs from exact reviewed product and QA scope"
    ! grep -Fqx 'docs/scenario-registry.json' <<<"$scope" || fail "candidate unexpectedly includes scenario registry"
    ! grep -Fqx 'docs/zoid-coach-product-scenario-tracker.md' <<<"$scope" || fail "candidate unexpectedly includes scenario tracker"
    ! grep -Fqx 'docs/impl/666-BACKLOG.md' <<<"$scope" || fail "candidate unexpectedly includes shared backlog"

    commit_count="$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")"
    [[ "$commit_count" == "3" ]] || fail "candidate must contain tooling replay, product fix, and lineage binding commits"
    tooling_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$TOOLING_CANDIDATE")"
    has_exact_lines "$tooling_scope" "$(printf '%s\n' "${TOOLING_FILES[@]}")" || fail "QA tooling replay contains unrelated files"
    product_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$PRODUCT_CANDIDATE")"
    has_exact_lines "$product_scope" "$(printf '%s\n' "${PRODUCT_FILES[@]}")" || fail "product commit contains unrelated files"
    head_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected")"
    has_exact_lines "$head_scope" "$(printf '%s\n' "${BINDING_FILES[@]}")" || fail "lineage binding commit contains unrelated files"
}

assert_runbook_contract() {
    [[ -f "$RUNBOOK" ]] || fail "signed runbook is missing"
    local case_name
    for case_name in empty whitespace unicode-whitespace zero negative decimal text localized-digits localized-decimal too-large; do
        grep -Fq -- "run_invalid_case $case_name" "$RUNBOOK" || fail "runbook omits estimate case $case_name"
    done
    grep -Fq -- '--phase submit --case valid-padded' "$RUNBOOK" || fail "runbook omits valid padded recovery"
    grep -Fq 'physical Return key event at the HID event tap' "$RUNBOOK" || fail "runbook does not bind keyboard Return submission"
    grep -Fq 'set -o pipefail' "$RUNBOOK" || fail "runbook does not prevent evidence tee from masking probe failure"
    grep -Fq 'probe_status=0' "$RUNBOOK" || fail "runbook does not capture each probe exit status"
    grep -Fq '(( probe_status == 0 )) || return "$probe_status"' "$RUNBOOK" || fail "runbook does not abort before database assertion"
    grep -Fq 'retained input and focus after failure' "$RUNBOOK" || fail "runbook omits focus-retention acceptance"
    grep -Fq '"$FIXTURE" assert-unmutated "$DATABASE"' "$RUNBOOK" || fail "runbook omits no-mutation assertions"
    grep -Fq '"$FIXTURE" assert-valid "$DATABASE"' "$RUNBOOK" || fail "runbook omits valid recovery assertion"
    grep -Fq -- '--require-ordinary-open' "$RUNBOOK" || fail "runbook omits ordinary relaunch binding"
    grep -Fq 'restore-root "$QA_ROOT" "$BASELINE_SNAPSHOT"' "$RUNBOOK" || fail "runbook omits byte restoration"
    grep -Fq 'assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"' "$RUNBOOK" || fail "runbook omits restored-root comparison"
    grep -Fq "$CANONICAL_BASE" "$RUNBOOK" || fail "runbook omits canonical base"
    grep -Fq "$TOOLING_CANDIDATE" "$RUNBOOK" || fail "runbook omits tooling candidate"
    grep -Fq "$PRODUCT_CANDIDATE" "$RUNBOOK" || fail "runbook omits product candidate"
    grep -Fq "$TOOLING_PATCH_ID" "$RUNBOOK" || fail "runbook omits tooling patch identity"
    grep -Fq "$PRODUCT_PATCH_ID" "$RUNBOOK" || fail "runbook omits product patch identity"
    grep -Fq 'CustomEstimateEditorStateTests' "$RUNBOOK" || fail "runbook omits shared interaction-state tests"
}

assert_concurrent_fixture_self_tests() {
    local first_pid second_pid
    "$FIXTURE" self-test >/dev/null &
    first_pid=$!
    "$FIXTURE" self-test >/dev/null &
    second_pid=$!
    wait "$first_pid" || fail "first concurrent fixture self-test failed"
    wait "$second_pid" || fail "second concurrent fixture self-test failed"
}

assert_probe_failure_is_not_masked() {
    local assertion_called=0
    simulated_probe_failure() { return 7; }
    simulated_database_assertion() { assertion_called=1; return 0; }
    simulated_case_runner() {
        local probe_status=0
        simulated_probe_failure || probe_status=$?
        (( probe_status == 0 )) || return "$probe_status"
        simulated_database_assertion
    }
    if simulated_case_runner; then
        fail "successful database assertion masked a failed probe"
    fi
    [[ "$assertion_called" == "0" ]] || fail "database assertion ran after failed probe"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "b3ff3d3e8eff70f60301c5be3faffb9c00ccfc2a" || fail "valid SHA was rejected"
    ! is_full_lowercase_sha "B3FF3D3E8EFF70F60301C5BE3FAFFB9C00CCFC2A" || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "b3ff3d3" || fail "abbreviated SHA was accepted"
    command_has_exact_argument "/tmp/Zoid666QA --qa-open-main" "--qa-open-main" || fail "exact QA argument was rejected"
    ! command_has_exact_argument "/tmp/Zoid666QA --qa-open-main-extra" "--qa-open-main" || fail "prefixed QA argument was accepted"
    assert_runbook_contract
    "$FIXTURE" self-test >/dev/null
    assert_concurrent_fixture_self_tests
    assert_probe_failure_is_not_masked
    swiftc -typecheck "$AX_PROBE"
    swift "$AX_PROBE" --self-test >/dev/null
    print -- "PASS: ZC-011-007 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main)
            REQUIRE_QA_OPEN_MAIN=1
            shift
            ;;
        --require-ordinary-open)
            REQUIRE_ORDINARY_OPEN=1
            shift
            ;;
        --require-helper-unregistered)
            REQUIRE_HELPER_UNREGISTERED=1
            shift
            ;;
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        *)
            fail "unsupported preflight option: $1"
            ;;
    esac
done

(( ! REQUIRE_QA_OPEN_MAIN || ! REQUIRE_ORDINARY_OPEN )) || fail "QA and ordinary launch requirements are mutually exclusive"
[[ "$EXPECTED_APP_PID" == "" || "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
if (( ! REQUIRE_HELPER_UNREGISTERED )); then
    [[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
fi
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_lineage "$EXPECTED_COMMIT"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"

ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$CANONICAL_APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"

[[ "$QA_ROOT" == /private/tmp/zoid-666-zc011007-* ]] || fail "QA root is outside isolated ZC-011-007 namespace"
[[ -x "$APP_EXECUTABLE" ]] || fail "app executable is unavailable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "helper executable is unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] || fail "app and helper do not embed same QA root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database is not exact shared app/helper QA database"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT" ]] || fail "helper does not resolve embedded QA root"

matching_app_pids() {
    local pid
    for _ in {1..50}; do
        local matches=()
        for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
                matches+=("$pid")
            fi
        done
        if (( ${#matches} == 1 )); then
            print -- "${matches[1]}"
            return 0
        fi
        (( ${#matches} == 0 )) || fail "multiple installed candidate app processes are running"
        sleep 0.2
    done
    return 1
}

app_pid="$(matching_app_pids)" || fail "app is not running from expected installed bundle"
readonly APP_PID="$app_pid"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "foreground app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_QA_OPEN_MAIN )); then
    command_has_exact_argument "$APP_COMMAND" "--qa-open-main" || fail "app was not launched through supported foreground argument"
fi
if (( REQUIRE_ORDINARY_OPEN )); then
    ! command_has_exact_argument "$APP_COMMAND" "--qa-open-main" || fail "ordinary relaunch retained QA foreground argument"
    swift "$SCRIPT_DIR/qa-window-content-probe.swift" "$APP_PID" --expect-today >/dev/null || fail "ordinary relaunch did not restore Today"
fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || fail "helper is registered before foreground binding"
    for helper_pid in ${(f)"$(pgrep -x "${AGENT_EXECUTABLE:t}" 2>/dev/null || true)"}; do
        if lsof -Fn -a -p "$helper_pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE"; then
            fail "installed helper is still running before registration"
        fi
    done
    readonly HELPER_PID="UNREGISTERED"
else
    service="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "installed helper service is unavailable"
    readonly SERVICE="$service"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "installed helper has no running PID"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" || fail "helper is not running from installed bundle"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 || fail "helper does not hold exact QA database"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
if (( REQUIRE_HELPER_UNREGISTERED )); then
    print -- "PASS: signed foreground app is bound before helper registration"
else
    print -- "PASS: signed candidate identity, unchanged product blobs, executables, and isolated runtime are bound"
fi
