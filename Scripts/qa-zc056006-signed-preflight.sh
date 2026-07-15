#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PRODUCT_CANDIDATE="86943ed7c1615caa69bee669c4d79247bff3223b"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-006-SIGNED-QA-RUNBOOK.md"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
readonly EXPECTED_APP_PID="${4:-}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    local command="$1"
    local expected="$2"
    [[ " $command " == *" $expected "* ]]
}

assert_runbook_contract() {
    grep -Fq 'FIXTURE" seed-paused --database "$DATABASE"' "$RUNBOOK" \
        || fail "runbook does not seed the paused fixture"
    grep -Fq -- '--expected-value paused' "$RUNBOOK" \
        || fail "runbook does not verify the stable paused AX value"
    grep -Fq 'trap cleanup EXIT' "$RUNBOOK" \
        || fail "runbook does not guarantee cleanup"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "$PRODUCT_CANDIDATE" || fail "valid SHA was rejected"
    ! is_full_lowercase_sha "86943ED7C1615CAA69BEE669C4D79247BFF3223B" \
        || fail "uppercase SHA was accepted"
    command_has_exact_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" \
        || fail "exact foreground argument was rejected"
    ! command_has_exact_argument "/tmp/Zoid666 --qa-open-main-extra" "--qa-open-main" \
        || fail "prefixed foreground argument was accepted"
    assert_runbook_contract
    print -- "PASS: ZC-056-006 signed preflight self-test"
    exit 0
fi

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
is_full_lowercase_sha "$EXPECTED_COMMIT" \
    || fail "expected commit must be a full lowercase SHA"
[[ "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain product candidate $PRODUCT_CANDIDATE"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$CANONICAL_APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$APP_EXECUTABLE" ]] || fail "app executable is unavailable: $APP_EXECUTABLE"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] \
    || fail "database is not the signed app's exact isolated QA database"
kill -0 "$EXPECTED_APP_PID" 2>/dev/null \
    || fail "expected app PID is not running"
lsof -Fn -a -p "$EXPECTED_APP_PID" -d txt 2>/dev/null \
    | sed -n 's/^n//p' \
    | grep -Fqx "$APP_EXECUTABLE" \
    || fail "PID is not running the exact signed app executable"
lsof -a -p "$EXPECTED_APP_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
    || fail "signed app does not hold the isolated database open"
readonly APP_COMMAND="$(ps -ww -p "$EXPECTED_APP_PID" -o command=)"
command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
    || fail "signed app was not launched through the supported foreground path"
assert_runbook_contract
print -- "APP_PID=$EXPECTED_APP_PID"
print -- "PASS: ZC-056-006 signed identity, database, foreground PID, and candidate ancestry"
