#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
if [[ "${1:-}" == "--self-test" && "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
    readonly REPOSITORY="${ZOID_PREFLIGHT_REPOSITORY_OVERRIDE:?missing internal repository override}"
else
    readonly REPOSITORY="${SCRIPT_DIR:h}"
fi
readonly STACKED_PARENT="0f82cbc3dd12252a3ed8f08a65210cfc72dcf6b2"
readonly CORRECTED_TIP="8c9e007d467fe2b5388e151914a559a8245d18ed"
readonly RUNBOOK="$REPOSITORY/docs/ZC-061-005-SIGNED-QA-RUNBOOK.md"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC061005InsufficientEvidenceJourneyTests.swift
    Scripts/qa-zc061005-insufficient-evidence-fixture.sh
    Scripts/qa-zc061005-insufficient-evidence-ax-probe.swift
    Scripts/qa-zc061005-signed-preflight.sh
    Scripts/verify-zc-061-005-insufficient-evidence-static.sh
    docs/ZC-061-005-SIGNED-QA-RUNBOOK.md
)

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

normalized_lines() {
    sed '/^$/d' | LC_ALL=C sort -u
}

assert_runbook_shell_blocks_fail_fast() {
    [[ -f "$RUNBOOK" ]] || fail "signed QA runbook is missing"
    awk '
        /^```sh$/ { checking = 1; found = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking || !found) exit 1 }
    ' "$RUNBOOK" || fail "every runbook shell block must begin with set -euo pipefail"
}

assert_candidate_lineage_and_scope() {
    local candidate="$1"
    is_full_lowercase_sha "$candidate" || fail "candidate must be a full lowercase SHA"
    local resolved head merge_base expected actual
    resolved="$(git -C "$REPOSITORY" rev-parse --verify "$candidate^{commit}")" \
        || fail "candidate commit is unavailable"
    [[ "$resolved" == "$candidate" ]] || fail "candidate did not resolve to the exact requested commit"
    head="$(git -C "$REPOSITORY" rev-parse --verify HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$resolved" ]] || fail "candidate must equal repository HEAD"
    git -C "$REPOSITORY" merge-base --is-ancestor "$STACKED_PARENT" "$resolved" \
        || fail "required parent is not an ancestor of the candidate"
    merge_base="$(git -C "$REPOSITORY" merge-base "$STACKED_PARENT" "$resolved")" \
        || fail "candidate has no merge base with the required parent"
    [[ "$merge_base" == "$STACKED_PARENT" ]] || fail "candidate merge base is not the required parent"
    expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
    actual="$(git -C "$REPOSITORY" diff --name-only "$STACKED_PARENT" "$resolved" -- | normalized_lines)"
    [[ "$actual" == "$expected" ]] || fail "signed candidate differs from the exact six-file scope"
}

assert_corrected_tip_with_runtime_contract() {
    local temporary_root checkout
    temporary_root="$(mktemp -d /private/tmp/zoid-zc061005-lineage.XXXXXX)"
    checkout="$temporary_root/repository"
    cleanup_corrected_tip_worktree() {
        git -C "$REPOSITORY" worktree remove --force "$checkout" >/dev/null 2>&1 || true
        rm -rf "$temporary_root"
    }
    trap cleanup_corrected_tip_worktree EXIT HUP INT TERM
    git -C "$REPOSITORY" worktree add --detach "$checkout" "$CORRECTED_TIP" >/dev/null
    env ZOID_PREFLIGHT_REPOSITORY_OVERRIDE="$checkout" \
        ZOID_PREFLIGHT_ASSERT_ONLY=1 \
        ZOID_PREFLIGHT_ASSERT_CANDIDATE="$CORRECTED_TIP" \
        "$SCRIPT_PATH" --self-test >/dev/null
    if env ZOID_PREFLIGHT_REPOSITORY_OVERRIDE="$checkout" \
        ZOID_PREFLIGHT_ASSERT_ONLY=1 \
        ZOID_PREFLIGHT_ASSERT_CANDIDATE="$STACKED_PARENT" \
        "$SCRIPT_PATH" --self-test >/dev/null 2>&1; then
        fail "required parent was accepted as the checked-out candidate"
    fi
    cleanup_corrected_tip_worktree
    trap - EXIT HUP INT TERM
}

if [[ "${1:-}" == "--self-test" ]]; then
    if [[ "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
        assert_candidate_lineage_and_scope "${ZOID_PREFLIGHT_ASSERT_CANDIDATE:-}"
        exit 0
    fi
    is_full_lowercase_sha "$STACKED_PARENT" || fail "stacked parent SHA is invalid"
    is_full_lowercase_sha "$CORRECTED_TIP" || fail "corrected tip SHA is invalid"
    ! is_full_lowercase_sha "${STACKED_PARENT:u}" || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "3df007c" || fail "abbreviated SHA was accepted"
    git -C "$REPOSITORY" cat-file -e "$STACKED_PARENT^{commit}" \
        || fail "stacked parent is unavailable"
    assert_corrected_tip_with_runtime_contract
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/AgentMain.swift" \
        || fail "installed helper no longer supports the bounded --once path"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc061005-insufficient-evidence-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc061005-insufficient-evidence-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-061-005 signed preflight self-test"
    exit 0
fi

(( $# == 4 )) || fail "usage: $0 --self-test | <app> <database> <os-state> <expected-signed-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly OS_STATE="${3:A}"
readonly EXPECTED_COMMIT="$4"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
[[ -f "$OS_STATE" && ! -L "$OS_STATE" ]] || fail "isolated OS fixture state is unavailable or unsafe"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_candidate_lineage_and_scope "$EXPECTED_COMMIT"

ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly EXPECTED_OS_STATE="${QA_ROOT:A}/OS Fixtures/state.json"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"

[[ "$QA_ROOT" == /private/tmp/zoid-666-zc061005-* ]] \
    || fail "signed package uses an unexpected QA root namespace"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not share the isolated QA root"
[[ "${DATABASE:A}" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the exact embedded QA database"
[[ "${OS_STATE:A}" == "$EXPECTED_OS_STATE" ]] \
    || fail "OS state is not the exact embedded QA fixture state"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "signed helper executable is unavailable"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT"* ]] \
    || fail "helper does not resolve the isolated signed QA runtime"

print -- "QA_ROOT=${QA_ROOT:A}"
print -- "DATABASE=${DATABASE:A}"
print -- "OS_STATE=${OS_STATE:A}"
print -- "AGENT_EXECUTABLE=${AGENT_EXECUTABLE:A}"
print -- "AGENT_LABEL=$AGENT_LABEL"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "STACKED_PARENT=$STACKED_PARENT"
print -- "PASS: signed candidate, direct parent, exact scope, helper --once, and isolated runtime are bound"
