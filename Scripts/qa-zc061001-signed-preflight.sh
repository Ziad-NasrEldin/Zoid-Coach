#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PRODUCT_BASE="9119754"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_lowercase_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

assert_runbook_shell_blocks_fail_fast() {
    awk '
        /^```sh$/ { checking = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking) exit 1 }
    ' "$REPOSITORY/docs/ZC-061-001-SIGNED-QA-RUNBOOK.md" \
        || fail "every runbook shell block must start with set -euo pipefail"
}

if [[ "${1:-}" == "--self-test" ]]; then
    is_full_lowercase_sha "0123456789abcdef0123456789abcdef01234567" || fail "valid SHA rejected"
    ! is_full_lowercase_sha "0123456" || fail "abbreviated SHA accepted"
    assert_runbook_shell_blocks_fail_fast
    "$SCRIPT_DIR/qa-zc061001-technical-task-fixture.sh" --self-test >/dev/null
    swift "$SCRIPT_DIR/qa-zc061001-technical-task-ax-probe.swift" --self-test >/dev/null
    print -- "PASS: ZC-061-001 signed preflight self-test"
    exit 0
fi

(( $# == 3 )) || fail "usage: $0 --self-test | <app> <database> <expected-commit>"
readonly APP="${1:A}"
readonly DATABASE="${2:A}"
readonly EXPECTED_COMMIT="$3"
[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database does not exist: $DATABASE"
is_full_lowercase_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_BASE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain ZC-061-001 product base"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null
readonly EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
readonly EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
[[ -x "$EXECUTABLE" ]] || fail "signed executable is unavailable"
pid="$(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null | head -n 1 || true)"
[[ "$pid" == <-> ]] || fail "signed app is not running"
lsof -Fn -a -p "$pid" -d txt | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE" \
    || fail "running app does not match signed executable"
print -- "APP_PID=$pid"
print -- "DATABASE=$DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: signed candidate identity and isolated database are bound"
