#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANDIDATE="ce8f8d9c00f100dae55595a1ac995592ec381ed0"
readonly PROBE="$SCRIPT_DIR/qa-zc048010-diagnostic-package-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-zc048010-diagnostic-package-fixture.sh"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"
readonly EXPECTED_COMMIT="${3:-}"
readonly EVIDENCE_ROOT="${4:-}"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
is_external_path() {
    local candidate="${1:A}"
    [[ "$candidate" != "$REPOSITORY" && "$candidate" != "$REPOSITORY"/* ]]
}
assert_runbook_order() {
    local runbook="$REPOSITORY/docs/ZC-048-010-SIGNED-QA-RUNBOOK.md"
    local preview cancel prepare save inspect existing retry finder cleanup
    preview="$(grep -nF -- '--phase preview' "$runbook" | head -n1 | cut -d: -f1)"
    cancel="$(grep -nF -- '--phase cancel' "$runbook" | head -n1 | cut -d: -f1)"
    prepare="$(grep -nF '"$FIXTURE" prepare "$DATABASE"' "$runbook" | head -n1 | cut -d: -f1)"
    save="$(grep -nF -- '--phase save' "$runbook" | head -n1 | cut -d: -f1)"
    inspect="$(grep -nF '"$FIXTURE" assert-package "$DATABASE" "$PACKAGE"' "$runbook" | head -n1 | cut -d: -f1)"
    existing="$(grep -nF 'Existing-destination rejection' "$runbook" | head -n1 | cut -d: -f1)"
    retry="$(grep -nF 'Fresh retry' "$runbook" | head -n1 | cut -d: -f1)"
    finder="$(grep -nF -- '--phase finder' "$runbook" | head -n1 | cut -d: -f1)"
    cleanup="$(grep -nF '"$FIXTURE" cleanup "$DATABASE"' "$runbook" | tail -n1 | cut -d: -f1)"
    [[ "$preview" == <-> && "$cancel" == <-> && "$prepare" == <-> && "$save" == <-> \
        && "$inspect" == <-> && "$existing" == <-> && "$retry" == <-> && "$finder" == <-> && "$cleanup" == <-> \
        && preview -lt cancel && cancel -lt prepare && prepare -lt save && save -lt inspect \
        && inspect -lt existing && existing -lt retry && retry -lt finder && finder -lt cleanup ]] \
        || fail "runbook order must preserve preview, cancel, private fixture, export, inspection, rejection, retry, Finder, and cleanup"
}

if [[ "$APP" == "--self-test" ]]; then
    is_sha "$CANDIDATE" || fail "candidate SHA rejected"
    ! is_sha "${CANDIDATE:u}" || fail "uppercase SHA accepted"
    is_external_path "/private/tmp/zoid-zc048010-evidence" || fail "external evidence root rejected"
    ! is_external_path "$REPOSITORY/.audit/zc048010" || fail "repository evidence root accepted"
    assert_runbook_order
    "$FIXTURE" self-test >/dev/null
    "$PROBE" --self-test >/dev/null
    print -- "PASS: ZC-048-010 signed preflight self-test"
    exit 0
fi

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "database is unavailable: $DATABASE"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ -n "$EVIDENCE_ROOT" ]] || fail "external evidence root is required"
is_external_path "$EVIDENCE_ROOT" || fail "evidence root must remain outside the repository"

readonly CANONICAL_APP="${APP:A}"
readonly CANONICAL_DATABASE="${DATABASE:A}"
readonly CANONICAL_EVIDENCE="${EVIDENCE_ROOT:A}"
readonly INFO_PLIST="$CANONICAL_APP/Contents/Info.plist"
readonly AGENT_PLISTS=("$CANONICAL_APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"

git -C "$REPOSITORY" merge-base --is-ancestor "$CANDIDATE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain ZC-048-010 candidate $CANDIDATE"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" "$CANONICAL_APP" \
    --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$CANONICAL_APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly APP_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$INFO_PLIST")"
readonly AGENT_ROOT="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_PROGRAM="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE="$CANONICAL_APP/$AGENT_PROGRAM"
readonly EXPECTED_DATABASE="${QA_ROOT:A}/Application Support/Zoid 666/zoid-coach.sqlite"
[[ -x "$APP_EXECUTABLE" && -x "$AGENT_EXECUTABLE" ]] || fail "installed executables are unavailable"
[[ "$APP_ROOT" == "$QA_ROOT" && "$AGENT_ROOT" == "$QA_ROOT" ]] || fail "app and helper QA roots differ"
[[ "$CANONICAL_DATABASE" == "$EXPECTED_DATABASE" ]] || fail "database does not match embedded QA root"

matching_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}
readonly APP_PID="$(matching_pid)" || fail "installed app process is unavailable"
readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null)" || fail "helper service unavailable"
readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "helper PID unavailable"
lsof -Fn -a -p "$HELPER_PID" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$AGENT_EXECUTABLE" \
    || fail "helper executable mismatch"
lsof -a -p "$HELPER_PID" "$CANONICAL_DATABASE" >/dev/null 2>&1 \
    || fail "helper does not hold the exact database open"
mkdir -p "$CANONICAL_EVIDENCE"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "QA_ROOT=$QA_ROOT"
print -- "DATABASE=$CANONICAL_DATABASE"
print -- "EVIDENCE_ROOT=$CANONICAL_EVIDENCE"
print -- "BUILD_COMMIT=$EXPECTED_COMMIT"
print -- "PASS: ZC-048-010 signed runtime identity is bound"
