#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly ORIGINAL_PRODUCT_CANDIDATE="730677a66c265823ef9417af8abe55a8f0b0e998"
readonly CURRENT_PRODUCT_CANDIDATE="c552ea29472ccb1de30a7f896e30f159003aa374"
readonly ORIGINAL_TOOLING_CANDIDATE="39baf022157b53f36a96e1370b3342ed3793c65f"
readonly CURRENT_TOOLING_CANDIDATE="e659575a3ecfcc9379e0c97332b32da4c5fd9ba7"
readonly CURRENT_BASELINE_FIX="5482a1ed6bb7b73a255137937f0f458e9dd68294"
readonly PRODUCT_PATCH_ID="b19bb45f10aa9dabcb1bde528139a75c3ef2f05f"
readonly TOOLING_PATCH_ID="1570803ab40dc2f57785fb23babd984c93d3fc32"
readonly BASELINE_FIX_PATCH_ID="467749eff5875502ea2f5a7c45276a4e6024806c"
readonly CANONICAL_BASE="15d8e6ec42bf178e9de2ee055dd6915c8c74b786"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc025006-ambiguity-ax-probe.swift"
readonly RUNBOOK="$REPOSITORY/docs/ZC-025-006-SIGNED-QA-RUNBOOK.md"
readonly PRODUCT_FILES=(
    Sources/ZoidCoachAgent/AgentMain.swift
    Sources/ZoidCoachApp/DashboardPromptActionOutcome.swift
    Sources/ZoidCoachCore/PromptInbox.swift
    Sources/ZoidCoachInfrastructure/AmbiguousActivityPromptService.swift
    Sources/ZoidCoachInfrastructure/PromptResponseEffectRouter.swift
    Tests/ZoidCoachAppTests/AmbiguousActivityPromptServiceTests.swift
    Tests/ZoidCoachAppTests/DashboardPromptTaskStartTests.swift
    Tests/ZoidCoachAppTests/PromptResponseEffectRouterTests.swift
)
readonly TOOLING_FILES=(
    Scripts/qa-zc025006-ambiguity-fixture.sh
    Scripts/qa-zc025006-ambiguity-ax-probe.swift
    Scripts/qa-zc025006-signed-preflight.sh
    docs/ZC-025-006-SIGNED-QA-RUNBOOK.md
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

commit_patch_id() {
    git -C "$REPOSITORY" show --pretty=email --no-ext-diff "$1" \
        | git patch-id --stable | awk 'NR == 1 { print $1 }'
}

normalized_lines() {
    print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u
}

has_exact_lines() {
    [[ "$(normalized_lines "$1")" == "$(normalized_lines "$2")" ]]
}

contains_required_lines() {
    local actual="$1"
    local required="$2"
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        grep -Fqx -- "$line" <<<"$actual" || return 1
    done <<<"$required"
}

line_count() {
    normalized_lines "$1" | wc -l | tr -d ' '
}

verify_current_base_lineage() {
    local expected="$1"
    local head scope reviewed_scope commit_count head_scope patch_ids commit
    head="$(git -C "$REPOSITORY" rev-parse HEAD)" \
        || fail "repository HEAD is unavailable"
    [[ "$head" == "$expected" ]] \
        || fail "repository HEAD $head does not match signed commit $expected"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$expected" \
        || fail "signed candidate does not descend from current canonical base $CANONICAL_BASE"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CURRENT_PRODUCT_CANDIDATE" "$expected" \
        || fail "signed candidate omits the current-base product commit"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CURRENT_TOOLING_CANDIDATE" "$expected" \
        || fail "signed candidate omits the current-base tooling commit"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CURRENT_BASELINE_FIX" "$expected" \
        || fail "signed candidate omits the reviewed complete-baseline fixture fix"

    reviewed_scope="$(printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}")"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE" "$expected")" \
        || fail "current-base candidate scope is unavailable"
    has_exact_lines "$scope" "$reviewed_scope" \
        || fail "signed candidate differs from the exact reviewed 12-file scope"
    ! grep -Fqx 'docs/scenario-registry.json' <<<"$scope" \
        || fail "signed candidate unexpectedly includes the scenario registry"
    ! grep -Fqx 'docs/zoid-coach-product-scenario-tracker.md' <<<"$scope" \
        || fail "signed candidate unexpectedly includes the scenario tracker"

    commit_count="$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")"
    (( commit_count == 5 )) \
        || fail "signed candidate contains an unexpected number of current-base commits"
    head_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected")"
    has_exact_lines "$head_scope" 'Scripts/qa-zc025006-signed-preflight.sh'$'\n''docs/ZC-025-006-SIGNED-QA-RUNBOOK.md' \
        || fail "lineage-contract maintenance commit contains unrelated files"

    patch_ids=""
    for commit in ${(f)"$(git -C "$REPOSITORY" rev-list --reverse "$CANONICAL_BASE..$expected")"}; do
        patch_ids+="$(commit_patch_id "$commit")"$'\n'
    done
    contains_required_lines "$patch_ids" "$PRODUCT_PATCH_ID"$'\n'"$TOOLING_PATCH_ID"$'\n'"$BASELINE_FIX_PATCH_ID" \
        || fail "signed candidate is missing or alters a reviewed raw patch"
    (( $(line_count "$patch_ids") == 5 )) \
        || fail "signed candidate adds an unexpected raw patch identity"
}

