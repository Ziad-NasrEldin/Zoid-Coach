#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="a002610ae3d8db3f1e88cfd8463a4ce103531e83"
readonly PRODUCT_CANDIDATE="65fa67324db313281fe2db0562a97930aec1a93c"
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

committed_blob() {
    git -C "$1" show "$2:$3"
}

assert_static_contract() {
    local commit="$1"
    local presentation dashboard tests ax_probe fixture
    presentation="$(committed_blob "$REPOSITORY" "$commit" "Sources/ZoidCoachApp/UnplannedDayReviewPresentation.swift")" \
        || fail "cannot read committed presentation contract"
    dashboard="$(committed_blob "$REPOSITORY" "$commit" "Sources/ZoidCoachApp/Views/DashboardView.swift")" \
        || fail "cannot read committed dashboard contract"
    tests="$(committed_blob "$REPOSITORY" "$commit" "Tests/ZoidCoachAppTests/UnplannedDayReviewPresentationTests.swift")" \
        || fail "cannot read committed presentation tests"
    ax_probe="$(committed_blob "$REPOSITORY" "$commit" "Scripts/qa-zc010007-unplanned-review-ax-probe.swift")" \
        || fail "cannot read committed accessibility probe"
    fixture="$(committed_blob "$REPOSITORY" "$commit" "Scripts/qa-zc010007-unplanned-review-fixture.sh")" \
        || fail "cannot read committed snapshot fixture"
    grep -Fq 'snapshot?.planningStatus?.mode == .unplanned' <<< "$presentation" || fail "explicit unplanned eligibility is missing"
    grep -Fq 'snapshot?.activeTask == nil' <<< "$presentation" || fail "inactive-day eligibility is missing"
    grep -Fq 'let isActionEnabled = true' <<< "$presentation" || fail "command is not explicitly enabled"
    grep -Fq 'case openDailyReview' <<< "$presentation" || fail "review command identity is missing"
    grep -Fq 'observed behavior and tracked task outcomes' <<< "$presentation" || fail "factual review copy is missing"
    grep -Fq 'without inventing planned commitments' <<< "$presentation" || fail "invented-plan exclusion is missing"
    grep -Fq 'model.selectedSection = .reviews' <<< "$dashboard" || fail "existing Reviews route is missing"
    grep -Fq 'accessibilityIdentifier("today.unplanned-day-review")' <<< "$dashboard" || fail "unplanned review accessibility surface is missing"
    grep -Fq 'accessibilityIdentifier("today.end-workday")' <<< "$dashboard" || fail "command accessibility identity is missing"
    grep -Fq 'accessibilityIdentifier("today.snapshot.ready")' <<< "$dashboard" || fail "rendered snapshot readiness identity is missing"
    for boundary in planning invitation snoozed dismissed; do
        grep -Fq "snapshot(mode: .$boundary)" <<< "$tests" || fail "$boundary exclusion test is missing"
    done
    grep -Fq 'snapshot(mode: .unplanned, hasActiveTask: true)' <<< "$tests" || fail "active-unplanned precedence test is missing"
    grep -Fq 'UnplannedDayReviewPresentation(snapshot: nil)' <<< "$tests" || fail "nil snapshot exclusion test is missing"
    grep -Fq 'renderedSnapshotIsReady(nodes.map(\.identifier))' <<< "$ax_probe" || fail "absence probe is not bound to rendered snapshot readiness"
    grep -Fq 'privacyLeak(in: nodes.map(\.searchableText))' <<< "$ax_probe" || fail "accessibility privacy assertion is missing"
    grep -Fq 'privacyLeak(in: ["prefix \(sentinel) suffix"]) == sentinel' <<< "$ax_probe" || fail "privacy negative self-test is missing"
    grep -Fq "'$.coverage', json_object(" <<< "$fixture" || fail "privacy sentinels do not use a decoded snapshot field"
    grep -Fq 'actual="$(scalar "$1")" || fail' <<< "$fixture" || fail "SQLite query failure propagation is missing"
    grep -Fq '_self-test-sqlite-failure' <<< "$fixture" || fail "SQLite failure negative self-test is missing"
    grep -Fq 'assert_helper_stopped_before_mutation' <<< "$fixture" || fail "fixture does not require helper-off mutation isolation"
    grep -Fq 'simulated active helper refresh overwrites and invalidates private sentinels' <<< "$fixture" \
        || fail "active-helper overwrite negative self-test is missing"
    ! grep -Fq '$.qaPrivateWindowTitle' <<< "$fixture" || fail "unknown private title field remains"
    ! grep -Fq '$.qaPrivateURL' <<< "$fixture" || fail "unknown private URL field remains"
}

