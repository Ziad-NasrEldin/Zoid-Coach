#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="ed5d07a363e0f64049c07b0e1d309d754caa035b"
readonly PRODUCT_CANDIDATE="73edbf228af32907b1d4a899208b243efd443641"
readonly PROBE="$SCRIPT_DIR/qa-zc052002-local-database-actions-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc052002-local-database-actions-fixture.sh"
readonly -a PRODUCT_PATHS=(
    "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift"
    "Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift"
    "Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift"
)
readonly -a TOOLING_PATHS=(
    "Scripts/fixtures/zc-052-002-local-database-actions.json"
    "Scripts/qa-zc052002-local-database-actions-ax-probe.swift"
    "Scripts/qa-zc052002-local-database-actions-fixture.sh"
    "Scripts/qa-zc052002-signed-preflight.sh"
    "Scripts/verify-zc-052-002-local-database-actions-static.sh"
    "docs/ZC-052-002-SIGNED-QA-RUNBOOK.md"
)
readonly PRODUCT_BLOBS="03f902f7a7d3d2ea43358fa34c9fd6c5e0125bc9 Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift
d4147ed56ccd67868ea786394063f4f7ab16573a Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift
61487666b40254e6202c2c2b2fd337ce537ab2f5 Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift"

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

verify_candidate_lineage() {
    local expected_commit="$1"
    local expected_scope actual_scope expected_tooling_scope actual_tooling_scope entry expected_blob path actual_blob
    [[ "$(git -C "$REPOSITORY" rev-parse HEAD)" == "$expected_commit" ]] \
        || fail "repository HEAD does not match the signed commit"
    [[ -z "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]] \
        || fail "candidate worktree is not clean"
    [[ "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE^")" == "$CANONICAL_BASE" ]] \
        || fail "reviewed product candidate no longer descends directly from canonical base"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected_commit^")" == "$PRODUCT_CANDIDATE" ]] \
        || fail "signed tooling commit must descend directly from the reviewed product candidate"
    [[ -z "$(git -C "$REPOSITORY" rev-list --min-parents=2 "$CANONICAL_BASE..$expected_commit")" ]] \
        || fail "candidate lineage contains a merge commit"

    expected_scope="$(printf '%s\n' "${PRODUCT_PATHS[@]}" "${TOOLING_PATHS[@]}")"
    actual_scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE..$expected_commit")"
    has_exact_lines "$actual_scope" "$expected_scope" \
        || fail "signed commit differs from the exact reviewed nine-file scope"
    expected_tooling_scope="$(printf '%s\n' "${TOOLING_PATHS[@]}")"
    actual_tooling_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected_commit")"
    has_exact_lines "$actual_tooling_scope" "$expected_tooling_scope" \
        || fail "tooling commit contains product or unrelated changes"
    ! grep -Eqi '(tracker|registry|backlog|\.lavish)' <<<"$actual_scope" \
        || fail "protected tracker, registry, backlog, or Lavish path entered the candidate"

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        expected_blob="${entry%% *}"
        path="${entry#* }"
        actual_blob="$(git -C "$REPOSITORY" rev-parse "$expected_commit:$path")" \
            || fail "reviewed product file is missing: $path"
        [[ "$actual_blob" == "$expected_blob" ]] \
            || fail "reviewed product file changed during tooling: $path"
    done <<<"$PRODUCT_BLOBS"
}

run_self_test() {
    local product_scope tooling_scope full_scope
    product_scope="$(printf '%s\n' "${PRODUCT_PATHS[@]}")"
    tooling_scope="$(printf '%s\n' "${TOOLING_PATHS[@]}")"
    full_scope="$product_scope"$'\n'"$tooling_scope"
    is_sha "$PRODUCT_CANDIDATE" || fail "valid product SHA was rejected"
    ! is_sha "${PRODUCT_CANDIDATE:u}" || fail "uppercase SHA was accepted"
    has_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" \
        || fail "QA foreground argument was rejected"
    ! has_argument "/tmp/Zoid666" "--qa-open-main" \
        || fail "ordinary launch was mistaken for QA foreground launch"
    has_exact_lines "$full_scope" "$full_scope" || fail "exact scope was rejected"
    ! has_exact_lines "$full_scope"$'\n''docs/scenario-registry.json' "$full_scope" \
        || fail "registry scope escape was accepted"
    ! has_exact_lines "$(sed '$d' <<<"$full_scope")" "$full_scope" \
        || fail "missing tooling path was accepted"
    "$FIXTURE" --self-test >/dev/null
    swift "$PROBE" --self-test >/dev/null
    print -- "PASS: ZC-052-002 signed preflight scope, fixture, AX, and negative self-test"
}

if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit 0
fi

(( $# >= 3 )) || fail "usage: ${0:t} <app> <database> <expected-commit> [--require-qa-open-main|--require-ordinary-open] [--expected-app-pid <pid>]"
readonly APP="$1"
readonly DATABASE="$2"
readonly EXPECTED_COMMIT="$3"
shift 3
REQUIRE_QA_OPEN_MAIN=0
REQUIRE_ORDINARY_OPEN=0
EXPECTED_APP_PID=""
while (( $# > 0 )); do
    case "$1" in
        --require-qa-open-main) REQUIRE_QA_OPEN_MAIN=1; shift ;;
        --require-ordinary-open) REQUIRE_ORDINARY_OPEN=1; shift ;;
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        *) fail "unsupported preflight option: $1" ;;
    esac
done
(( ! REQUIRE_QA_OPEN_MAIN || ! REQUIRE_ORDINARY_OPEN )) \
    || fail "launch requirements are mutually exclusive"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
verify_candidate_lineage "$EXPECTED_COMMIT"

readonly CANONICAL_APP="${APP:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$CANONICAL_APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$APP_EXECUTABLE" ]] || fail "installed app executable is unavailable"
[[ "$APP_ROOT" == "$QA_ROOT" && "$AGENT_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper QA roots differ"
[[ "$DATABASE" == "$EXPECTED_DATABASE" ]] \
    || fail "database path does not match the embedded isolated QA root"
! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 \
    || fail "helper must remain unregistered during isolated database replacement"

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

readonly APP_PID="$(matching_pid)" || fail "installed foreground app process is unavailable"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] \
    || fail "visible app PID changed"
readonly APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
! has_argument "$APP_COMMAND" "--background-schedule" \
    || fail "bound app process is background-only"
if (( REQUIRE_QA_OPEN_MAIN )); then
    has_argument "$APP_COMMAND" "--qa-open-main" || fail "QA foreground argument is absent"
fi
if (( REQUIRE_ORDINARY_OPEN )); then
    ! has_argument "$APP_COMMAND" "--qa-open-main" || fail "ordinary relaunch retained QA foreground argument"
    swift "$PROBE" --pid "$APP_PID" --phase window >/dev/null \
        || fail "ordinary relaunch has no unique visible main window"
fi

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=UNREGISTERED"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-052-002 signed package, foreground process, helper isolation, and candidate lineage are bound"
