#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
readonly VALIDATOR_REPOSITORY="${SCRIPT_DIR:h}"

fail() { print -u2 -- "FAIL: $*"; exit 1; }

canonical_candidate_repository() {
    local requested="$1" canonical top_level
    [[ "$requested" == /* ]] || fail "candidate repository must be an absolute path"
    [[ -d "$requested" && ! -L "$requested" ]] || fail "candidate repository is unavailable or unsafe"
    canonical="$(cd "$requested" && pwd -P)" || fail "candidate repository cannot be canonicalized"
    top_level="$(git -C "$canonical" rev-parse --show-toplevel 2>/dev/null)" \
        || fail "candidate repository is not a Git worktree"
    top_level="$(cd "$top_level" && pwd -P)" || fail "candidate repository root cannot be canonicalized"
    [[ "$canonical" == "$top_level" ]] || fail "candidate repository must name the worktree root"
    print -- "$canonical"
}

typeset -i CANDIDATE_REPOSITORY_PROVIDED=0
if [[ "${1:-}" == "--candidate-repository" ]]; then
    (( $# >= 2 )) || fail "missing value for --candidate-repository"
    readonly REPOSITORY="$(canonical_candidate_repository "$2")"
    CANDIDATE_REPOSITORY_PROVIDED=1
    shift 2
else
    readonly REPOSITORY="$VALIDATOR_REPOSITORY"
fi
readonly PARENT="e5ca6227964edd752b8d1b9709da48b9b6f791b6"
readonly CORRECTED_TIP="0fb1fe536e0f19d560e8b089936d31934ad1c41e"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift
    Scripts/qa-zc062003-source-warning-suppression-fixture.sh
    Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift
    Scripts/qa-zc062003-signed-preflight.sh
    Scripts/verify-zc-062-003-source-warning-suppression-static.sh
    docs/ZC-062-003-SIGNED-QA-RUNBOOK.md
)

is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
normalized() { sed '/^$/d' | LC_ALL=C sort -u; }

assert_scope() {
    local candidate="$1" resolved head merge_base expected actual
    is_sha "$candidate" || fail "candidate must be a full lowercase SHA"
    [[ -z "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]] \
        || fail "candidate repository must be clean"
    ! git -C "$REPOSITORY" symbolic-ref -q HEAD >/dev/null 2>&1 \
        || fail "candidate repository HEAD must be detached"
    resolved="$(git -C "$REPOSITORY" rev-parse --verify "$candidate^{commit}")" \
        || fail "candidate is unavailable"
    [[ "$resolved" == "$candidate" ]] || fail "candidate did not resolve to the exact requested commit"
    [[ "$resolved" == "$CORRECTED_TIP" ]] || fail "candidate is not the reviewed corrected tip"
    head="$(git -C "$REPOSITORY" rev-parse --verify HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$resolved" ]] || fail "candidate must equal repository HEAD"
    git -C "$REPOSITORY" merge-base --is-ancestor "$PARENT" "$resolved" \
        || fail "required parent is not an ancestor of the candidate"
    merge_base="$(git -C "$REPOSITORY" merge-base "$PARENT" "$resolved")" \
        || fail "candidate has no merge base with the required parent"
    [[ "$merge_base" == "$PARENT" ]] || fail "candidate merge base is not the required parent"
    expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized)"
    actual="$(git -C "$REPOSITORY" diff --name-only "$PARENT" "$resolved" -- | normalized)"
    [[ "$actual" == "$expected" ]] || fail "candidate differs from exact six-file scope"
}

assert_corrected_tip_with_runtime_contract() {
    local temporary_root checkout downstream_candidate branch_name
    temporary_root="$(mktemp -d /private/tmp/zoid-zc062003-lineage.XXXXXX)"
    checkout="$temporary_root/repository"
    branch_name="codex/zc062003-preflight-${temporary_root:t}"
    cleanup_corrected_tip_worktree() {
        git -C "$VALIDATOR_REPOSITORY" worktree remove --force "$checkout" >/dev/null 2>&1 || true
        git -C "$VALIDATOR_REPOSITORY" branch -D "$branch_name" >/dev/null 2>&1 || true
        rm -rf "$temporary_root"
    }
    trap cleanup_corrected_tip_worktree EXIT HUP INT TERM
    git -C "$VALIDATOR_REPOSITORY" worktree add --detach "$checkout" "$CORRECTED_TIP" >/dev/null
    "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$CORRECTED_TIP" >/dev/null
    git -C "$checkout" switch -c "$branch_name" >/dev/null 2>&1
    if "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$CORRECTED_TIP" >/dev/null 2>&1; then
        fail "clean branch checkout was accepted as a detached candidate"
    fi
    git -C "$checkout" switch --detach "$CORRECTED_TIP" >/dev/null 2>&1
    git -C "$VALIDATOR_REPOSITORY" branch -D "$branch_name" >/dev/null
    if "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$PARENT" >/dev/null 2>&1; then
        fail "required parent was accepted as the checked-out candidate"
    fi
    print '\n' >> "$checkout/${EXPECTED_PATHS[1]}"
    git -C "$checkout" add -- "${EXPECTED_PATHS[1]}"
    git -C "$checkout" -c user.name='Zoid Preflight Self-Test' \
        -c user.email='zoid-preflight-self-test@invalid' \
        -c core.hooksPath=/dev/null \
        commit -m 'test: create unreviewed allowlisted descendant' >/dev/null
    downstream_candidate="$(git -C "$checkout" rev-parse --verify HEAD)"
    if "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$downstream_candidate" >/dev/null 2>&1; then
        fail "unreviewed allowlisted-path descendant was accepted"
    fi
    cleanup_corrected_tip_worktree
    trap - EXIT HUP INT TERM
}

assert_runbook() {
    awk '
        /^```sh$/ { checking=1; found=1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking=0 }
        END { if (checking || !found) exit 1 }
    ' "$REPOSITORY/docs/ZC-062-003-SIGNED-QA-RUNBOOK.md" || fail "every runbook shell block must fail fast"
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_sha "$PARENT" || fail "invalid parent SHA"
    is_sha "$CORRECTED_TIP" || fail "invalid corrected tip SHA"
    ! is_sha "${PARENT:u}" || fail "uppercase SHA was accepted"
    ! is_sha "e5ca622" || fail "abbreviated SHA was accepted"
    git -C "$REPOSITORY" cat-file -e "$PARENT^{commit}" || fail "stacked parent unavailable"
    assert_corrected_tip_with_runtime_contract
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/AgentMain.swift" || fail "helper lacks bounded --once"
    assert_runbook
    "$SCRIPT_DIR/qa-zc062003-source-warning-suppression-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc062003-source-warning-suppression-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-062-003 signed preflight self-test"
    exit 0
fi

if [[ "${1:-}" == "--validate-candidate" ]]; then
    (( CANDIDATE_REPOSITORY_PROVIDED )) || fail "--validate-candidate requires --candidate-repository"
    (( $# == 2 )) || fail "usage: $SCRIPT_PATH --candidate-repository <worktree> --validate-candidate <commit>"
    assert_scope "$2"
    print -- "PASS: reviewed ZC-062-003 candidate worktree is clean and exactly bound"
    exit 0
fi

(( CANDIDATE_REPOSITORY_PROVIDED )) || fail "runtime validation requires --candidate-repository"
(( $# == 5 )) || fail "usage: $SCRIPT_PATH --self-test | --candidate-repository <worktree> --validate-candidate <commit> | --candidate-repository <worktree> <app> <database> <Screenwatch-root> <os-state> <expected-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly SCREENWATCH_ROOT="${3:A}"
readonly OS_STATE="${4:A}"
readonly EXPECTED_COMMIT="$5"
[[ -d "$APP" && -f "$DATABASE" && -d "$SCREENWATCH_ROOT" && -f "$OS_STATE" ]] || fail "runtime inputs are missing"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_scope "$EXPECTED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa "$REPOSITORY/Scripts/verify-package.sh" "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly HELPER_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
[[ "${QA_ROOT:A}" == /private/tmp/zoid-666-zc062003-* && ! -L "$QA_ROOT" ]] || fail "unsafe QA root"
[[ "$APP_ROOT" == "$QA_ROOT" && "$HELPER_ROOT" == "$QA_ROOT" ]] || fail "app/helper root mismatch"
[[ "${DATABASE:A}" == "${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite" ]] || fail "wrong database path accepted"
[[ "${SCREENWATCH_ROOT:A}" == "${QA_ROOT:A}/Screenwatch/days" ]] || fail "wrong source path accepted"
[[ "${OS_STATE:A}" == "${QA_ROOT:A}/OS Fixtures/state.json" ]] || fail "wrong OS state path accepted"
[[ "$AGENT_PROGRAM" == "Contents/MacOS/ZoidCoachAgent" && -x "$AGENT_EXECUTABLE" ]] || fail "wrong helper path accepted"
readonly RUNTIME_IDENTITY="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$RUNTIME_IDENTITY" == *"package=qa mode=qa"*" root=$QA_ROOT"* ]] || fail "helper runtime identity mismatch"
print -- "QA_ROOT=${QA_ROOT:A}"
print -- "AGENT_EXECUTABLE=${AGENT_EXECUTABLE:A}"
print -- "AGENT_LABEL=$AGENT_LABEL"
print -- "PASS: signed candidate, direct parent, exact scope, helper, database, source, and OS state are bound"