assert_runbook_contract() {
    local commit="$1"
    local runbook
    runbook="$(committed_blob "$REPOSITORY" "$commit" "docs/ZC-010-007-SIGNED-QA-RUNBOOK.md")" \
        || fail "cannot read committed signed QA runbook"
    grep -Fq 'ordinary app relaunch' <<< "$runbook" || fail "ordinary relaunch acceptance is missing"
    grep -Fq 'byte-for-byte' <<< "$runbook" || fail "byte restoration acceptance is missing"
    grep -Fq 'planned invitation snoozed dismissed nil active-unplanned' <<< "$runbook" || fail "boundary matrix is incomplete"
    grep -Fq 'Accessibility permission' <<< "$runbook" || fail "accessibility prerequisite is missing"
    grep -Fq 'APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")"' <<< "$runbook" \
        || fail "runbook does not bind the installed QA bundle identifier"
    grep -Fq 'tell application id \"$APP_BUNDLE_ID\" to quit' <<< "$runbook" \
        || fail "runbook does not quit the bound QA application"
    ! grep -Fq 'com.zoidcoach.app' <<< "$runbook" \
        || fail "runbook still targets the unrelated hard-coded bundle identifier"
    grep -Fq 'stop_exact_qa_app() {' <<< "$runbook" \
        || fail "runbook exact QA foreground replacement helper is missing"
    grep -Fq 'READY_STATE="$REPO/Scripts/prepare-qa-ready-state.py"' <<< "$runbook" \
        || fail "runbook supported post-onboarding fixture is missing"
    grep -Fq '"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace' <<< "$runbook" \
        || fail "runbook does not establish the post-onboarding Today surface"
    grep -Fq '! launchctl print "gui/$(id -u)/qa.ziadnasreldin.ZoidCoach.agent"' <<< "$runbook" \
        || fail "runbook does not prove the exact QA helper is unregistered before fixture mutation"
    awk '
        /"\$APP_EXECUTABLE" --qa-register-agent/ { registered=1 }
        registered && /"\$APP_EXECUTABLE" --qa-unregister-agent/ { unregistered=1 }
        unregistered && /! pgrep -x ZoidCoachAgentQA/ { helper_exited=1 }
        /"\$FIXTURE" prepare/ { if (!(registered && unregistered && helper_exited)) exit 1; prepared=1 }
        END { if (!prepared) exit 1 }
    ' <<< "$runbook" || fail "runbook does not prove helper exit before baseline backup"
    awk '
        /^[[:space:]]*$/ { next }
        /open "\$APP" --args --qa-open-main/ {
            opens += 1
            if (previous !~ /stop_exact_qa_app/) exit 1
        }
        { previous = $0 }
        END { if (opens != 5) exit 1 }
    ' <<< "$runbook" || fail "every foreground open must replace the exact QA app process"
    awk '
        /^```sh$/ { checking=1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking=0 }
        END { if (checking) exit 1 }
    ' <<< "$runbook" || fail "every shell block must start in fail-fast mode"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$CANONICAL_BASE" || fail "valid canonical base rejected"
    is_full_sha "$PRODUCT_CANDIDATE" || fail "valid product candidate rejected"
    ! is_full_sha "${PRODUCT_CANDIDATE[1,39]}" || fail "abbreviated SHA accepted"
    command_has_exact_argument "/tmp/Zoid666 --qa-open-main" "--qa-open-main" || fail "exact argument rejected"
    ! command_has_exact_argument "/tmp/Zoid666 --qa-open-main-extra" "--qa-open-main" || fail "prefixed argument accepted"
    self_test_commit=""
    self_test_commit="$(git -C "$REPOSITORY" rev-parse HEAD)" || fail "cannot resolve self-test commit"
    assert_static_contract "$self_test_commit"
    assert_runbook_contract "$self_test_commit"
    root="$(mktemp -d /private/tmp/zoid-zc010007-preflight.XXXXXX)"
    trap 'rm -rf -- "$root"' EXIT
    git -C "$root" init -q
    git -C "$root" config user.name "ZC-010-007 Self Test"
    git -C "$root" config user.email "zc010007-self-test@example.invalid"
    print -r -- "committed contract" > "$root/contract.txt"
    git -C "$root" add contract.txt
    git -C "$root" commit -qm "fixture"
    fixture_commit=""
    fixture_commit="$(git -C "$root" rev-parse HEAD)" || fail "cannot resolve fixture commit"
    print -r -- "untrusted working copy" > "$root/contract.txt"
    [[ "$(committed_blob "$root" "$fixture_commit" contract.txt)" == "committed contract" ]] \
        || fail "committed blob lookup trusted working-copy content"
    rm -rf -- "$root"
    trap - EXIT
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
git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain the current canonical base"
git -C "$REPOSITORY" merge-base --is-ancestor "$PRODUCT_CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain ZC-010-007 product candidate"
assert_static_contract "$EXPECTED_COMMIT"
assert_runbook_contract "$EXPECTED_COMMIT"

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
