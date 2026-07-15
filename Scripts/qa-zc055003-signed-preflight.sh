#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b"
readonly ORIGINAL_PRODUCT_CANDIDATE="6d8ec43867e0bf6aee53bb089f0fa7cf508ce870"
readonly PRODUCT_CORRECTION="f260fa8f14d69e49b33e411366a6fc06ddd7dcf2"
readonly TOOLING_CANDIDATE="7efed0f712ffcc35f9f7afb9b3aa136c32e9fc51"
readonly ORIGINAL_PRODUCT_PATCH_ID="764437992c743d0fba4109360a66b3d89c9fff06"
readonly PRODUCT_CORRECTION_PATCH_ID="0a5662a3b0c5c69a5b98a516e6faf2ee1fa83a4a"
readonly TOOLING_PATCH_ID="5226588dbc0b50b5b034e4dabc2e1eecd12a2898"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc055003-keyboard-lifecycle-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc055003-keyboard-lifecycle-fixture.sh"
readonly RUNBOOK="$REPOSITORY/docs/ZC-055-003-SIGNED-QA-RUNBOOK.md"
readonly PRODUCT_FILES=(
    Sources/ZoidCoachApp/TaskKeyboardCommands.swift
    Tests/ZoidCoachAppTests/TaskKeyboardCommandsTests.swift
)
readonly TOOLING_FILES=(
    docs/ZC-055-003-SIGNED-QA-RUNBOOK.md
    Scripts/qa-zc055003-keyboard-lifecycle-ax-probe.swift
    Scripts/qa-zc055003-keyboard-lifecycle-fixture.sh
    Scripts/qa-zc055003-signed-preflight.sh
)
readonly LINEAGE_FILES=(
    docs/ZC-055-003-SIGNED-QA-RUNBOOK.md
    Scripts/qa-zc055003-signed-preflight.sh
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
    git -C "$REPOSITORY" show --pretty=email --no-ext-diff "$1" \
        | git patch-id --stable | awk 'NR == 1 { print $1 }'
}

assert_lineage() {
    local expected="$1"
    local head scope reviewed_scope tooling_scope lineage_scope commit_count
    head="$(git -C "$REPOSITORY" rev-parse HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$expected" ]] || fail "repository HEAD $head does not match signed commit $expected"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$expected" || fail "candidate does not descend from canonical base"
    [[ "$(git -C "$REPOSITORY" rev-parse "$ORIGINAL_PRODUCT_CANDIDATE^")" == "$CANONICAL_BASE" ]] || fail "original product commit is not a direct child of canonical"
    [[ "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CORRECTION^")" == "$ORIGINAL_PRODUCT_CANDIDATE" ]] || fail "product correction is not a direct child of the original product commit"
    [[ "$(git -C "$REPOSITORY" rev-parse "$TOOLING_CANDIDATE^")" == "$PRODUCT_CORRECTION" ]] || fail "tooling commit is not a direct child of the product correction"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected^")" == "$TOOLING_CANDIDATE" ]] || fail "lineage commit is not a direct child of the tooling commit"
    [[ "$(commit_patch_id "$ORIGINAL_PRODUCT_CANDIDATE")" == "$ORIGINAL_PRODUCT_PATCH_ID" ]] || fail "original product patch identity changed"
    [[ "$(commit_patch_id "$PRODUCT_CORRECTION")" == "$PRODUCT_CORRECTION_PATCH_ID" ]] || fail "product correction patch identity changed"
    [[ "$(commit_patch_id "$TOOLING_CANDIDATE")" == "$TOOLING_PATCH_ID" ]] || fail "tooling patch identity changed"

    reviewed_scope="$(printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}")"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE" "$expected")" || fail "candidate scope is unavailable"
    has_exact_lines "$scope" "$reviewed_scope" || fail "signed candidate differs from the exact reviewed six-file scope"
    ! grep -Fqx 'docs/scenario-registry.json' <<<"$scope" || fail "candidate unexpectedly includes scenario registry"
    ! grep -Fqx 'docs/zoid-coach-product-scenario-tracker.md' <<<"$scope" || fail "candidate unexpectedly includes scenario tracker"

    commit_count="$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")"
    [[ "$commit_count" == "4" ]] || fail "candidate must contain product, correction, tooling, and lineage commits"
    tooling_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$TOOLING_CANDIDATE")"
    has_exact_lines "$tooling_scope" "$(printf '%s\n' "${TOOLING_FILES[@]}")" || fail "tooling commit contains unrelated files"
    lineage_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected")"
    has_exact_lines "$lineage_scope" "$(printf '%s\n' "${LINEAGE_FILES[@]}")" || fail "lineage commit contains files outside immutable bindings"
}

assert_runbook_contract() {
    [[ -f "$RUNBOOK" ]] || fail "signed runbook is missing"
    grep -Fq 'CGEvent at the HID event tap' "$RUNBOOK" || fail "runbook does not bind physical keyboard injection"
    local action
    for action in start pause resume switch complete; do
        grep -Eq -- "--send[[:space:]]+$action([[:space:]]|$)" "$RUNBOOK" || fail "runbook omits keyboard action $action"
    done
    grep -Fq -- '--phase ambiguous --send complete' "$RUNBOOK" || fail "runbook omits ambiguous Complete rejection"
    grep -Fq -- '--phase no-active --send complete' "$RUNBOOK" || fail "runbook omits no-active Complete rejection"
    [[ "$(grep -Fc 'assert-root-restored "$QA_ROOT" "$BASELINE_SNAPSHOT"' "$RUNBOOK")" -ge 3 ]] || fail "runbook must prove byte restoration after all three journeys"
    ! grep -Fq 'AXUIElementPerformAction' "$RUNBOOK" || fail "runbook must not substitute AXPress for lifecycle keyboard actions"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "b3ff3d3e8eff70f60301c5be3faffb9c00ccfc2a" || fail "valid SHA was rejected"
    ! is_full_lowercase_sha "B3FF3D3E8EFF70F60301C5BE3FAFFB9C00CCFC2A" || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "b3ff3d3" || fail "abbreviated SHA was accepted"
    command_has_exact_argument "/tmp/Zoid666QA --qa-open-main" "--qa-open-main" || fail "exact QA argument was rejected"
    ! command_has_exact_argument "/tmp/Zoid666QA --qa-open-main-extra" "--qa-open-main" || fail "prefixed QA argument was accepted"
    assert_runbook_contract
    "$FIXTURE" self-test >/dev/null
    swiftc -typecheck "$AX_PROBE"
    swift "$AX_PROBE" --self-test >/dev/null
    assert_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    print -- "PASS: ZC-055-003 signed preflight self-test"
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

[[ "$QA_ROOT" == /private/tmp/zoid-666-zc055003-* ]] || fail "QA root is outside isolated ZC-055-003 namespace"
[[ -x "$APP_EXECUTABLE" ]] || fail "app executable is unavailable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "helper executable is unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] || fail "app and helper do not embed the same QA root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database is not the exact shared app/helper QA database"

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
            fail "installed helper executable is still running before registration"
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
    print -- "PASS: signed candidate identity, lineage, executables, and shared isolated runtime are bound"
fi