find_reviewed_product_commit() {
    local expected="$1"
    local commit
    if git -C "$REPOSITORY" merge-base --is-ancestor "$CURRENT_PRODUCT_CANDIDATE" "$expected"; then
        print -- "$CURRENT_PRODUCT_CANDIDATE"
        return 0
    fi
    for commit in ${(f)"$(git -C "$REPOSITORY" log --format='%H' "$expected" -- Sources/ZoidCoachInfrastructure/AmbiguousActivityPromptService.swift)"}; do
        if [[ "$(commit_patch_id "$commit")" == "$PRODUCT_PATCH_ID" ]]; then
            print -- "$commit"
            return 0
        fi
    done
    return 1
}

assert_reviewed_product_scope() {
    local commit="$1"
    local actual expected
    actual="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$commit" | LC_ALL=C sort)"
    expected="$(printf '%s\n' "${PRODUCT_FILES[@]}" | LC_ALL=C sort)"
    [[ "$actual" == "$expected" ]] \
        || fail "reviewed product commit has an unexpected file scope"
    [[ "$(commit_patch_id "$commit")" == "$PRODUCT_PATCH_ID" ]] \
        || fail "reviewed product commit does not match the stable product patch"
}

assert_runbook_contract() {
    [[ -f "$RUNBOOK" ]] || fail "signed runbook is missing"
    grep -Fq "$ORIGINAL_PRODUCT_CANDIDATE" "$RUNBOOK" \
        || fail "runbook omits the original reviewed product identity"
    grep -Fq "$CURRENT_PRODUCT_CANDIDATE" "$RUNBOOK" \
        || fail "runbook omits the current-base product identity"
    grep -Fq "$CURRENT_TOOLING_CANDIDATE" "$RUNBOOK" \
        || fail "runbook omits the current-base tooling identity"
    grep -Fq "$CURRENT_BASELINE_FIX" "$RUNBOOK" \
        || fail "runbook omits the reviewed complete-baseline fixture identity"
    grep -Fq "$CANONICAL_BASE" "$RUNBOOK" \
        || fail "runbook omits the current canonical base"
    grep -Fq "$PRODUCT_PATCH_ID" "$RUNBOOK" \
        || fail "runbook omits the raw product patch identity"
    grep -Fq "$TOOLING_PATCH_ID" "$RUNBOOK" \
        || fail "runbook omits the raw tooling patch identity"
    grep -Fq "$BASELINE_FIX_PATCH_ID" "$RUNBOOK" \
        || fail "runbook omits the complete-baseline fixture patch identity"
    local phase
    for phase in qualifying short no-task late-task stale certain; do
        grep -Fq "prepare $phase \"\$DATABASE\"" "$RUNBOOK" \
            || fail "runbook omits the $phase fixture"
    done
    for phase in choose-work choose-gaming choose-unknown history-work history-gaming history-unknown; do
        grep -Fq -- "--phase $phase" "$RUNBOOK" \
            || fail "runbook omits the $phase AX proof"
    done
    grep -Fq 'snapshot-root "$QA_ROOT" "$BASELINE_ROOT"' "$RUNBOOK" \
        || fail "runbook omits the byte baseline snapshot"
    grep -Fq 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"' "$RUNBOOK" \
        || fail "runbook omits the final byte-exact restoration assertion"
    grep -Fq 'cmp -s "$BASELINE_MANIFEST" "$FINAL_MANIFEST"' "$RUNBOOK" \
        || fail "runbook omits the independent final byte comparison"
    grep -Eq '^[[:space:]]*open "\$APP"[[:space:]]*$' "$RUNBOOK" \
        || fail "runbook omits the ordinary LaunchServices open"
    local ordinary_invocations
    ordinary_invocations="$(grep -Ec '^[[:space:]]*ordinary_relaunch[[:space:]]*$' "$RUNBOOK")"
    (( ordinary_invocations == 6 )) \
        || fail "runbook must load and persist all three actions through ordinary relaunches"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "$ORIGINAL_PRODUCT_CANDIDATE" || fail "valid candidate SHA was rejected"
    ! is_full_lowercase_sha "${ORIGINAL_PRODUCT_CANDIDATE:u}" || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "730677a" || fail "abbreviated SHA was accepted"
    command_has_exact_argument "/tmp/Zoid666QA --qa-open-main" "--qa-open-main" \
        || fail "exact QA foreground argument was rejected"
    ! command_has_exact_argument "/tmp/Zoid666QA --qa-open-main-extra" "--qa-open-main" \
        || fail "prefixed QA foreground argument was accepted"
    [[ "$(commit_patch_id "$ORIGINAL_PRODUCT_CANDIDATE")" == "$PRODUCT_PATCH_ID" ]] \
        || fail "embedded product patch identity drifted"
    [[ "$(commit_patch_id "$CURRENT_PRODUCT_CANDIDATE")" == "$PRODUCT_PATCH_ID" ]] \
        || fail "current-base product patch identity drifted"
    [[ "$(commit_patch_id "$ORIGINAL_TOOLING_CANDIDATE")" == "$TOOLING_PATCH_ID" ]] \
        || fail "embedded tooling patch identity drifted"
    [[ "$(commit_patch_id "$CURRENT_TOOLING_CANDIDATE")" == "$TOOLING_PATCH_ID" ]] \
        || fail "current-base tooling patch identity drifted"
    [[ "$(commit_patch_id "$CURRENT_BASELINE_FIX")" == "$BASELINE_FIX_PATCH_ID" ]] \
        || fail "complete-baseline fixture patch identity drifted"
    assert_reviewed_product_scope "$ORIGINAL_PRODUCT_CANDIDATE"
    assert_reviewed_product_scope "$CURRENT_PRODUCT_CANDIDATE"
    verify_current_base_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    assert_runbook_contract
    print -- "PASS: ZC-025-006 signed preflight self-test"
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
        *) fail "unsupported preflight option: $1" ;;
    esac
