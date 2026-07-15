#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly PRODUCT_CANDIDATE="6fa4bcb029a13eb951806a2d5a4f073d2f11c58e"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
shift $(( $# < 3 ? $# : 3 ))
EXPECTED_APP_PID=""
REQUIRE_QA_OPEN_MAIN=0

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

is_full_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

command_has_exact_argument() {
    [[ " $1 " == *" $2 "* ]]
}

assert_static_contract() {
    local presentation="$REPOSITORY/Sources/ZoidCoachApp/UnplannedDayReviewPresentation.swift"
    local dashboard="$REPOSITORY/Sources/ZoidCoachApp/Views/DashboardView.swift"
    local tests="$REPOSITORY/Tests/ZoidCoachAppTests/UnplannedDayReviewPresentationTests.swift"
    grep -Fq 'snapshot?.planningStatus?.mode == .unplanned' "$presentation" || fail "explicit unplanned eligibility is missing"
    grep -Fq 'snapshot?.activeTask == nil' "$presentation" || fail "inactive-day eligibility is missing"
    grep -Fq 'let isActionEnabled = true' "$presentation" || fail "command is not explicitly enabled"
    grep -Fq 'case openDailyReview' "$presentation" || fail "review command identity is missing"
    grep -Fq 'observed behavior and tracked task outcomes' "$presentation" || fail "factual review copy is missing"
    grep -Fq 'without inventing planned commitments' "$presentation" || fail "invented-plan exclusion is missing"
    grep -Fq 'model.selectedSection = .reviews' "$dashboard" || fail "existing Reviews route is missing"
    grep -Fq 'accessibilityIdentifier("today.unplanned-day-review")' "$dashboard" || fail "unplanned review accessibility surface is missing"
    grep -Fq 'accessibilityIdentifier("today.end-workday")' "$dashboard" || fail "command accessibility identity is missing"
    for boundary in planning invitation snoozed dismissed; do
        grep -Fq "snapshot(mode: .$boundary)" "$tests" || fail "$boundary exclusion test is missing"
    done
    grep -Fq 'snapshot(mode: .unplanned, hasActiveTask: true)' "$tests" || fail "active-unplanned precedence test is missing"
    grep -Fq 'UnplannedDayReviewPresentation(snapshot: nil)' "$tests" || fail "nil snapshot exclusion test is missing"
}

assert_runbook_contract() {
    local runbook="$REPOSITORY/docs/ZC-010-007-SIGNED-QA-RUNBOOK.md"
    grep -Fq 'ordinary app relaunch' "$runbook" || fail "ordinary relaunch acceptance is missing"
    grep -Fq 'byte-for-byte' "$runbook" || fail "byte restoration acceptance is missing"
    grep -Fq 'planned invitation snoozed dismissed nil active-unplanned' "$runbook" || fail "boundary matrix is incomplete"
    grep -Fq 'Accessibility permission' "$runbook" || fail "accessibility prerequisite is missing"
    awk '
        /^```sh$/ { checking=1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking=0 }
        END { if (checking) exit 1 }
    ' "$runbook" || fail "every shell block must start in fail-fast mode"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$PRODUCT_CANDIDATE" || fail "valid product candidate rejected"
    ! is_full_sha "${PRODUCT_CANDIDATE[1,39]}" || fail "abbreviated SHA accepted"
    command_has_exact_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "exact argument rejected"
    ! command_has_exact_argument "/tmp/Zoid666 --qa-open-main-extra" "--qa-open-main" || fail "prefixed argument accepted"
    assert_static_contract
    assert_runbook_contract
    print -- "PASS: ZC-010-007 signed preflight self-test"
    exit 0
fi

while (( $# > 0 )); do
    case "$1" in
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        --require-qa-open-main)
            REQUIRE_QA_OPEN_MAIN=1
            shift
            ;;
        *) fail "unsupported option: $1" ;;
    esac
done

[[ -d "$APP" ]] || fail "signed app is unavailable: $APP"
[[ -f "$DATABASE" ]] || fail "isolated database is unavailable: $DATABASE"
is_full_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ -z "$EXPECTED_APP_PID" || "$EXPECTED_APP_PID" == <-> ]] || fail "expected app PID must be numeric"
git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain ZC-010-007 product candidate"
assert_static_contract
assert_runbook_contract

readonly CANONICAL_APP="${APP:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$CANONICAL_APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$EXECUTABLE" ]] || fail "installed executable is unavailable"
[[ "${DATABASE:A}" == "$EXPECTED_DATABASE" ]] || fail "database is not the signed app's isolated QA database"

resolve_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

APP_PID="$(resolve_pid)" || fail "app is not running from the expected signed bundle"
[[ -z "$EXPECTED_APP_PID" || "$APP_PID" == "$EXPECTED_APP_PID" ]] || fail "foreground app PID changed"
if (( REQUIRE_QA_OPEN_MAIN )); then
    APP_COMMAND="$(ps -ww -p "$APP_PID" -o command=)"
    command_has_exact_argument "$APP_COMMAND" "--qa-open-main" || fail "app was not launched with --qa-open-main"
fi
lsof -a -p "$APP_PID" "$EXPECTED_DATABASE" >/dev/null 2>&1 \
    || fail "signed app does not hold the exact isolated database open"

print -- "APP_PID=$APP_PID"
print -- "DATABASE=$EXPECTED_DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-010-007 signed identity and isolated runtime are bound"
