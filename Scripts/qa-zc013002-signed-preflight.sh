#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="b73a1c1c489eb02017d8609eab7a056296065819"
readonly ORIGINAL_PRODUCT_CANDIDATE="f9bb51ba3ca3f323f10cabe8729bb10f532bbb4f"
readonly PRODUCT_CANDIDATE="fc776ce000bd23b8c83d64b398399827d95c293c"
readonly ORIGINAL_TOOLING_CANDIDATE="d15bcfe6bd2c637176861a357e59636afaaad8ba"
readonly READY_BOOTSTRAP_CANDIDATE="d46324a257a7475799228f69b1e1aa3932c1e832"
readonly FOREGROUND_BINDING_CANDIDATE="e0e79e7ef20981cbc3280ab2b3190a200f94ecbc"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc013002-coaching-status-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc013002-coaching-status-fixture.sh"
readonly BOOTSTRAP="$SCRIPT_DIR/qa-zc013002-signed-bootstrap.sh"
readonly PRODUCT_BLOBS="6dc23615d1ace05b69026fc9c3026f72fe110864 Sources/ZoidCoachApp/AppModel.swift
caf58905e3202e976510b068957165ade57761a6 Sources/ZoidCoachApp/CoachingStatePresentation.swift
223d7674fc0efbbcc4049bac750d2d7573698441 Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
de5253d653de9bbde129624f35bc3e4b354925e2 Tests/ZoidCoachAppTests/CoachingStatePresentationTests.swift"
readonly -a PRODUCT_FILES=(
    Sources/ZoidCoachApp/AppModel.swift
    Sources/ZoidCoachApp/CoachingStatePresentation.swift
    Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
    Tests/ZoidCoachAppTests/CoachingStatePresentationTests.swift
)
readonly -a TOOLING_FILES=(
    Scripts/qa-zc013002-coaching-status-ax-probe.swift
    Scripts/qa-zc013002-coaching-status-fixture.sh
    Scripts/qa-zc013002-signed-bootstrap.sh
    Scripts/qa-zc013002-signed-preflight.sh
    docs/ZC-013-002-SIGNED-QA-RUNBOOK.md
)
readonly -a REBOUND_FILES=(
    Scripts/qa-zc013002-signed-bootstrap.sh
    Scripts/qa-zc013002-signed-preflight.sh
    docs/ZC-013-002-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1 }
normalized() { print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }

verify_lineage() {
    local expected="$1" scope head_scope entry expected_blob owned_path actual_blob
    [[ "$(git -C "$REPOSITORY" rev-parse HEAD)" == "$expected" ]] || fail "HEAD differs from expected signed commit"
    [[ -z "$(git -C "$REPOSITORY" status --porcelain)" ]] || fail "candidate worktree is not clean"
    [[ "$(git -C "$REPOSITORY" rev-parse "$ORIGINAL_PRODUCT_CANDIDATE^")" == "$CANONICAL_BASE" ]] || fail "original product does not descend directly from canonical"
    [[ "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE^")" == "$ORIGINAL_PRODUCT_CANDIDATE" ]] || fail "runtime binding does not descend directly from original product"
    [[ "$(git -C "$REPOSITORY" rev-parse "$ORIGINAL_TOOLING_CANDIDATE^")" == "$PRODUCT_CANDIDATE" ]] || fail "original tooling does not descend directly from product"
    [[ "$(git -C "$REPOSITORY" rev-parse "$READY_BOOTSTRAP_CANDIDATE^")" == "$ORIGINAL_TOOLING_CANDIDATE" ]] || fail "ready-state tooling does not descend directly from original tooling"
    [[ "$(git -C "$REPOSITORY" rev-parse "$FOREGROUND_BINDING_CANDIDATE^")" == "$READY_BOOTSTRAP_CANDIDATE" ]] || fail "foreground binding fix does not descend directly from ready-state tooling"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected^")" == "$FOREGROUND_BINDING_CANDIDATE" ]] || fail "zsh iteration fix does not descend directly from foreground binding"
    [[ -z "$(git -C "$REPOSITORY" rev-list --merges "$CANONICAL_BASE..$expected")" ]] || fail "candidate contains a merge"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE..$expected")"
    [[ "$(normalized "$scope")" == "$(printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}" | LC_ALL=C sort -u)" ]] || fail "candidate differs from exact eight-file scope"
    head_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected")"
    [[ "$(normalized "$head_scope")" == "$(printf '%s\n' "${REBOUND_FILES[@]}" | LC_ALL=C sort -u)" ]] || fail "foreground binding commit contains unrelated files"
    while IFS= read -r entry; do
        expected_blob="${entry%% *}"; owned_path="${entry#* }"
        actual_blob="$(git -C "$REPOSITORY" rev-parse "$expected:$owned_path")"
        [[ "$actual_blob" == "$expected_blob" ]] || fail "product blob changed during tooling: $owned_path"
    done <<< "$PRODUCT_BLOBS"
}