done

(( ! REQUIRE_QA_OPEN_MAIN || ! REQUIRE_ORDINARY_OPEN )) \
    || fail "foreground and ordinary launch requirements are mutually exclusive"
[[ "$EXPECTED_APP_PID" == "" || "$EXPECTED_APP_PID" == <-> ]] \
    || fail "expected app PID must be numeric"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
if (( ! REQUIRE_HELPER_UNREGISTERED )); then
    [[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
fi
is_full_lowercase_sha "$EXPECTED_COMMIT" \
    || fail "expected commit must be a full 40-character lowercase SHA"
git -C "$REPOSITORY" cat-file -e "$EXPECTED_COMMIT^{commit}" \
    || fail "expected commit is unavailable"
verify_current_base_lineage "$EXPECTED_COMMIT"

reviewed_product_commit="$(find_reviewed_product_commit "$EXPECTED_COMMIT")" \
    || fail "signed candidate lacks the reviewed ambiguity product patch"
readonly REVIEWED_PRODUCT_COMMIT="$reviewed_product_commit"
assert_reviewed_product_scope "$REVIEWED_PRODUCT_COMMIT"
for file in "${PRODUCT_FILES[@]}"; do
    [[ "$(git -C "$REPOSITORY" rev-parse "$EXPECTED_COMMIT:$file")" == "$(git -C "$REPOSITORY" rev-parse "$REVIEWED_PRODUCT_COMMIT:$file")" ]] \
        || fail "reviewed product file changed after the accepted patch: $file"
done
for file in "${TOOLING_FILES[@]}"; do
    git -C "$REPOSITORY" cat-file -e "$EXPECTED_COMMIT:$file" \
        || fail "signed commit omits verifier tooling: $file"
done

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
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

[[ -x "$APP_EXECUTABLE" ]] || fail "app executable is unavailable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "helper executable is unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not embed the same isolated QA root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the exact embedded QA database"
[[ "$QA_ROOT" == /private/tmp/zoid-666-zc025006-* ]] \
    || fail "signed package uses an unexpected QA root namespace"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT" ]] \
    || fail "helper does not resolve the embedded isolated QA root"

matching_app_pid() {
    local candidate
    for _ in {1..40}; do
        for candidate in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
                print -- "$candidate"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

app_pid="$(matching_app_pid)" || fail "app is not running from the expected installed bundle"
readonly APP_PID="$app_pid"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] \
    || fail "foreground app PID changed: expected $EXPECTED_APP_PID, got $APP_PID"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_QA_OPEN_MAIN )); then
    command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
        || fail "installed QA app lacks the supported foreground argument"
fi
if (( REQUIRE_ORDINARY_OPEN )); then
    ! command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
        || fail "ordinary relaunch retained the QA foreground argument"
    swift "$AX_PROBE" --pid "$APP_PID" --phase window >/dev/null \
        || fail "ordinary relaunch did not restore exactly one main window"
fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    if launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1; then
        fail "helper registered before the foreground app was bound"
    fi
    for helper_pid in ${(f)"$(pgrep -x "${AGENT_EXECUTABLE:t}" 2>/dev/null || true)"}; do
        if lsof -Fn -a -p "$helper_pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE"; then
            fail "helper executable is running before registration"
        fi
    done
    readonly HELPER_PID="UNREGISTERED"
else
    service="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" \
        || fail "installed helper service is unavailable"
    readonly SERVICE="$service"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "installed helper has no running PID"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper is not running from the expected installed bundle"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the exact isolated database open"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PRODUCT_COMMIT=$REVIEWED_PRODUCT_COMMIT"
print -- "PRODUCT_PATCH_ID=$PRODUCT_PATCH_ID"
print -- "PASS: signed ZC-025-006 identity and isolated runtime are bound"
