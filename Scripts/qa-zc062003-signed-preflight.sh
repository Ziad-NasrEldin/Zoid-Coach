#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
if [[ "${1:-}" == "--self-test" && "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
    readonly REPOSITORY="${ZOID_PREFLIGHT_REPOSITORY_OVERRIDE:?missing internal repository override}"
else
    readonly REPOSITORY="${SCRIPT_DIR:h}"
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

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
normalized() { sed '/^$/d' | LC_ALL=C sort -u; }

assert_scope() {
    local candidate="$1" resolved head merge_base expected actual
    is_sha "$candidate" || fail "candidate must be a full lowercase SHA"
    resolved="$(git -C "$REPOSITORY" rev-parse --verify "$candidate^{commit}")" \
        || fail "candidate is unavailable"
    [[ "$resolved" == "$candidate" ]] || fail "candidate did not resolve to the exact requested commit"
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
    local temporary_root checkout
    temporary_root="$(mktemp -d /private/tmp/zoid-zc062003-lineage.XXXXXX)"
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
        ZOID_PREFLIGHT_ASSERT_CANDIDATE="$PARENT" \
        "$SCRIPT_PATH" --self-test >/dev/null 2>&1; then
        fail "required parent was accepted as the checked-out candidate"
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
    if [[ "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
        assert_scope "${ZOID_PREFLIGHT_ASSERT_CANDIDATE:-}"
        exit 0
    fi
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

(( $# == 5 )) || fail "usage: $0 --self-test | <app> <database> <Screenwatch-root> <os-state> <expected-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly SCREENWATCH_ROOT="${3:A}"
readonly OS_STATE="${4:A}"
readonly EXPECTED_COMMIT="$5"
[[ -d "$APP" && -f "$DATABASE" && -d "$SCREENWATCH_ROOT" && -f "$OS_STATE" ]] || fail "runtime inputs are missing"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_scope "$EXPECTED_COMMIT"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

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
