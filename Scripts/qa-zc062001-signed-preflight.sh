#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
if [[ "${1:-}" == "--self-test" && "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
    readonly REPOSITORY="${ZOID_PREFLIGHT_REPOSITORY_OVERRIDE:?missing internal repository override}"
else
    readonly REPOSITORY="${SCRIPT_DIR:h}"
fi
readonly STACKED_PARENT="762c2c9dfcd59a27fd9e272993e2c3c556c9d6df"
readonly CORRECTED_TIP="e38794acb3068ed16051c6eb820405319dbda912"
readonly RUNBOOK="$REPOSITORY/docs/ZC-062-001-SIGNED-QA-RUNBOOK.md"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062001HealthyWorkdayJourneyTests.swift
    Scripts/qa-zc062001-healthy-workday-fixture.sh
    Scripts/qa-zc062001-healthy-workday-ax-probe.swift
    Scripts/qa-zc062001-signed-preflight.sh
    Scripts/verify-zc-062-001-healthy-workday-static.sh
    docs/ZC-062-001-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized_lines() { sed '/^$/d' | LC_ALL=C sort -u; }
is_full_lowercase_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
is_exact_owned_path() { [[ "${1:A}" == "${2:A}" ]]; }

assert_runbook_shell_blocks_fail_fast() {
    awk '
        /^```sh$/ { checking=1; found=1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking=0 }
        END { if (checking || !found) exit 1 }
    ' "$RUNBOOK" || fail "every runbook shell block must begin with set -euo pipefail"
}

assert_candidate() {
    local candidate="$1" expected actual
    is_full_lowercase_sha "$candidate" || fail "candidate must be a full lowercase SHA"
    local resolved head merge_base
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
    temporary_root="$(mktemp -d /private/tmp/zoid-zc062001-lineage.XXXXXX)"
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
    print '\n' >> "$checkout/${EXPECTED_PATHS[1]}"
    git -C "$checkout" add -- "${EXPECTED_PATHS[1]}"
    git -C "$checkout" -c user.name='Zoid Preflight Self-Test' \
        -c user.email='zoid-preflight-self-test@invalid' \
        -c core.hooksPath=/dev/null \
        commit -m 'test: create unreviewed allowlisted descendant' >/dev/null
    downstream_candidate="$(git -C "$checkout" rev-parse --verify HEAD)"
    if env ZOID_PREFLIGHT_REPOSITORY_OVERRIDE="$checkout" \
        ZOID_PREFLIGHT_ASSERT_ONLY=1 \
        ZOID_PREFLIGHT_ASSERT_CANDIDATE="$downstream_candidate" \
        "$SCRIPT_PATH" --self-test >/dev/null 2>&1; then
        fail "unreviewed allowlisted-path descendant was accepted"
    fi
    cleanup_corrected_tip_worktree
    trap - EXIT HUP INT TERM
}

if [[ "${1:-}" == --self-test ]]; then
    if [[ "${ZOID_PREFLIGHT_ASSERT_ONLY:-0}" == 1 ]]; then
        assert_candidate "${ZOID_PREFLIGHT_ASSERT_CANDIDATE:-}"
        exit 0
    fi
    is_full_lowercase_sha "$STACKED_PARENT" || fail "stacked parent SHA is invalid"
    is_full_lowercase_sha "$CORRECTED_TIP" || fail "corrected tip SHA is invalid"
    ! is_full_lowercase_sha "${STACKED_PARENT:u}" || fail "uppercase SHA accepted"
    ! is_full_lowercase_sha "0c6e749" || fail "abbreviated SHA accepted"
    assert_corrected_tip_with_runtime_contract
    is_exact_owned_path "/private/tmp/zoid-666-zc062001-self/Application Support/Zoid 666/zoid-coach.sqlite" "/private/tmp/zoid-666-zc062001-self/Application Support/Zoid 666/zoid-coach.sqlite" \
        || fail "exact database path rejected"
    ! is_exact_owned_path "/private/tmp/zoid-666-zc062001-other/zoid-coach.sqlite" "/private/tmp/zoid-666-zc062001-self/Application Support/Zoid 666/zoid-coach.sqlite" \
        || fail "wrong database path accepted"
    ! is_exact_owned_path "/private/tmp/wrong-helper" "/private/tmp/app/Contents/MacOS/ZoidCoachAgent" \
        || fail "wrong helper path accepted"
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/AgentMain.swift" \
        || fail "installed helper no longer supports --once"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc062001-healthy-workday-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc062001-healthy-workday-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-062-001 signed preflight self-test"
    exit 0
fi

(( $# == 4 )) || fail "usage: $0 --self-test | <app> <database> <screenwatch-root> <expected-signed-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly SCREENWATCH_ROOT="${3:A}"
readonly EXPECTED_COMMIT="$4"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" && ! -L "$DATABASE" ]] || fail "canonical database is unavailable or unsafe"
[[ -d "$SCREENWATCH_ROOT" && ! -L "$SCREENWATCH_ROOT" ]] || fail "Screenwatch root is unavailable or unsafe"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
assert_candidate "$EXPECTED_COMMIT"

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
readonly EXPECTED_SCREENWATCH="${QA_ROOT:A}/Screenwatch/days"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="${APP:A}/$AGENT_PROGRAM"
readonly EXPECTED_HELPER="${APP:A}/Contents/MacOS/ZoidCoachAgent"

[[ "$QA_ROOT" == /private/tmp/zoid-666-zc062001-* ]] || fail "unexpected QA root namespace"
[[ "$APP_QA_ROOT" == "$QA_ROOT" && "$AGENT_QA_ROOT" == "$QA_ROOT" ]] \
    || fail "app and helper do not share the isolated QA root"
is_exact_owned_path "$DATABASE" "$EXPECTED_DATABASE" || fail "wrong canonical database"
is_exact_owned_path "$SCREENWATCH_ROOT" "$EXPECTED_SCREENWATCH" || fail "wrong Screenwatch root"
is_exact_owned_path "$AGENT_EXECUTABLE" "$EXPECTED_HELPER" || fail "wrong helper executable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "installed helper is unavailable"

readonly HELPER_RUNTIME="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)"
[[ "$HELPER_RUNTIME" == *"package=qa mode=qa"*" root=$QA_ROOT"* ]] \
    || fail "helper does not resolve the isolated signed QA runtime"

print -- "QA_ROOT=${QA_ROOT:A}"
print -- "DATABASE=$DATABASE"
print -- "SCREENWATCH_ROOT=$SCREENWATCH_ROOT"
print -- "AGENT_EXECUTABLE=${AGENT_EXECUTABLE:A}"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "STACKED_PARENT=$STACKED_PARENT"
print -- "PASS: signed lineage, exact scope, source/database/helper ownership, and isolated runtime are bound"
