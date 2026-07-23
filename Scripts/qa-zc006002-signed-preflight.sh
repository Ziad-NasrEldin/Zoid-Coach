#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly CANONICAL_BASE="b73a1c1c489eb02017d8609eab7a056296065819"
readonly APP="${1:-}"
readonly EXPECTED_COMMIT="${2:-}"

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

assert_runbook() {
    local runbook="$REPOSITORY/docs/ZC-006-002-SIGNED-QA-RUNBOOK.md"
    /usr/bin/grep -Fq 'Do not run the signed journey without an orchestration runtime lease.' "$runbook" \
        || fail "runbook runtime lease gate is missing"
    /usr/bin/awk '
        /^```sh$/ { checking = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking) exit 1 }
    ' "$runbook" || fail "every runbook shell block must fail fast"
    /usr/bin/grep -Fq 'BOOTSTRAP_READY=0' "$runbook" \
        || fail "runbook bounded bootstrap readiness gate is missing"
    /usr/bin/grep -Fq "name IN ('settings','processing_checkpoints','prompt_episodes','policy_versions')" "$runbook" \
        || fail "runbook required-schema gate is missing"
    /usr/bin/grep -Fq 'BEGIN IMMEDIATE; UPDATE settings SET updated_at_utc=updated_at_utc WHERE 0; ROLLBACK;' "$runbook" \
        || fail "runbook write-transaction gate is missing"
    /usr/bin/grep -Fq 'PRAGMA wal_checkpoint(PASSIVE);' "$runbook" \
        || fail "runbook quiescent-checkpoint gate is missing"
    /usr/bin/awk '
        /"\$APP_EXECUTABLE" --qa-register-agent/ && !registered { registered = NR }
        /"\$APP_EXECUTABLE" --qa-unregister-agent/ && registered && !unregistered { unregistered = NR }
        /fixture_output=.*"\$FIXTURE" configure/ { configured = NR }
        END { exit !(registered && unregistered && configured && registered < unregistered && unregistered < configured) }
    ' "$runbook" || fail "helper bootstrap must finish before fixture mutation"
    /usr/bin/grep -Fq 'Foreground open must not reuse a background-schedule process.' "$runbook" \
        || fail "runbook exact foreground replacement gate is missing"
    /usr/bin/grep -Fq 'swift "$PROBE" --pid "$APP_PID" --phase work-unplanned' "$runbook" \
        || fail "runbook visible Work Unplanned action gate is missing"
    /usr/bin/grep -Fq '"$FIXTURE" assert-work-unplanned "$DATABASE" "$EXPECTED_LOCAL_DAY" "$PROMPT_ID"' "$runbook" \
        || fail "runbook durable Work Unplanned assertion is missing"
    /usr/bin/grep -Fq 'swift "$PROBE" --pid "$APP_PID" --phase unplanned --prompt-id "$PROMPT_ID"' "$runbook" \
        || fail "runbook ordinary-relaunch UI assertion is missing"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$CANONICAL_BASE" || fail "canonical base is not a full SHA"
    ! is_full_sha "b73a1c1" || fail "abbreviated SHA was accepted"
    command_has_exact_argument '/tmp/ZoidCoachQA --qa-open-main' '--qa-open-main' \
        || fail "exact foreground argument was rejected"
    ! command_has_exact_argument '/tmp/ZoidCoachQA --qa-open-main-extra' '--qa-open-main' \
        || fail "prefixed foreground argument was accepted"
    assert_runbook
    "$SCRIPT_DIR/qa-zc006002-missed-invitation-fixture.sh" self-test
    swift "$SCRIPT_DIR/qa-zc006002-missed-invitation-ax-probe.swift" --self-test
    print -- "PASS: ZC-006-002 signed preflight self-test"
    exit 0
fi

[[ -d "$APP" ]] || fail "signed app does not exist"
is_full_sha "$EXPECTED_COMMIT" || fail "expected signed commit must be a full lowercase SHA"
git -C "$REPOSITORY" merge-base --is-ancestor "$CANONICAL_BASE" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain the canonical base"
readonly TOOLING_COMMIT="$(git -C "$REPOSITORY" log -1 --format=%H -- "$0")"
is_full_sha "$TOOLING_COMMIT" || fail "tooling commit cannot be resolved"
git -C "$REPOSITORY" merge-base --is-ancestor "$TOOLING_COMMIT" "$EXPECTED_COMMIT" \
    || fail "signed commit does not contain this verifier tooling"
ZOID_COACH_PACKAGE_MODE=qa "$SCRIPT_DIR/verify-package.sh" \
    "$APP" --expected-commit "$EXPECTED_COMMIT" --require-clean >/dev/null

readonly INFO_PLIST="$APP/Contents/Info.plist"
readonly QA_ROOT="$(plutil -extract ZoidCoachQARunRoot raw -o - "$INFO_PLIST")"
readonly DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
readonly APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
(( ${#AGENT_PLISTS} == 1 )) || fail "signed bundle must contain exactly one LaunchAgent"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
[[ -x "$APP_EXECUTABLE" && -f "$DATABASE" ]] || fail "isolated signed runtime is incomplete"
typeset -a MATCHING_APP_PIDS
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true); do
    candidate_executable="$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    candidate_command="$(ps -ww -p "$candidate" -o command=)"
    if [[ "$candidate_executable" == "$APP_EXECUTABLE" ]] \
        && command_has_exact_argument "$candidate_command" '--qa-open-main'; then
        MATCHING_APP_PIDS+=("$candidate")
    fi
done
(( ${#MATCHING_APP_PIDS} == 1 )) || fail "exact foreground app process is unavailable or ambiguous"
readonly APP_PID="${MATCHING_APP_PIDS[1]}"
readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL")"
readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "helper PID is unavailable"
lsof -a -p "$HELPER_PID" "$DATABASE" >/dev/null 2>&1 \
    || fail "helper does not own the isolated database"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=$DATABASE"
print -- "PASS: ZC-006-002 signed identity and isolated runtime are bound"
