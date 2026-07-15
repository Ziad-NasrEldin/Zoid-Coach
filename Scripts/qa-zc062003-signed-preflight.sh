#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PARENT="72854220dd3c1de0ff1a8c7e701a9a966912226d"
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
    local candidate="$1" expected actual
    [[ "$(git -C "$REPOSITORY" rev-parse "$candidate^")" == "$PARENT" ]] || fail "candidate is not a direct child of ZC-062-002"
    expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized)"
    actual="$(git -C "$REPOSITORY" diff --name-only "$PARENT" "$candidate" -- | normalized)"
    [[ "$actual" == "$expected" ]] || fail "candidate differs from exact six-file scope"
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
    git -C "$REPOSITORY" cat-file -e "$PARENT^{commit}" || fail "stacked parent unavailable"
    git -C "$REPOSITORY" merge-base --is-ancestor "$PARENT" HEAD || fail "worktree is not stacked on ZC-062-002"
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
