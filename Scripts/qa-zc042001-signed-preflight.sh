#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly REVIEWED_BASE="8b1782c6ee2c213a408360554f19bf231b0f3e19"
readonly -a REVIEWED_PATHS=(
    "Scripts/qa-zc042001-evidence-layers-ax-probe.swift"
    "Scripts/qa-zc042001-evidence-layers-fixture.sh"
    "Scripts/qa-zc042001-signed-bootstrap.sh"
    "Scripts/qa-zc042001-signed-preflight.sh"
    "Sources/ZoidCoachApp/ApplicationLaunchPresentation.swift"
    "Sources/ZoidCoachApp/DailyReviewEvidenceLayersState.swift"
    "Sources/ZoidCoachApp/Views/DailyReviewView.swift"
    "Sources/ZoidCoachInfrastructure/DailyReviewStore.swift"
    "Tests/ZoidCoachAppTests/ApplicationLaunchPresentationTests.swift"
    "Tests/ZoidCoachAppTests/DailyReviewEvidenceLayersStateTests.swift"
    "Tests/ZoidCoachAppTests/DailyReviewTests.swift"
    "docs/ZC-042-001-SIGNED-QA-RUNBOOK.md"
)
readonly -a REVIEWED_PATCH_IDS=(
    "50dde6b14d5387076062e13679c0060d711d3657"
    "1990692a8d2e10ae1d5a0beaf1fe26ed2c69a2a7"
    "87abcc980cb75d4704bb8278812e702feed89581"
    "11d740cd3b9c2bbea2798f053a7c737ba5c0f748"
    "408f4407de2c0509995b31aa29e02dcfa2899f12"
    "64011ee6adc75440d3148d8a8bca55902f752784"
    "3a3214632dd22ca67c0cf5364c8dd6f899e90be1"
    "2de64e3308c41f6871d0fa52ff36799d2238dc2f"
)
readonly REVIEWED_BLOBS="ca447eab0731c1072a157bc6e91000572f169287 Scripts/qa-zc042001-evidence-layers-ax-probe.swift
e791f2fe6694a3d93d6e53667741a540d90e78de Scripts/qa-zc042001-evidence-layers-fixture.sh
a66087d86f51f5b81c530e221eaccb5745023f6c Scripts/qa-zc042001-signed-bootstrap.sh
b4f19917cdf16fb890601319b26bb82482227867 Sources/ZoidCoachApp/ApplicationLaunchPresentation.swift
777fb72fd0981c561b41dbc0f2543d8ab61667fc Sources/ZoidCoachApp/DailyReviewEvidenceLayersState.swift
2272443cdbf4accb44357eb884dff51cce55789c Sources/ZoidCoachApp/Views/DailyReviewView.swift
10ccad0e94fa4ec4a9ceaea21876b89695907faf Sources/ZoidCoachInfrastructure/DailyReviewStore.swift
bf07cc4d481d58ee27ab6ca2239f047f7b57c5c0 Tests/ZoidCoachAppTests/ApplicationLaunchPresentationTests.swift
172937962475f2c484709820559e9ddd1be88d66 Tests/ZoidCoachAppTests/DailyReviewEvidenceLayersStateTests.swift
047915d715eb4dbaa88909ee2d4dfe56804e53de Tests/ZoidCoachAppTests/DailyReviewTests.swift
0304c83690837b129a7611b517006f9128f42f52 docs/ZC-042-001-SIGNED-QA-RUNBOOK.md"
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
normalized_lines() { print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u; }
has_exact_lines() { [[ "$(normalized_lines "$1")" == "$(normalized_lines "$2")" ]]; }
contains_required_lines() {
    local actual="$1"
    local required="$2"
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        grep -Fqx -- "$line" <<<"$actual" || return 1
    done <<<"$required"
}
line_count() { normalized_lines "$1" | wc -l | tr -d ' '; }
has_reviewed_patch_shape() {
    contains_required_lines "$1" "$2" \
        && (( $(line_count "$1") == $(line_count "$2") + 1 ))
}

