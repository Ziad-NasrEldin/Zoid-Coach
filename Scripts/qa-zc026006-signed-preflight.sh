#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CURRENT_CANONICAL="b97c2ce3177ccf89f60225c475062608db1920ad"
readonly SOURCE_REVIEWED_BASE="7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b"
readonly SOURCE_PRODUCT_COMMIT="98da04e5818fd949295fe37348de04198fdb2579"
readonly SOURCE_TOOLING_COMMIT="80d159b9b801d30924f0c717478d9888a0309f95"
readonly SOURCE_CANDIDATE="4ff4b3dfd2b98e2013e38a0666283055ea7161dc"
readonly SOURCE_PRODUCT_PATCH_ID="afd0a0249005f2bec0bf2441a4c67772dfecb91d"
readonly SOURCE_TOOLING_PATCH_ID="072a04b15c857295c78d9822e5faf2cf013aedea"
readonly SOURCE_COMPLETE_PATCH_ID="be790028b69e679cdde30ba2e80e20fc6e6d4182"
readonly FIXTURE="$SCRIPT_DIR/qa-zc026006-correction-impact-fixture.sh"
readonly PROBE="$SCRIPT_DIR/qa-zc026006-correction-impact-ax-probe.swift"
readonly RUNBOOK="$REPOSITORY/docs/ZC-026-006-SIGNED-QA-RUNBOOK.md"
readonly -a PRODUCT_PATHS=(
    "Sources/ZoidCoachApp/DailyReviewCorrectionImpact.swift"
    "Sources/ZoidCoachApp/Views/DailyReviewView.swift"
    "Tests/ZoidCoachAppTests/DailyReviewCorrectionImpactTests.swift"
)
readonly -a TOOLING_PATHS=(
    "Scripts/qa-zc026006-correction-impact-ax-probe.swift"
    "Scripts/qa-zc026006-correction-impact-fixture.sh"
    "Scripts/qa-zc026006-signed-preflight.sh"
    "docs/ZC-026-006-SIGNED-QA-RUNBOOK.md"
)
readonly -a LINEAGE_PATHS=(
    "Scripts/qa-zc026006-signed-preflight.sh"
    "docs/ZC-026-006-SIGNED-QA-RUNBOOK.md"
)
readonly -a IMMUTABLE_REPLAY_PATHS=(
    "Scripts/qa-zc026006-correction-impact-ax-probe.swift"
    "Scripts/qa-zc026006-correction-impact-fixture.sh"
    "Sources/ZoidCoachApp/DailyReviewCorrectionImpact.swift"
    "Sources/ZoidCoachApp/Views/DailyReviewView.swift"
    "Tests/ZoidCoachAppTests/DailyReviewCorrectionImpactTests.swift"
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
normalized_lines() { print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u; }
has_exact_lines() { [[ "$(normalized_lines "$1")" == "$(normalized_lines "$2")" ]]; }
has_argument() { [[ " $1 " == *" $2 "* ]]; }
commit_patch_id() { git -C "$REPOSITORY" show "$1" | git patch-id --stable | awk '{print $1}'; }
range_patch_id() { git -C "$REPOSITORY" diff "$1" "$2" | git patch-id --stable | awk '{print $1}'; }

verify_lineage() {
    local expected_commit="$1"
    local source_product_scope source_tooling_scope source_lineage_scope source_candidate_scope candidate_scope
    [[ "$(git -C "$REPOSITORY" rev-parse HEAD)" == "$expected_commit" ]] \
        || fail "repository HEAD does not match the signed commit"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected_commit^")" == "$CURRENT_CANONICAL" ]] \
        || fail "signed candidate is not a direct child of current canonical"
    [[ "$(git -C "$REPOSITORY" rev-parse "$SOURCE_PRODUCT_COMMIT^")" == "$SOURCE_REVIEWED_BASE" ]] \
        || fail "source product commit is not a direct child of its reviewed base"
    [[ "$(git -C "$REPOSITORY" rev-parse "$SOURCE_TOOLING_COMMIT^")" == "$SOURCE_PRODUCT_COMMIT" ]] \
        || fail "source tooling commit is not a direct child of the source product commit"
    [[ "$(git -C "$REPOSITORY" rev-parse "$SOURCE_CANDIDATE^")" == "$SOURCE_TOOLING_COMMIT" ]] \
        || fail "source candidate is not a direct child of the source tooling commit"
    source_product_scope="$(git -C "$REPOSITORY" diff --name-only "$SOURCE_REVIEWED_BASE" "$SOURCE_PRODUCT_COMMIT")"
    has_exact_lines "$source_product_scope" "$(printf '%s\n' "${PRODUCT_PATHS[@]}")" \
        || fail "source product commit scope differs from the exact three-file contract"
    source_tooling_scope="$(git -C "$REPOSITORY" diff --name-only "$SOURCE_PRODUCT_COMMIT" "$SOURCE_TOOLING_COMMIT")"
    has_exact_lines "$source_tooling_scope" "$(printf '%s\n' "${TOOLING_PATHS[@]}")" \
        || fail "source tooling scope differs from the exact four-file contract"
    source_lineage_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$SOURCE_CANDIDATE")"
    has_exact_lines "$source_lineage_scope" "$(printf '%s\n' "${LINEAGE_PATHS[@]}")" \
        || fail "source lineage commit contains files outside immutable bindings"
    source_candidate_scope="$(git -C "$REPOSITORY" diff --name-only "$SOURCE_REVIEWED_BASE" "$SOURCE_CANDIDATE")"
    has_exact_lines "$source_candidate_scope" "$(printf '%s\n' "${PRODUCT_PATHS[@]}" "${TOOLING_PATHS[@]}")" \
        || fail "source candidate differs from the exact seven-file contract"
    candidate_scope="$(git -C "$REPOSITORY" diff --name-only "$CURRENT_CANONICAL" "$expected_commit")"
    has_exact_lines "$candidate_scope" "$(printf '%s\n' "${PRODUCT_PATHS[@]}" "${TOOLING_PATHS[@]}")" \
        || fail "signed candidate differs from the exact seven-file contract"
    [[ "$(git -C "$REPOSITORY" rev-list --count "$CURRENT_CANONICAL..$expected_commit")" == "1" ]] \
        || fail "signed candidate is not a single commit over current canonical"
    [[ "$(commit_patch_id "$SOURCE_PRODUCT_COMMIT")" == "$SOURCE_PRODUCT_PATCH_ID" ]] \
        || fail "source product patch identity drifted"
    [[ "$(commit_patch_id "$SOURCE_TOOLING_COMMIT")" == "$SOURCE_TOOLING_PATCH_ID" ]] \
        || fail "source tooling patch identity drifted"
    [[ "$(range_patch_id "$SOURCE_REVIEWED_BASE" "$SOURCE_CANDIDATE")" == "$SOURCE_COMPLETE_PATCH_ID" ]] \
        || fail "source complete patch identity drifted"
    git -C "$REPOSITORY" diff --quiet "$SOURCE_CANDIDATE" "$expected_commit" -- "${IMMUTABLE_REPLAY_PATHS[@]}" \
        || fail "immutable replay files differ from the audited source candidate"
    ! grep -Eq '^(docs/scenario-registry.json|docs/zoid-coach-product-scenario-tracker.md|docs/impl/666-BACKLOG.md|\.lavish/)' <<<"$source_product_scope
