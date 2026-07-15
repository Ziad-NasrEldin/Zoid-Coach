#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly STACKED_PARENT="8c9e007d467fe2b5388e151914a559a8245d18ed"
readonly RUNBOOK="$REPOSITORY/docs/ZC-061-008-SIGNED-QA-RUNBOOK.md"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift
    Scripts/qa-zc061008-future-rule-fixture.sh
    Scripts/qa-zc061008-future-rule-ax-probe.swift
    Scripts/qa-zc061008-signed-preflight.sh
    Scripts/verify-zc-061-008-future-rule-static.sh
    docs/ZC-061-008-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
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
    git -C "$REPOSITORY" cat-file -e "$candidate^{commit}" || fail "candidate is unavailable"
    [[ "$(git -C "$REPOSITORY" rev-parse "$candidate^")" == "$STACKED_PARENT" ]] \
        || fail "candidate is not a direct child of $STACKED_PARENT"
    local expected actual
    expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
    actual="$(git -C "$REPOSITORY" diff --name-only "$STACKED_PARENT" "$candidate" -- | normalized_lines)"
    [[ "$actual" == "$expected" ]] || fail "candidate differs from the exact six-file scope"
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_full_lowercase_sha "$STACKED_PARENT" || fail "stacked parent SHA is invalid"
    git -C "$REPOSITORY" cat-file -e "$STACKED_PARENT^{commit}" || fail "stacked parent is unavailable"
    git -C "$REPOSITORY" merge-base --is-ancestor "$STACKED_PARENT" HEAD \
        || fail "worktree is not stacked on the required parent"
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/AgentMain.swift" \
        || fail "installed helper no longer supports --once"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc061008-future-rule-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc061008-future-rule-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-061-008 signed preflight self-test"
    exit 0
fi

(( $# == 4 )) || fail "usage: $0 --self-test | <app> <database> <screenwatch-root> <expected-signed-commit>"
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

ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
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
