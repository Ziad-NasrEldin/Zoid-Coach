#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PARENT="fb49217deed0846c3745aac1af396cc4a769f970"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }

assert_paths() {
    local app="$1" database="$2" source="$3"
    local info="$app/Contents/Info.plist" qa_root app_root helper_root plist program helper expected_database expected_source
    [[ -d "$app" && -f "$database" && -d "$source" ]] || fail "app, database, or isolated Screenwatch source is missing"
    qa_root="$(plutil -extract ZoidCoachQARunRoot raw -o - "$info")"
    [[ "${qa_root:A}" == /private/tmp/zoid-666-zc062002-* && ! -L "$qa_root" ]] || fail "unsafe QA root"
    app_root="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$info")"
    plist=("$app"/Contents/Library/LaunchAgents/*.plist(N))
    (( ${#plist} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent plist"
    helper_root="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$plist[1]")"
    program="$(plutil -extract BundleProgram raw -o - "$plist[1]")"
    helper="$app/$program"
    expected_database="${qa_root:A}/Application Support/Zoid 666/zoid-coach.sqlite"
    expected_source="${qa_root:A}/Screenwatch/days"
    [[ "$app_root" == "$qa_root" && "$helper_root" == "$qa_root" ]] || fail "app and helper QA roots differ"
    [[ "${database:A}" == "$expected_database" ]] || fail "wrong database path accepted"
    [[ "${source:A}" == "$expected_source" ]] || fail "wrong Screenwatch source accepted"
    [[ "$program" == "Contents/MacOS/ZoidCoachAgent" && -x "$helper" ]] || fail "wrong helper path accepted"
    rg -Fq 'case "--once"' "$REPOSITORY/Sources/ZoidCoachAgent/main.swift" || fail "installed helper lacks --once"
}

assert_runbook_shell_blocks_fail_fast() {
    awk '
        /^```sh$/ { checking=1; found=1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking=0 }
        END { if (checking || !found) exit 1 }
    ' "$REPOSITORY/docs/ZC-062-002-SIGNED-QA-RUNBOOK.md" || fail "every runbook shell block must fail fast"
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_sha "$PARENT" || fail "invalid parent SHA"
    git -C "$REPOSITORY" cat-file -e "$PARENT^{commit}" || fail "parent unavailable"
    [[ "/private/tmp/zoid-666-zc062002-test" == /private/tmp/zoid-666-zc062002-* ]] || fail "valid namespace rejected"
    [[ "$HOME/screenwatch/days" != /private/tmp/zoid-666-zc062002-* ]] || fail "real Screenwatch path accepted"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc062002-screenwatch-outage-fixture.sh" self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc062002-screenwatch-outage-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-062-002 signed preflight self-test"
    exit 0
fi

(( $# == 4 )) || fail "usage: $0 --self-test | <app> <database> <Screenwatch-root> <expected-commit>"
readonly APP="${1:A}" DATABASE="${2:A}" SCREENWATCH_ROOT="${3:A}" EXPECTED_COMMIT="$4"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
git -C "$REPOSITORY" merge-base --is-ancestor "$PARENT" "$EXPECTED_COMMIT" || fail "signed commit is not stacked on required parent"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null
assert_paths "$APP" "$DATABASE" "$SCREENWATCH_ROOT"
print -- "PASS: signed candidate, helper, database, and isolated Screenwatch identities are bound"
