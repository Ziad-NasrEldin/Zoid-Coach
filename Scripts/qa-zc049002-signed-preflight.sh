#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE='7ac4ea0b6cb12062fc77ff6e7588cd7a3a78ab0b'
readonly PRODUCT_COMMIT='a492acbae5641bbe41bfcdad93b8e7fb37612bdf'
readonly TOOLING_COMMIT='49b480214184988886de207460299f18212d3e61'
readonly PRODUCT_PATCH_ID='e1501b79d92e053e6239f6ca45db96fa242dc234'
readonly TOOLING_PATCH_ID='7c372bbd9f0b92e6d159f80f1102606cf3ba9292'
readonly SUSPENSION_SENTENCE='Drift detection is suspended until Screenwatch coverage is current.'

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "Usage: $0 --self-test"
    print -u2 -- "       $0 APP DATABASE EXPECTED_COMMIT [--expected-app-pid PID]"
    exit 64
}

is_sha() {
    [[ "$1" =~ '^[0-9a-f]{40}$' ]]
}

commit_scope() {
    git -C "$REPOSITORY" diff-tree --no-commit-id --name-only -r "$1" | LC_ALL=C sort
}

range_scope() {
    git -C "$REPOSITORY" diff --name-only "$CANONICAL_BASE..$1" | LC_ALL=C sort
}

patch_id() {
    git -C "$REPOSITORY" show "$1" --pretty=format: | git patch-id --stable | awk '{print $1}'
}

assert_exact() {
    [[ "$1" == "$2" ]] || fail "$3"
}

verify_lineage() {
    local expected="$1"
    is_sha "$expected" || fail "expected commit must be a full lowercase SHA"
    git -C "$REPOSITORY" cat-file -e "$expected^{commit}" 2>/dev/null || fail "expected commit is unavailable"
    assert_exact "$(git -C "$REPOSITORY" rev-parse "$PRODUCT_COMMIT^")" "$CANONICAL_BASE" "product commit is not directly based on canonical"
    assert_exact "$(git -C "$REPOSITORY" rev-parse "$TOOLING_COMMIT^")" "$PRODUCT_COMMIT" "tooling commit is not directly based on product"
    assert_exact "$(git -C "$REPOSITORY" rev-parse "$expected^")" "$TOOLING_COMMIT" "signed candidate is not directly based on tooling"
    assert_exact "$(git -C "$REPOSITORY" rev-list --count "$CANONICAL_BASE..$expected")" 3 "signed candidate must contain exactly three commits"
    assert_exact "$(patch_id "$PRODUCT_COMMIT")" "$PRODUCT_PATCH_ID" "reviewed product patch identity changed"
    assert_exact "$(patch_id "$TOOLING_COMMIT")" "$TOOLING_PATCH_ID" "reviewed tooling patch identity changed"

    local product_scope tooling_scope head_scope total_scope
    product_scope=$'Sources/ZoidCoachApp/BehaviorEvidenceState.swift\nTests/ZoidCoachAppTests/BehaviorEvidenceStateTests.swift'
    tooling_scope=$'Scripts/qa-zc049002-coverage-drift-suspension-ax-probe.swift\nScripts/qa-zc049002-coverage-drift-suspension-fixture.sh\ndocs/ZC-049-002-SIGNED-QA-RUNBOOK.md'
    head_scope=$'Scripts/qa-zc049002-signed-preflight.sh\ndocs/ZC-049-002-SIGNED-QA-RUNBOOK.md'
    total_scope=$'Scripts/qa-zc049002-coverage-drift-suspension-ax-probe.swift\nScripts/qa-zc049002-coverage-drift-suspension-fixture.sh\nScripts/qa-zc049002-signed-preflight.sh\nSources/ZoidCoachApp/BehaviorEvidenceState.swift\nTests/ZoidCoachAppTests/BehaviorEvidenceStateTests.swift\ndocs/ZC-049-002-SIGNED-QA-RUNBOOK.md'
    assert_exact "$(commit_scope "$PRODUCT_COMMIT")" "$product_scope" "product commit scope changed"
    assert_exact "$(commit_scope "$TOOLING_COMMIT")" "$tooling_scope" "tooling commit scope changed"
    assert_exact "$(commit_scope "$expected")" "$head_scope" "lineage commit contains unrelated files"
    assert_exact "$(range_scope "$expected")" "$total_scope" "candidate range contains unrelated files"

    local changed
    changed="$(range_scope "$expected")"
    if print -r -- "$changed" | grep -Eq '(^|/)(CHANGELOG\.md|scenario-registry|scenario_registry|scenario-tracker|ScenarioTracker|\.lavish)(/|$)'; then
        fail "candidate touches a protected generated, registry, tracker, or Lavish path"
    fi
}

