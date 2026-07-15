#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly REVIEWED_BASE="76149705b3a301fafa832102a2e599358a16ff25"
readonly REVIEWED_LINEAGE_TIP="f950272b94c2fa4f3290aa6d5cb2437e2a9996a1"
readonly PRODUCT_PATCH_ID="a7efaf62d800f972ca8da25a78ccdd1f890fe7ba"
readonly TOOLING_PATCH_ID="0698e0eb3b14cec5fa92c12f5682e759513c891c"
readonly -a REVIEWED_PATCH_IDS=("$PRODUCT_PATCH_ID" "$TOOLING_PATCH_ID")
readonly -a REVIEWED_PATHS=(
    "Scripts/fixtures/zc-035-011-gaming-observation-ready-state.json"
    "Scripts/qa-zc035011-gaming-observation-ax-probe.swift"
    "Scripts/qa-zc035011-gaming-observation-fixture.sh"
    "Scripts/qa-zc035011-signed-preflight.sh"
    "Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift"
    "Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift"
    "docs/ZC-035-011-SIGNED-QA-RUNBOOK.md"
)
readonly REVIEWED_BLOBS="f02e4e76e679d106ace22e8672a8e08a85b5a177 Scripts/fixtures/zc-035-011-gaming-observation-ready-state.json
95f34b5d9b55a63fbba7b5d7be735872726f3b3e Scripts/qa-zc035011-gaming-observation-ax-probe.swift
10cc400df5cb4f9d08a2b35ca5adb4d99ac13578 Scripts/qa-zc035011-gaming-observation-fixture.sh
1f7481dddf53fdb8d70f4785549493eb835092a3 Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift
7aa0f3a40a688087ba90ee77b177522a3b1bb573 Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift
e907faa47566ba15464fbbf0f5596c9e1b7a4605 docs/ZC-035-011-SIGNED-QA-RUNBOOK.md"
readonly PROBE="$SCRIPT_DIR/qa-zc035011-gaming-observation-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc035011-gaming-observation-fixture.sh"
readonly READY_MANIFEST="$SCRIPT_DIR/fixtures/zc-035-011-gaming-observation-ready-state.json"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_ORDINARY_OPEN=0
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

