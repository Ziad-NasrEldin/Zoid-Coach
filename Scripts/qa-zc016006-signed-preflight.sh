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

assert_runbook() {
    local runbook="$REPOSITORY/docs/ZC-016-006-SIGNED-QA-RUNBOOK.md"
    /usr/bin/grep -Fq 'Acquire exclusive QA runtime ownership before this journey.' "$runbook" \
        || fail "runtime ownership gate is missing"
    /usr/bin/awk '
        /^```sh$/ { checking = 1; next }
        checking && /^[[:space:]]*$/ { next }
        checking { if ($0 != "set -euo pipefail") exit 1; checking = 0 }
        END { if (checking) exit 1 }
    ' "$runbook" || fail "every runbook shell block must fail fast"
}

if [[ "$APP" == "--self-test" ]]; then
    is_full_sha "$CANONICAL_BASE" || fail "canonical base is not a full SHA"
    ! is_full_sha "b73a1c1" || fail "abbreviated SHA was accepted"
    assert_runbook
    "$SCRIPT_DIR/qa-zc016006-single-active-everywhere-fixture.sh" self-test
    swift "$SCRIPT_DIR/qa-zc016006-single-active-everywhere-ax-probe.swift" --self-test
    print -- "PASS: ZC-016-006 signed preflight self-test"
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

matching_app_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' \
                | grep -Fqx "$APP_EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

readonly APP_PID="$(matching_app_pid)" || fail "exact app process is unavailable"
readonly SERVICE="$(launchctl print "gui/$(id -u)/$AGENT_LABEL")" \
    || fail "packaged helper service is unavailable"
readonly HELPER_PID="$(awk '/pid =/{print $3; exit}' <<<"$SERVICE")"
[[ "$HELPER_PID" == <-> ]] || fail "helper PID is unavailable"
lsof -a -p "$HELPER_PID" "$DATABASE" >/dev/null 2>&1 \
    || fail "helper does not own the isolated database"

print -- "APP_PID=$APP_PID"
print -- "HELPER_PID=$HELPER_PID"
print -- "DATABASE=$DATABASE"
print -- "PASS: ZC-016-006 signed identity and isolated runtime are bound"