verify_reviewed_lineage() {
    local expected_commit="${1:-$EXPECTED_COMMIT}"
    local head scope reviewed_scope patch_ids commit entry expected_blob file_path actual_blob
    local commit_count head_scope
    head="$(git -C "$REPOSITORY" rev-parse HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$expected_commit" ]] || fail "repository HEAD $head does not match signed commit $expected_commit"
    git -C "$REPOSITORY" merge-base --is-ancestor "$REVIEWED_BASE" "$expected_commit" \
        || fail "signed commit does not descend from reviewed base $REVIEWED_BASE"

    reviewed_scope="$(printf '%s\n' "${REVIEWED_PATHS[@]}")"
    scope="$(git -C "$REPOSITORY" diff --name-only "$REVIEWED_BASE" "$expected_commit")" \
        || fail "reviewed file scope is unavailable"
    has_exact_lines "$scope" "$reviewed_scope" \
        || fail "signed commit file scope differs from the reviewed 12-file scope"
    ! grep -Fqx 'docs/scenario-registry.json' <<<"$scope" \
        || fail "signed commit unexpectedly includes the scenario registry"
    ! grep -Fqx 'docs/zoid-coach-product-scenario-tracker.md' <<<"$scope" \
        || fail "signed commit unexpectedly includes the scenario tracker"

    commit_count="$(git -C "$REPOSITORY" rev-list --count "$REVIEWED_BASE..$expected_commit")"
    (( commit_count == ${#REVIEWED_PATCH_IDS} + 1 )) \
        || fail "signed commit contains an unexpected number of candidate commits"
    head_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected_commit")"
    [[ "$head_scope" == 'Scripts/qa-zc042001-signed-preflight.sh' ]] \
        || fail "lineage-contract maintenance commit contains unrelated files"

    patch_ids=""
    for commit in ${(f)"$(git -C "$REPOSITORY" rev-list --reverse "$REVIEWED_BASE..$expected_commit")"}; do
        patch_ids+="$(git -C "$REPOSITORY" show --pretty=email --no-ext-diff "$commit" \
            | git patch-id --stable | awk '{print $1}')"$'\n'
    done
    has_reviewed_patch_shape "$patch_ids" "$(printf '%s\n' "${REVIEWED_PATCH_IDS[@]}")" \
        || fail "signed commit is missing, alters, or adds an unexpected reviewed patch"

    while IFS= read -r entry; do
        expected_blob="${entry%% *}"
        file_path="${entry#* }"
        actual_blob="$(git -C "$REPOSITORY" rev-parse "$expected_commit:$file_path" 2>/dev/null)" \
            || fail "signed commit is missing reviewed file $file_path"
        [[ "$actual_blob" == "$expected_blob" ]] \
            || fail "signed commit alters reviewed file $file_path"
    done <<<"$REVIEWED_BLOBS"
}

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

assert_existing_main_window_is_reused() {
    local source="$REPOSITORY/Sources/ZoidCoachApp/ApplicationLaunchPresentation.swift"
    local tests="$REPOSITORY/Tests/ZoidCoachAppTests/ApplicationLaunchPresentationTests.swift"
    local open_line reuse_line request_line
    open_line="$(grep -n '^    func open() {$' "$source" | head -n1 | cut -d: -f1)"
    reuse_line="$(awk -v start="$open_line" 'NR > start && /if let mainWindow = MainApplicationWindowSelector.select/ {print NR; exit}' "$source")"
    request_line="$(awk -v start="$open_line" 'NR > start && /requestMainWindow\(\)/ {print NR; exit}' "$source")"
    [[ "$open_line" == <-> && "$reuse_line" == <-> && "$request_line" == <-> \
        && open_line -lt reuse_line && reuse_line -lt request_line ]] \
        || fail "QA launch must reuse an existing main WindowGroup before requesting another scene"
    grep -Fq '@Test func qaMainWindowLaunchReusesExistingMainWithoutRequestingDuplicate()' "$tests" \
        || fail "existing-main duplicate regression test is unavailable"
    grep -Fq '#expect(events == ["activate", "foreground-42"])' "$tests" \
        || fail "existing-main regression test permits a duplicate scene request"
}

if [[ "$APP" == "--self-test" ]]; then
    reviewed_scope="$(printf '%s\n' "${REVIEWED_PATHS[@]}")"
    reviewed_patches="$(printf '%s\n' "${REVIEWED_PATCH_IDS[@]}")"
    candidate_patches="$reviewed_patches"$'\n''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    is_sha "8cc9f2187e74787c183e444140b8696b8e37e52f" || fail "valid SHA rejected"
    ! is_sha "8CC9F2187E74787C183E444140B8696B8E37E52F" || fail "uppercase SHA accepted"
    has_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "foreground argument rejected"
    ! has_argument "/tmp/Zoid666" "--qa-open-main" || fail "ordinary launch mistaken for foreground launch"
    has_exact_lines "$reviewed_scope" "$reviewed_scope" || fail "reviewed scope rejected"
    ! has_exact_lines "$(sed '$d' <<<"$reviewed_scope")" "$reviewed_scope" \
        || fail "missing reviewed file accepted"
    ! has_exact_lines "$reviewed_scope"$'\n''Sources/UnrelatedCandidate.swift' "$reviewed_scope" \
        || fail "unrelated candidate file accepted"
    ! has_exact_lines "$reviewed_scope"$'\n''docs/scenario-registry.json' "$reviewed_scope" \
        || fail "scenario registry inclusion accepted"
    has_reviewed_patch_shape "$candidate_patches" "$reviewed_patches" || fail "reviewed patch shape rejected"
    ! has_reviewed_patch_shape "$(sed '$d' <<<"$candidate_patches")" "$reviewed_patches" \
        || fail "missing reviewed patch accepted"
    ! has_reviewed_patch_shape "${candidate_patches/50dde6b14d5387076062e13679c0060d711d3657/0000000000000000000000000000000000000000}" "$reviewed_patches" \
        || fail "altered reviewed patch accepted"
    ! has_reviewed_patch_shape "$candidate_patches"$'\n''bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "$reviewed_patches" \
        || fail "unrelated candidate patch accepted"
    ! contains_required_lines "${REVIEWED_BLOBS/ca447eab0731c1072a157bc6e91000572f169287/0000000000000000000000000000000000000000}" "$REVIEWED_BLOBS" \
        || fail "altered reviewed file blob accepted"
    verify_reviewed_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    assert_runbook_order
    assert_existing_main_window_is_reused
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
verify_reviewed_lineage
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
