#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PRODUCT_CANDIDATE="2e6ee58663b5d4991d7bd7ef10e529e92bdaf34b"
readonly RUNBOOK="$REPOSITORY/docs/ZC-056-001-SIGNED-QA-RUNBOOK.md"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
readonly EXPECTED_LOCALE="${4:-}"
readonly EXPECTED_APP_PID="${5:-}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    local command="$1"
    local expected_argument="$2"
    [[ " $command " == *" $expected_argument "* ]]
}

assert_runbook_contract() {
    grep -Fq 'FIXTURE" seed --database "$DATABASE"' "$RUNBOOK" \
        || fail "runbook does not seed the namespaced fixture"
    grep -Fq -- '-AppleLocale en_US' "$RUNBOOK" \
        || fail "runbook does not launch the en-US locale phase"
    grep -Fq -- '-AppleLocale ar_EG' "$RUNBOOK" \
        || fail "runbook does not launch the Arabic locale phase"
    grep -Fq -- '--compact-estimate "$ARABIC_ESTIMATE"' "$RUNBOOK" \
        || fail "runbook does not bind the deterministic Arabic compact estimate"
    grep -Fq 'trap cleanup EXIT' "$RUNBOOK" \
        || fail "runbook does not guarantee fixture and process cleanup"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_lowercase_sha "2e6ee58663b5d4991d7bd7ef10e529e92bdaf34b" \
        || fail "valid SHA was rejected"
    ! is_full_lowercase_sha "2E6EE58663B5D4991D7BD7EF10E529E92BDAF34B" \
        || fail "uppercase SHA was accepted"
    command_has_exact_argument "/tmp/Zoid666 -AppleLocale fr_FR --qa-open-main" "-AppleLocale" \
        || fail "exact locale option was rejected"
    command_has_exact_argument "/tmp/Zoid666 -AppleLocale fr_FR --qa-open-main" "fr_FR" \
        || fail "exact locale identifier was rejected"
    ! command_has_exact_argument "/tmp/Zoid666 -AppleLocale fr_FR_extra" "fr_FR" \
        || fail "locale prefix was accepted"
    assert_runbook_contract
    print -- "PASS: ZC-056-001 signed preflight self-test"
    exit 0
fi

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
is_full_lowercase_sha "$EXPECTED_COMMIT" \
    || fail "expected commit must be a full lowercase SHA"
[[ "$EXPECTED_LOCALE" =~ '^[a-z]{2}_[A-Z]{2}$' ]] \
    || fail "expected locale must use language_REGION form"
[[ "$EXPECTED_APP_PID" == <-> ]] \
    || fail "expected app PID must be numeric"

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
    || fail "expected app PID is not running: $EXPECTED_APP_PID"
lsof -Fn -a -p "$EXPECTED_APP_PID" -d txt 2>/dev/null \
    | sed -n 's/^n//p' \
    | grep -Fqx "$APP_EXECUTABLE" \
    || fail "PID is not running the exact signed app executable"
lsof -a -p "$EXPECTED_APP_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
    || fail "signed app does not hold the exact isolated database open"

readonly APP_COMMAND="$(ps -ww -p "$EXPECTED_APP_PID" -o command=)"
command_has_exact_argument "$APP_COMMAND" "-AppleLocale" \
    || fail "signed app was not launched with an explicit locale"
command_has_exact_argument "$APP_COMMAND" "$EXPECTED_LOCALE" \
    || fail "signed app locale does not match $EXPECTED_LOCALE"
command_has_exact_argument "$APP_COMMAND" "--qa-open-main" \
    || fail "signed app was not launched through the supported QA foreground path"

assert_runbook_contract
print -- "APP_PID=$EXPECTED_APP_PID"
print -- "PASS: ZC-056-001 signed identity, QA database, foreground launch, and locale binding"
