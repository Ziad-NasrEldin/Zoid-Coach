#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="91197544123ccd53a647933545728af7ff81acd5"
readonly PRODUCT_CANDIDATE="a477c93a34dbf568e7d8053f1bc0ce55fe745442"
readonly TOOLING_CANDIDATE="b2103974b9948660fcb3c5bb10c3e86e8e8c73c0"
readonly PRODUCT_PATCH_ID="bfd7e82fdd3554ce9c7223e60a824d9e29d24566"
readonly TOOLING_PATCH_ID="c1bb138a61e771e6ec674063e3da0b59c7347090"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc017007-open-ended-elapsed-ax-probe.swift"
readonly RUNBOOK="$REPOSITORY/docs/ZC-017-007-SIGNED-QA-RUNBOOK.md"
readonly PRODUCT_FILES=(
    Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
    Tests/ZoidCoachAppTests/TodayDashboardCommandOverviewTests.swift
)
readonly TOOLING_FILES=(
    Scripts/qa-zc017007-open-ended-elapsed-fixture.sh
    Scripts/qa-zc017007-open-ended-elapsed-ax-probe.swift
    Scripts/qa-zc017007-signed-preflight.sh
    Scripts/qa-zc017007-runbook-self-test.sh
    docs/ZC-017-007-SIGNED-QA-RUNBOOK.md
)

APP="${1:-}"
DATABASE="${2:-}"
EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_ORDINARY_OPEN=0
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    [[ " $1 " == *" $2 "* ]]
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

contains_line() {
    grep -Fqx -- "$2" <<<"$1"
}

verify_lineage() {
    local expected="$1"
    local head scope reviewed_scope commit_count patch_ids commit
    head="$(git -C "$REPOSITORY" rev-parse HEAD)"
    [[ "$head" == "$expected" ]] || fail "repository HEAD $head does not match signed commit $expected"
    git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$expected" \
        || fail "signed candidate does not descend from canonical base"
    git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$expected" \
        || fail "signed candidate omits the reviewed product commit"
    git -C "$REPOSITORY" merge-base --is-ancestor "$TOOLING_CANDIDATE" "$expected" \
        || fail "signed candidate omits the reviewed tooling commit"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE" "$expected")"
    reviewed_scope="$(printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}")"
    has_exact_lines "$scope" "$reviewed_scope" \
        || fail "signed candidate differs from the exact reviewed seven-file scope"
    ! contains_line "$scope" "docs/scenario-registry.json" \
        || fail "signed candidate unexpectedly includes the scenario registry"
    ! contains_line "$scope" "docs/zoid-coach-product-scenario-tracker.md" \
        || fail "signed candidate unexpectedly includes the scenario tracker"
    commit_count="$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")"
    (( commit_count == 3 )) || fail "signed candidate contains an unexpected commit count"
    patch_ids=""
    for commit in ${(f)"$(git -C "$REPOSITORY" rev-list --reverse "$CANONICAL_BASE..$expected")"}; do
        patch_ids+="$(commit_patch_id "$commit")"$'\n'
    done
    contains_line "$patch_ids" "$PRODUCT_PATCH_ID" || fail "reviewed product patch identity is missing"
    contains_line "$patch_ids" "$TOOLING_PATCH_ID" || fail "reviewed tooling patch identity is missing"
    (( $(normalized_lines "$patch_ids" | wc -l | tr -d ' ') == 3 )) \
        || fail "signed candidate contains an unexpected raw patch identity"
}

assert_product_scope() {
    local actual expected
    actual="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$PRODUCT_CANDIDATE")"
    expected="$(printf '%s\n' "${PRODUCT_FILES[@]}")"
    has_exact_lines "$actual" "$expected" || fail "reviewed product commit has unexpected scope"
    [[ "$(commit_patch_id "$PRODUCT_CANDIDATE")" == "$PRODUCT_PATCH_ID" ]] \
        || fail "reviewed product patch identity drifted"
}