self_test() {
    [[ ${#PRODUCT_FILES[@]} == 4 && ${#TOOLING_FILES[@]} == 5 && ${#REBOUND_FILES[@]} == 3 ]] || fail "owned scope count changed"
    ! printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}" | rg -qi '(tracker|registry|backlog|\.lavish)' || fail "protected path entered scope"
    "$FIXTURE" self-test >/dev/null
    "$BOOTSTRAP" --self-test >/dev/null
    swift "$AX_PROBE" --self-test >/dev/null
    zsh -n "$FIXTURE" "$BOOTSTRAP" "$0"
    swiftc -typecheck "$AX_PROBE"
    verify_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    print -- "PASS: ZC-013-002 signed preflight scope, fixture, AX, and typecheck self-test"
}

exact_executable_for_pid() {
    local pid="$1" expected="$2"
    [[ "$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)" == "$expected" ]]
}

exact_database_for_pid() {
    local pid="$1" expected="$2" open_databases
    open_databases="$(lsof -Fn -a -p "$pid" 2>/dev/null | sed -n 's/^n//p' | grep -E '/zoid-coach\.sqlite$' | LC_ALL=C sort -u || true)"
    [[ "$open_databases" == "$expected" ]]
}

verify_live_binding() {
    local app="$1" database="$2" expected_commit="$3" pid="$4"
    local executable_name executable
    is_sha "$expected_commit" || fail "expected commit must be a full lowercase SHA"
    verify_lineage "$expected_commit"
    [[ "$app" == /private/tmp/zoid-zc013002-*/*.app ]] || fail "app is outside isolated QA namespace"
    [[ "$database" == /private/tmp/zoid-zc013002-*/Application\ Support/Zoid\ 666/zoid-coach.sqlite ]] || fail "database is outside isolated QA namespace"
    [[ -d "$app" && -f "$database" ]] || fail "app or database is missing"
    codesign --verify --deep --strict "$app" >/dev/null 2>&1 || fail "app signature is invalid"
    kill -0 "$pid" >/dev/null 2>&1 || fail "foreground PID is unavailable"
    executable_name="$(plutil -extract CFBundleExecutable raw -o - "$app/Contents/Info.plist")"
    executable="$app/Contents/MacOS/$executable_name"
    exact_executable_for_pid "$pid" "$executable" || fail "foreground PID is not the exact installed executable"
    exact_database_for_pid "$pid" "$database" || fail "foreground PID is not bound exclusively to the isolated database"
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit 0; fi
if [[ "${1:-}" == "--ready-app" ]]; then
    [[ $# == 5 ]] || fail "usage: --ready-app APP DATABASE EXPECTED_COMMIT PID"
    verify_live_binding "$2" "$3" "$4" "$5"
    swift "$AX_PROBE" --pid "$5" --ready
    print -- "PASS: ZC-013-002 ready app has exact signed identity, database ownership, Today UI, and no setup UI"
    exit 0
fi
[[ $# == 5 ]] || fail "usage: APP DATABASE EXPECTED_COMMIT PID PHASE"
readonly APP="${1:A}" DATABASE="${2:A}" EXPECTED_COMMIT="$3" PID="$4" PHASE="$5"
verify_live_binding "$APP" "$DATABASE" "$EXPECTED_COMMIT" "$PID"
swift "$AX_PROBE" --pid "$PID" --phase "$PHASE"
print -- "PASS: ZC-013-002 signed candidate, isolated database, foreground app, and accessible state are bound"
