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
readonly STACKED_PARENT="8c9e007d467fe2b5388e151914a559a8245d18ed"
readonly CORRECTED_TIP="762c2c9dfcd59a27fd9e272993e2c3c556c9d6df"
readonly RUNBOOK="$REPOSITORY/docs/ZC-061-008-SIGNED-QA-RUNBOOK.md"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift
    Scripts/qa-zc061008-future-rule-fixture.sh
    Scripts/qa-zc061008-future-rule-ax-probe.swift
    Scripts/qa-zc061008-signed-preflight.sh
    Scripts/verify-zc-061-008-future-rule-static.sh
    docs/ZC-061-008-SIGNED-QA-RUNBOOK.md
)

normalized_lines() { sed '/^$/d' | LC_ALL=C sort -u; }
is_full_lowercase_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }

assert_runbook_shell_blocks_fail_fast() {
    awk '
        /^```sh$/ { checking = 1; found = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking || !found) exit 1 }
    ' "$RUNBOOK" || fail "every runbook shell block must begin with set -euo pipefail"
}

assert_candidate() {
    local candidate="$1"
    is_full_lowercase_sha "$candidate" || fail "candidate must be a full lowercase SHA"
    [[ -z "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]] \
        || fail "candidate repository must be clean"
    local resolved head merge_base expected actual
    resolved="$(git -C "$REPOSITORY" rev-parse --verify "$candidate^{commit}")" \
        || fail "candidate is unavailable"
    [[ "$resolved" == "$candidate" ]] || fail "candidate did not resolve to the exact requested commit"
    [[ "$resolved" == "$CORRECTED_TIP" ]] || fail "candidate is not the reviewed corrected tip"
    head="$(git -C "$REPOSITORY" rev-parse --verify HEAD)" || fail "repository HEAD is unavailable"
    [[ "$head" == "$resolved" ]] || fail "candidate must equal repository HEAD"
    git -C "$REPOSITORY" merge-base --is-ancestor "$STACKED_PARENT" "$resolved" \
        || fail "required parent is not an ancestor of the candidate"
    merge_base="$(git -C "$REPOSITORY" merge-base "$STACKED_PARENT" "$resolved")" \
        || fail "candidate has no merge base with the required parent"
    [[ "$merge_base" == "$STACKED_PARENT" ]] || fail "candidate merge base is not the required parent"
    expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
    actual="$(git -C "$REPOSITORY" diff --name-only "$STACKED_PARENT" "$resolved" -- | normalized_lines)"
    [[ "$actual" == "$expected" ]] || fail "candidate differs from the exact six-file scope"
}

assert_corrected_tip_with_runtime_contract() {
    local temporary_root checkout downstream_candidate
    temporary_root="$(mktemp -d /private/tmp/zoid-zc061008-lineage.XXXXXX)"
    checkout="$temporary_root/repository"
    cleanup_corrected_tip_worktree() {
        git -C "$VALIDATOR_REPOSITORY" worktree remove --force "$checkout" >/dev/null 2>&1 || true
        rm -rf "$temporary_root"
    }
    trap cleanup_corrected_tip_worktree EXIT HUP INT TERM
    git -C "$VALIDATOR_REPOSITORY" worktree add --detach "$checkout" "$CORRECTED_TIP" >/dev/null
    "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$CORRECTED_TIP" >/dev/null
    if "$SCRIPT_PATH" --candidate-repository "$checkout" \
        --validate-candidate "$STACKED_PARENT" >/dev/null 2>&1; then
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

if [[ "${1:-}" == "--self-test" ]]; then
    is_full_lowercase_sha "$STACKED_PARENT" || fail "stacked parent SHA is invalid"
    is_full_lowercase_sha "$CORRECTED_TIP" || fail "corrected tip SHA is invalid"
    ! is_full_lowercase_sha "${STACKED_PARENT:u}" || fail "uppercase SHA was accepted"
    ! is_full_lowercase_sha "8c9e007" || fail "abbreviated SHA was accepted"
    git -C "$REPOSITORY" cat-file -e "$STACKED_PARENT^{commit}" || fail "stacked parent is unavailable"
    assert_corrected_tip_with_runtime_contract
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/AgentMain.swift" \
        || fail "installed helper no longer supports --once"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc061008-future-rule-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc061008-future-rule-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-061-008 signed preflight self-test"
    exit 0
fi

if [[ "${1:-}" == "--validate-candidate" ]]; then
    (( CANDIDATE_REPOSITORY_PROVIDED )) || fail "--validate-candidate requires --candidate-repository"
    (( $# == 2 )) || fail "usage: $SCRIPT_PATH --candidate-repository <worktree> --validate-candidate <commit>"
    assert_candidate "$2"
    print -- "PASS: reviewed ZC-061-008 candidate worktree is clean and exactly bound"
    exit 0
fi

(( CANDIDATE_REPOSITORY_PROVIDED )) || fail "runtime validation requires --candidate-repository"
(( $# == 4 )) || fail "usage: $SCRIPT_PATH --self-test | --candidate-repository <worktree> --validate-candidate <commit> | --candidate-repository <worktree> <app> <database> <screenwatch-root> <expected-signed-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly SCREENWATCH_ROOT="${3:A}"
readonly EXPECTED_COMMIT="$4"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
[[ -d "$SCREENWATCH_ROOT" && ! -L "$SCREENWATCH_ROOT" ]] \
    || fail "isolated Screenwatch root is unavailable or unsafe"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_candidate "$EXPECTED_COMMIT"

ZOID_COACH_PACKAGE_MODE=qa "$REPOSITORY/Scripts/verify-package.sh" \
    "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_QA_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$APP/$AGENT_PROGRAM"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
readonly EXPECTED_SCREENWATCH_ROOT="${QA_ROOT:A}/Screenwatch/days"

[[ "$QA_ROOT" == /private/tmp/zoid-666-zc061008-* ]] \
    || fail "signed package uses an unexpected QA root namespace"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not share the isolated QA root"
[[ "$DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database is not the embedded QA database"
[[ "$SCREENWATCH_ROOT" == "$EXPECTED_SCREENWATCH_ROOT" ]] \
    || fail "Screenwatch root is not the embedded helper source"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "signed helper executable is unavailable"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT"* ]] \
    || fail "helper does not resolve the isolated signed QA runtime"

print -- "QA_ROOT=${QA_ROOT:A}"
print -- "DATABASE=$DATABASE"
print -- "SCREENWATCH_ROOT=$SCREENWATCH_ROOT"
print -- "AGENT_EXECUTABLE=${AGENT_EXECUTABLE:A}"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "STACKED_PARENT=$STACKED_PARENT"
print -- "PASS: signed candidate, direct parent, exact scope, helper --once, and isolated Screenwatch runtime are bound"