assert_runbook_contract() {
    [[ -f "$RUNBOOK" ]] || fail "signed runbook is missing"
    local required
    for required in "$CANONICAL_BASE" "$PRODUCT_CANDIDATE" "$TOOLING_CANDIDATE" "$PRODUCT_PATCH_ID" "$TOOLING_PATCH_ID"; do
        grep -Fq "$required" "$RUNBOOK" || fail "runbook omits lineage identity $required"
    done
    local mode
    for mode in live rollback fallback bounded paused; do
        grep -Fq "prepare $mode \"\$DATABASE\"" "$RUNBOOK" || fail "runbook omits $mode fixture"
    done
    grep -Fq -- '--phase live-advance' "$RUNBOOK" || fail "runbook omits no-navigation live advance proof"
    grep -Fq 'bounded physical scroll before the initial reading' "$RUNBOOK" || fail "runbook omits bounded initial visibility scroll"
    grep -Fq -- '--phase exact-live --expected-minutes 9' "$RUNBOOK" || fail "runbook omits rollback proof"
    grep -Fq -- '--phase fallback --expected-minutes 9' "$RUNBOOK" || fail "runbook omits fallback proof"
    grep -Fq -- '--phase absent' "$RUNBOOK" || fail "runbook omits bounded and paused exclusions"
    grep -Fq 'snapshot-root "$QA_ROOT" "$BASELINE_ROOT"' "$RUNBOOK" || fail "runbook omits root snapshot"
    grep -Fq 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"' "$RUNBOOK" || fail "runbook omits byte restoration"
    grep -Fq 'cmp -s "$BASELINE_MANIFEST" "$FINAL_MANIFEST"' "$RUNBOOK" || fail "runbook omits independent manifest comparison"
    grep -Eq '^[[:space:]]*open "\$APP"[[:space:]]*$' "$RUNBOOK" || fail "runbook omits ordinary LaunchServices open"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$CANONICAL_BASE" || fail "canonical base SHA is invalid"
    is_full_sha "$PRODUCT_CANDIDATE" || fail "product SHA is invalid"
    is_full_sha "$TOOLING_CANDIDATE" || fail "tooling SHA is invalid"
    [[ "$(commit_patch_id "$TOOLING_CANDIDATE")" == "$TOOLING_PATCH_ID" ]] \
        || fail "reviewed tooling patch identity drifted"
    assert_product_scope
    verify_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    assert_runbook_contract
    print -- "PASS: ZC-017-007 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-ordinary-open) REQUIRE_ORDINARY_OPEN=1; shift ;;
        --require-helper-unregistered) REQUIRE_HELPER_UNREGISTERED=1; shift ;;
        --expected-app-pid) EXPECTED_APP_PID="${2:-}"; shift 2 ;;
        *) fail "unsupported preflight option: $1" ;;
    esac
done

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
if (( ! REQUIRE_HELPER_UNREGISTERED )); then
    [[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
fi
is_full_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
verify_lineage "$EXPECTED_COMMIT"
assert_product_scope
for file in "${PRODUCT_FILES[@]}"; do
    [[ "$(git -C "$REPOSITORY" rev-parse "$EXPECTED_COMMIT:$file")" == "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE:$file")" ]] \
        || fail "reviewed product file changed after acceptance: $file"
done
for file in "${TOOLING_FILES[@]}"; do
    git -C "$REPOSITORY" cat-file -e "$EXPECTED_COMMIT:$file" \
        || fail "signed candidate omits tooling file: $file"
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

[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "signed executables are unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not embed the same isolated root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database is not the embedded QA database"
[[ "$QA_ROOT" == /private/tmp/zoid-666-zc017007-* ]] || fail "unexpected QA root namespace"

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
    || fail "foreground app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_ORDINARY_OPEN )); then
    ! command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
        || fail "ordinary relaunch retained the QA foreground argument"
    swift "$AX_PROBE" --pid "$APP_PID" --phase window --reject PRIVATE-ZC017007 >/dev/null \
        || fail "ordinary relaunch did not restore one private-safe main window"
fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 \
        || fail "helper registered before foreground binding"
    readonly HELPER_PID="UNREGISTERED"
else
    service="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" \
        || fail "installed helper service is unavailable"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$service")"
    [[ "$HELPER_PID" == <-> ]] || fail "installed helper has no running PID"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper is not running from the installed bundle"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the exact isolated database"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
