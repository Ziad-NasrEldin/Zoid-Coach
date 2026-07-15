#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="361093b4a088c19eee927eaab2b58a40fb3b4c27"
readonly PRODUCT_CANDIDATE="26e139767ba253bd1039fad35c3dcf237468b612"
readonly AX_PROBE="$SCRIPT_DIR/qa-zc013002-coaching-status-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc013002-coaching-status-fixture.sh"
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
    [[ "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_CANDIDATE^")" == "$CANONICAL_BASE" ]] || fail "product does not descend directly from canonical"
    [[ "$(git -C "$REPOSITORY" rev-parse "$expected^")" == "$PRODUCT_CANDIDATE" ]] || fail "tooling does not descend directly from product"
    [[ -z "$(git -C "$REPOSITORY" rev-list --merges "$CANONICAL_BASE..$expected")" ]] || fail "candidate contains a merge"
    scope="$(git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE..$expected")"
    [[ "$(normalized "$scope")" == "$(printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}" | LC_ALL=C sort -u)" ]] || fail "candidate differs from exact eight-file scope"
    head_scope="$(git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$expected")"
    [[ "$(normalized "$head_scope")" == "$(printf '%s\n' "${TOOLING_FILES[@]}" | LC_ALL=C sort -u)" ]] || fail "tooling commit contains product or unrelated files"
    while IFS= read -r entry; do
        expected_blob="${entry%% *}"; owned_path="${entry#* }"
        actual_blob="$(git -C "$REPOSITORY" rev-parse "$expected:$owned_path")"
        [[ "$actual_blob" == "$expected_blob" ]] || fail "product blob changed during tooling: $owned_path"
    done <<< "$PRODUCT_BLOBS"
}

self_test() {
    [[ ${#PRODUCT_FILES[@]} == 4 && ${#TOOLING_FILES[@]} == 4 ]] || fail "owned scope count changed"
    ! printf '%s\n' "${PRODUCT_FILES[@]}" "${TOOLING_FILES[@]}" | rg -qi '(tracker|registry|backlog|\.lavish)' || fail "protected path entered scope"
    "$FIXTURE" self-test >/dev/null
    swift "$AX_PROBE" --self-test >/dev/null
    zsh -n "$FIXTURE" "$0"
    swiftc -typecheck "$AX_PROBE"
    verify_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    print -- "PASS: ZC-013-002 signed preflight scope, fixture, AX, and typecheck self-test"
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit 0; fi
[[ $# == 5 ]] || fail "usage: APP DATABASE EXPECTED_COMMIT PID PHASE"
readonly APP="${1:A}" DATABASE="${2:A}" EXPECTED_COMMIT="$3" PID="$4" PHASE="$5"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
verify_lineage "$EXPECTED_COMMIT"
[[ "$APP" == /private/tmp/zoid-zc013002-*/*.app ]] || fail "app is outside isolated QA namespace"
[[ "$DATABASE" == /private/tmp/zoid-zc013002-*/Application\ Support/Zoid\ 666/zoid-coach.sqlite ]] || fail "database is outside isolated QA namespace"
[[ -d "$APP" && -f "$DATABASE" ]] || fail "app or database is missing"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || fail "app signature is invalid"
kill -0 "$PID" >/dev/null 2>&1 || fail "foreground PID is unavailable"
swift "$AX_PROBE" --pid "$PID" --phase "$PHASE"
print -- "PASS: ZC-013-002 signed candidate, isolated database, foreground app, and accessible state are bound"