has_argument() {
    [[ " $1 " == *" $2 "* ]]
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

has_reviewed_patch_shape() {
    contains_required_lines "$1" "$2" \
        && (( $(line_count "$1") == $(line_count "$2") + 1 ))
}

reviewed_patch_ids() {
    local commit
    for commit in ${(f)"$(git -C "$REPOSITORY" rev-list --reverse --topo-order "$REVIEWED_BASE..$REVIEWED_LINEAGE_TIP")"}; do
        git -C "$REPOSITORY" show --pretty=email --no-ext-diff "$commit" \
            | git patch-id --stable \
            | awk '{print $1}'
    done
}

verify_reviewed_lineage() {
    local expected_commit="${1:-$EXPECTED_COMMIT}"
    local head reviewed_scope scope commit_count patch_ids expected_patch_ids
    local parent_line expected_parent_line entry expected_blob file_path actual_blob
    head="$(git -C "$REPOSITORY" rev-parse HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$expected_commit" ]] \
        || fail "repository HEAD $head does not match signed commit $expected_commit"
    git -C "$REPOSITORY" merge-base --is-ancestor "$REVIEWED_BASE" "$expected_commit" \
        || fail "signed commit does not descend from current canonical base $REVIEWED_BASE"
    git -C "$REPOSITORY" merge-base --is-ancestor "$REVIEWED_LINEAGE_TIP" "$expected_commit" \
        || fail "signed commit does not contain the reviewed product/tooling lineage"
    expected_parent_line="$REVIEWED_BASE $REVIEWED_LINEAGE_TIP"
    parent_line="$(git -C "$REPOSITORY" show -s --format='%P' "$expected_commit")"
    [[ "$parent_line" == "$expected_parent_line" ]] \
        || fail "signed candidate does not have the exact canonical and reviewed lineage parents"

    reviewed_scope="$(printf '%s\n' "${REVIEWED_PATHS[@]}")"
    scope="$(git -C "$REPOSITORY" diff --name-only "$REVIEWED_BASE" "$expected_commit")" \
        || fail "candidate file scope is unavailable"
    has_exact_lines "$scope" "$reviewed_scope" \
        || fail "signed candidate differs from the reviewed seven-file scope"
    ! grep -Fqx 'docs/scenario-registry.json' <<<"$scope" \
        || fail "signed candidate unexpectedly changes the scenario registry"
    ! grep -Fqx 'docs/zoid-coach-product-scenario-tracker.md' <<<"$scope" \
        || fail "signed candidate unexpectedly changes the scenario tracker"

    commit_count="$(git -C "$REPOSITORY" rev-list --count "$REVIEWED_BASE..$expected_commit")"
    (( commit_count == ${#REVIEWED_PATCH_IDS} + 1 )) \
        || fail "signed candidate contains an unexpected number of commits"

    patch_ids="$(reviewed_patch_ids)"
    expected_patch_ids="$(printf '%s\n' "${REVIEWED_PATCH_IDS[@]}")"
    [[ "$patch_ids" == "$expected_patch_ids" ]] \
        || fail "signed candidate is missing, alters, or adds a reviewed product/tooling patch"

    while IFS= read -r entry; do
        expected_blob="${entry%% *}"
        file_path="${entry#* }"
        actual_blob="$(git -C "$REPOSITORY" rev-parse "$expected_commit:$file_path" 2>/dev/null)" \
            || fail "signed candidate is missing reviewed file $file_path"
        [[ "$actual_blob" == "$expected_blob" ]] \
            || fail "signed candidate alters reviewed file $file_path"
    done <<<"$REVIEWED_BLOBS"
}

assert_runbook_contract() {
    local runbook="$REPOSITORY/docs/ZC-035-011-SIGNED-QA-RUNBOOK.md"
    local ready launch bind register qa_open ordinary_definition ordinary_calls cleanup unregister uninstall
    ready="$(grep -nF '"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace' "$runbook" | head -n1 | cut -d: -f1)"
    launch="$(awk -v start="$ready" 'NR > start && /^open "\$APP" --args --qa-open-main$/ {print NR; exit}' "$runbook")"
    bind="$(awk -v start="$ready" 'NR > start && /--require-qa-open-main --require-helper-unregistered/ {print NR; exit}' "$runbook")"
    register="$(awk -v start="$ready" 'NR > start && /^"\$APP_EXECUTABLE" --qa-register-agent$/ {print NR; exit}' "$runbook")"
    [[ "$ready" == <-> && "$launch" == <-> && "$bind" == <-> && "$register" == <-> \
        && ready -lt launch && launch -lt bind && bind -lt register ]] \
        || fail "runbook must prepare, foreground-launch, bind, then register the helper"

    qa_open="$(grep -c '^open "\$APP" --args --qa-open-main$' "$runbook")"
    ordinary_definition="$(grep -c '^ordinary_open() {$' "$runbook")"
    ordinary_calls="$(grep -c '^ordinary_open$' "$runbook")"
    [[ "$qa_open" == 1 && "$ordinary_definition" == 1 && "$ordinary_calls" == 4 ]] \
        || fail "runbook must use one foreground launch and four bound ordinary relaunches"
    grep -Fq 'for attempt in {1..130}; do' "$runbook" \
        || fail "later gaming wait is not bounded"
    grep -Fq 'sleep 5' "$runbook" \
        || fail "later gaming wait has no real-time cadence"
    ! grep -Fq 'ZOID_666_QA_ZC035011_NOW_EPOCH=' "$runbook" \
        || fail "signed runbook must not inject a synthetic clock"

    cleanup="$(grep -nF '"$FIXTURE" cleanup "$DATABASE"' "$runbook" | tail -n1 | cut -d: -f1)"
    unregister="$(grep -nF '"$APP_EXECUTABLE" --qa-unregister-agent' "$runbook" | tail -n1 | cut -d: -f1)"
    uninstall="$(grep -nF '"$UNINSTALLER"' "$runbook" | tail -n1 | cut -d: -f1)"
    [[ "$unregister" == <-> && "$cleanup" == <-> && "$uninstall" == <-> \
        && unregister -lt cleanup && cleanup -lt uninstall ]] \
        || fail "runbook cleanup must stop the helper, restore fixture state, then uninstall"
}

assert_ready_manifest() {
    jq -e '
        .schemaVersion == 1
        and .onboarding.coachingMode == "rulesOnly"
        and .osFixture.reminders == [{
            id:"qa-zc035011-priority",
            title:"ZC-035-011 priority objective",
            listIdentifier:"qa-zc035011-work",
            priority:1,
            isCompleted:false
        }]
        and .screenwatch.state == "healthy"
        and (.screenwatch.days | length) == 1
        and (.screenwatch.days[0].records | length) == 1
    ' "$READY_MANIFEST" >/dev/null \
        || fail "ready-state manifest does not preserve the reviewed task and healthy source boundary"
}

if [[ "$APP" == "--self-test" ]]; then
    readonly REVIEWED_SCOPE="$(printf '%s\n' "${REVIEWED_PATHS[@]}")"
    readonly REVIEWED_PATCHES="$(printf '%s\n' "${REVIEWED_PATCH_IDS[@]}")"
    readonly CANDIDATE_PATCHES="$REVIEWED_PATCHES"$'\n''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    is_sha "08bf903f67f86ed1fc2e9392ebf5a1de47c8418b" || fail "valid SHA rejected"
    ! is_sha "08BF903F67F86ED1FC2E9392EBF5A1DE47C8418B" || fail "uppercase SHA accepted"
    has_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "foreground argument rejected"
    ! has_argument "/tmp/Zoid666" "--qa-open-main" || fail "ordinary launch mistaken for QA foreground launch"
    has_exact_lines "$REVIEWED_SCOPE" "$REVIEWED_SCOPE" || fail "reviewed scope rejected"
    ! has_exact_lines "$REVIEWED_SCOPE"$'\n''docs/scenario-registry.json' "$REVIEWED_SCOPE" \
        || fail "registry scope was accepted"
    has_reviewed_patch_shape "$CANDIDATE_PATCHES" "$REVIEWED_PATCHES" \
        || fail "reviewed patch shape rejected"
    ! has_reviewed_patch_shape "${CANDIDATE_PATCHES/$PRODUCT_PATCH_ID/0000000000000000000000000000000000000000}" "$REVIEWED_PATCHES" \
        || fail "altered raw product patch was accepted"
    [[ "$(reviewed_patch_ids)" == "$REVIEWED_PATCHES" ]] \
        || fail "reviewed product/tooling ancestry changed"
    verify_reviewed_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    assert_runbook_contract
    assert_ready_manifest
    "$FIXTURE" self-test >/dev/null
    swift "$PROBE" --self-test >/dev/null
    print -- "PASS: ZC-035-011 signed lineage, runbook, fixture, AX, privacy, and cleanup preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main) REQUIRE_QA_OPEN_MAIN=1; shift ;;
        --require-ordinary-open) REQUIRE_ORDINARY_OPEN=1; shift ;;
        --require-helper-unregistered) REQUIRE_HELPER_UNREGISTERED=1; shift ;;
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
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ -z "$EXPECTED_APP_PID" || "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
if (( ! REQUIRE_HELPER_UNREGISTERED )); then
    [[ -f "$DATABASE" ]] || fail "isolated database is unavailable: $DATABASE"
fi

verify_reviewed_lineage
assert_runbook_contract
assert_ready_manifest
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "signed app or helper executable is unavailable"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not embed the same isolated QA root"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the exact embedded app/helper QA database"

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

readonly APP_PID="$(matching_app_pid)" || fail "installed app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "foreground app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_QA_OPEN_MAIN )); then
    has_argument "$APP_COMMAND" "--qa-open-main" || fail "foreground app lacks the supported QA main-window argument"
fi
if (( REQUIRE_ORDINARY_OPEN )); then
    ! has_argument "$APP_COMMAND" "--qa-open-main" || fail "ordinary relaunch retained the QA foreground argument"
    swift "$PROBE" --pid "$APP_PID" --phase window >/dev/null \
        || fail "ordinary relaunch did not restore one usable Today window"
fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 \
        || fail "helper registered before foreground binding"
    readonly HELPER_PID="UNREGISTERED"
else
    readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" \
        || fail "installed helper service is unavailable"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "installed helper has no PID"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper is not running from the signed installed bundle"
    lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the exact isolated database open"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-035-011 signed candidate identity and runtime are bound"