$source_tooling_scope
$source_lineage_scope
$candidate_scope" || fail "candidate includes a protected orchestration artifact"
}

assert_runbook_contract() {
    local snapshot prepare launch bind register combined relaunch restore unregister
    local identity
    for identity in "$CURRENT_CANONICAL" "$SOURCE_REVIEWED_BASE" "$SOURCE_PRODUCT_COMMIT" "$SOURCE_TOOLING_COMMIT" \
        "$SOURCE_CANDIDATE" "$SOURCE_PRODUCT_PATCH_ID" "$SOURCE_TOOLING_PATCH_ID" "$SOURCE_COMPLETE_PATCH_ID"; do
        grep -Fq "$identity" "$RUNBOOK" || fail "runbook omits immutable lineage identity $identity"
    done
    snapshot="$(grep -nF '"$FIXTURE" snapshot "$DATABASE" "$BYTE_BACKUP"' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    prepare="$(grep -nF '"$FIXTURE" prepare "$DATABASE"' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    launch="$(grep -nF 'open "$APP" --args --qa-open-main' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    bind="$(grep -nF -- '--require-qa-open-main --require-helper-unregistered' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    register="$(grep -nF '"$APP_EXECUTABLE" --qa-register-agent' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    combined="$(grep -nF 'probe apply-combined' "$RUNBOOK" | head -n1 | cut -d: -f1)"
    relaunch="$(grep -nF 'open "$APP"' "$RUNBOOK" | tail -n1 | cut -d: -f1)"
    unregister="$(grep -nF '"$APP_EXECUTABLE" --qa-unregister-agent' "$RUNBOOK" | tail -n1 | cut -d: -f1)"
    restore="$(grep -nF '"$FIXTURE" restore "$DATABASE" "$BYTE_BACKUP"' "$RUNBOOK" | tail -n1 | cut -d: -f1)"
    [[ "$snapshot" == <-> && "$prepare" == <-> && "$launch" == <-> && "$bind" == <-> \
        && "$register" == <-> && "$combined" == <-> && "$relaunch" == <-> \
        && "$unregister" == <-> && "$restore" == <-> \
        && snapshot -lt prepare && prepare -lt launch && launch -lt bind && bind -lt register \
        && register -lt combined && combined -lt relaunch && relaunch -lt unregister && unregister -lt restore ]] \
        || fail "runbook ordering does not preserve snapshot, foreground binding, ordinary relaunch, and byte restore"
    [[ "$(grep -c '^open "\$APP"$' "$RUNBOOK")" -ge 2 ]] \
        || fail "runbook must perform at least two ordinary relaunches"
    for phase in before apply-combined persisted-combined apply-remove apply-attach apply-unchanged-alignment persisted-final; do
        grep -Fq -- "probe $phase" "$RUNBOOK" || fail "runbook omits AX phase $phase"
    done
    for assertion in assert-before assert-combined assert-removed assert-attached assert-final; do
        grep -Fq -- "$assertion" "$RUNBOOK" || fail "runbook omits fixture assertion $assertion"
    done
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_sha "$CURRENT_CANONICAL" || fail "current canonical SHA is invalid"
    is_sha "$SOURCE_REVIEWED_BASE" || fail "source reviewed base SHA is invalid"
    is_sha "$SOURCE_PRODUCT_COMMIT" || fail "source product SHA is invalid"
    is_sha "$SOURCE_TOOLING_COMMIT" || fail "source tooling SHA is invalid"
    is_sha "$SOURCE_CANDIDATE" || fail "source candidate SHA is invalid"
    has_exact_lines "$(printf '%s\n' "${PRODUCT_PATHS[@]}")" "$(printf '%s\n' "${PRODUCT_PATHS[@]}")" \
        || fail "exact-scope helper rejected equal scopes"
    ! has_exact_lines "$(printf '%s\n' "${PRODUCT_PATHS[@]}")" "$(printf '%s\n' "${PRODUCT_PATHS[@]}")"$'\n''Sources/Unrelated.swift' \
        || fail "exact-scope helper accepted an unrelated file"
    has_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "foreground argument helper rejected the required argument"
    ! has_argument "/tmp/Zoid666" "--qa-open-main" || fail "ordinary launch was mistaken for a QA foreground launch"
    assert_runbook_contract
    "$FIXTURE" self-test >/dev/null
    "$PROBE" --self-test >/dev/null
    swiftc -typecheck "$PROBE" -framework ApplicationServices -framework CoreGraphics
    if [[ -z "$(git -C "$REPOSITORY" status --short)" ]]; then
        verify_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    fi
    print -- "PASS: ZC-026-006 signed preflight self-test"
    exit 0
fi

readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_ORDINARY_OPEN=0
REQUIRE_HELPER_UNREGISTERED=0
EXPECTED_APP_PID=""
while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main) REQUIRE_QA_OPEN_MAIN=1; shift ;;
        --require-ordinary-open) REQUIRE_ORDINARY_OPEN=1; shift ;;
        --require-helper-unregistered) REQUIRE_HELPER_UNREGISTERED=1; shift ;;
        --expected-app-pid) (( $# >= 2 )) || fail "--expected-app-pid requires a PID"; EXPECTED_APP_PID="$2"; shift 2 ;;
        *) fail "unsupported option: $1" ;;
    esac
done

[[ -d "$APP" ]] || fail "signed app does not exist"
[[ -f "$DATABASE" || "$REQUIRE_HELPER_UNREGISTERED" == 1 ]] || fail "isolated database is unavailable"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
(( ! REQUIRE_QA_OPEN_MAIN || ! REQUIRE_ORDINARY_OPEN )) || fail "launch requirements are mutually exclusive"
verify_lineage "$EXPECTED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly CANONICAL_APP="${APP:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly -a AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"
[[ "${DATABASE:A}" == "$EXPECTED_DATABASE" ]] || fail "database does not match the signed bundle's isolated QA root"

matching_pid() {
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

readonly APP_PID="$(matching_pid)" || fail "installed app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "app PID changed unexpectedly"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
if (( REQUIRE_QA_OPEN_MAIN )); then has_argument "$APP_COMMAND" "--qa-open-main" || fail "foreground QA argument is absent"; fi
if (( REQUIRE_ORDINARY_OPEN )); then ! has_argument "$APP_COMMAND" "--qa-open-main" || fail "ordinary relaunch retained QA foreground arguments"; fi

if (( REQUIRE_HELPER_UNREGISTERED )); then
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || fail "helper registered before foreground binding"
    readonly HELPER_PID="UNREGISTERED"
else
    readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper service is unavailable"
    readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
    [[ "$HELPER_PID" == <-> ]] || fail "helper PID is unavailable"
    lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
        || fail "helper executable does not belong to the signed bundle"
    lsof -a -p "$HELPER_PID" "$EXPECTED_DATABASE" >/dev/null 2>&1 \
        || fail "helper does not hold the exact isolated database open"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$EXPECTED_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-026-006 signed runtime identity is bound"