verify_contract() {
    local expected="$1" source tests fixture probe runbook
    source="$(git -C "$REPOSITORY" show "${expected}:Sources/ZoidCoachApp/BehaviorEvidenceState.swift")"
    tests="$(git -C "$REPOSITORY" show "${expected}:Tests/ZoidCoachAppTests/BehaviorEvidenceStateTests.swift")"
    fixture="$(git -C "$REPOSITORY" show "${expected}:Scripts/qa-zc049002-coverage-drift-suspension-fixture.sh")"
    probe="$(git -C "$REPOSITORY" show "${expected}:Scripts/qa-zc049002-coverage-drift-suspension-ax-probe.swift")"
    runbook="$(git -C "$REPOSITORY" show "${expected}:docs/ZC-049-002-SIGNED-QA-RUNBOOK.md")"
    print -r -- "$source" | grep -Fq 'coverage.isLimited' || fail "product no longer conditions the explanation on limited coverage"
    print -r -- "$source" | grep -Fq "$SUSPENSION_SENTENCE" || fail "product suspension explanation is missing"
    print -r -- "$tests" | grep -Fq '#expect(state.coverageDetail.contains("Drift detection is suspended' || fail "limited regression assertion is missing"
    print -r -- "$tests" | grep -Fq '#expect(!state.coverageDetail.contains("Drift detection is suspended"))' || fail "current-coverage negative assertion is missing"
    print -r -- "$fixture" | grep -Fq 'set-limited' || fail "limited fixture phase is missing"
    print -r -- "$fixture" | grep -Fq 'set-current' || fail "current fixture phase is missing"
    print -r -- "$fixture" | grep -Fq 'exact payload restoration' || fail "exact fixture restore assertion is missing"
    print -r -- "$probe" | grep -Fq 'today.behavior-evidence.coverage' || fail "coverage AX identifier is missing"
    print -r -- "$probe" | grep -Fq "$SUSPENSION_SENTENCE" || fail "AX suspension contract is missing"
    print -r -- "$runbook" | grep -Fq -- '--phase limited' || fail "limited signed runbook phase is missing"
    print -r -- "$runbook" | grep -Fq -- '--phase current' || fail "current signed runbook phase is missing"
}

self_test() {
    is_sha "$CANONICAL_BASE" || fail "canonical SHA contract failed"
    ! is_sha deadbeef || fail "short SHA was accepted"
    verify_lineage "$(git -C "$REPOSITORY" rev-parse HEAD)"
    verify_contract "$(git -C "$REPOSITORY" rev-parse HEAD)"
    "$SCRIPT_DIR/qa-zc049002-coverage-drift-suspension-fixture.sh" self-test
    swift "$SCRIPT_DIR/qa-zc049002-coverage-drift-suspension-ax-probe.swift" --self-test
    print -- "PASS: ZC-049-002 signed preflight self-test"
}

if [[ "${1:-}" == --self-test ]]; then
    (( $# == 1 )) || usage
    self_test
    exit 0
fi

(( $# >= 3 )) || usage
APP="${1:A}"
DATABASE="${2:A}"
EXPECTED_COMMIT="$3"
shift 3
EXPECTED_APP_PID=''
while (( $# > 0 )); do
    case "$1" in
        --expected-app-pid)
            (( $# >= 2 )) || fail "--expected-app-pid requires a PID"
            EXPECTED_APP_PID="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

verify_lineage "$EXPECTED_COMMIT"
verify_contract "$EXPECTED_COMMIT"
assert_exact "$(git -C "$REPOSITORY" rev-parse HEAD)" "$EXPECTED_COMMIT" "checkout does not match expected signed commit"
[[ -d "$APP" ]] || fail "app bundle does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "isolated QA database does not exist: $DATABASE"
[[ "$DATABASE" != "$HOME/Library/Application Support/Zoid Coach/"* ]] || fail "normal user database is forbidden"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$APP" --expected-commit "$EXPECTED_COMMIT"

APP_EXECUTABLE="$APP/Contents/MacOS/Zoid Coach"
[[ -x "$APP_EXECUTABLE" ]] || fail "signed app executable is unavailable"
[[ "$EXPECTED_APP_PID" =~ '^[0-9]+$' ]] || fail "--expected-app-pid is required for runtime binding"
kill -0 "$EXPECTED_APP_PID" 2>/dev/null || fail "expected app PID is not running"
lsof -Fn -a -p "$EXPECTED_APP_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE" \
    || fail "PID is not running the exact signed app executable"
lsof -a -p "$EXPECTED_APP_PID" "$DATABASE" >/dev/null 2>&1 \
    || fail "signed app process does not hold the exact isolated QA database open"

print -- "APP_PID=$EXPECTED_APP_PID"
print -- "DATABASE=$DATABASE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-049-002 signed runtime identity is bound"
