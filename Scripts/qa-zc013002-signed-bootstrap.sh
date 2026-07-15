#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly INSTALLER="$SCRIPT_DIR/install-signed-qa-runtime.sh"
readonly READY_STATE="$SCRIPT_DIR/prepare-qa-ready-state.py"
readonly READY_MANIFEST="$SCRIPT_DIR/fixtures/qa-ready-state.example.json"
readonly PREFLIGHT="$SCRIPT_DIR/qa-zc013002-signed-preflight.sh"
readonly FIXTURE="$SCRIPT_DIR/qa-zc013002-coaching-status-fixture.sh"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
is_safe_root() { [[ "$1" == /private/tmp/zoid-zc013002-* ]]; }

stop_exact_app() {
    local executable_name="$1" executable="$2" candidate
    for candidate in ${(f)$(pgrep -x "$executable_name" 2>/dev/null || true)}; do
        if [[ "$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)" == "$executable" ]]; then
            kill "$candidate"
            for _ in {1..40}; do kill -0 "$candidate" 2>/dev/null || break; sleep 0.1; done
            kill -0 "$candidate" 2>/dev/null && fail "exact QA app did not stop"
        fi
    done
}

wait_for_policy_store() {
    local database="$1"
    for _ in {1..80}; do
        if [[ -f "$database" ]] \
            && [[ "$(sqlite3 "$database" "SELECT count(*) FROM policy_versions WHERE policy_type='user_policy' AND is_active=1 AND json_valid(payload_json);" 2>/dev/null || true)" == 1 ]] \
            && [[ "$(sqlite3 "$database" "SELECT count(*) FROM settings WHERE key='user_policy' AND json_valid(value_json);" 2>/dev/null || true)" == 1 ]]; then
            return 0
        fi
        sleep 0.2
    done
    fail "ready-state helper did not materialize a valid policy store"
}

wait_for_app_database() {
    local executable_name="$1" executable="$2" database="$3" candidate open_databases
    for _ in {1..80}; do
        for candidate in ${(f)$(pgrep -x "$executable_name" 2>/dev/null || true)}; do
            [[ "$(lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)" == "$executable" ]] || continue
            open_databases="$(lsof -Fn -a -p "$candidate" 2>/dev/null | sed -n 's/^n//p' | grep -E '/zoid-coach\.sqlite$' | LC_ALL=C sort -u || true)"
            [[ "$open_databases" == "$database" ]] && { print -- "$candidate"; return 0; }
            [[ -z "$open_databases" ]] || fail "ready app opened a database outside the isolated root"
        done
        sleep 0.2
    done
    fail "ready app did not open the exact isolated database"
}

wait_for_quiescence() {
    local database="$1"
    for _ in {1..40}; do
        lsof -t "$database" >/dev/null 2>&1 || return 0
        sleep 0.2
    done
    fail "isolated database did not become quiescent"
}

self_test() {
    local source="$SCRIPT_DIR/qa-zc013002-signed-bootstrap.sh" runbook="$REPOSITORY/docs/ZC-013-002-SIGNED-QA-RUNBOOK.md"
    local ready_line register_line open_line live_line unregister_line root_line
    is_safe_root /private/tmp/zoid-zc013002-selftest || fail "safe QA root was rejected"
    ! is_safe_root /private/tmp/unrelated || fail "unrelated root was accepted"
    ready_line="$(grep -n '^"\$READY_STATE" "\$READY_MANIFEST" "\$QA_ROOT" --replace$' "$source" | cut -d: -f1)"
    register_line="$(grep -n '^REGISTRATION_OUTPUT="\$("\$APP_EXECUTABLE" --qa-register-agent)"$' "$source" | cut -d: -f1)"
    open_line="$(grep -n '^open -na "\$APP" --args --qa-open-main$' "$source" | cut -d: -f1)"
    live_line="$(grep -n '^"\$PREFLIGHT" --ready-app "\$APP" "\$DATABASE" "\$EXPECTED_COMMIT" "\$PID"$' "$source" | cut -d: -f1)"
    unregister_line="$(grep -n '^"\$APP_EXECUTABLE" --qa-unregister-agent$' "$source" | tail -n 1 | cut -d: -f1)"
    root_line="$(grep -n '^"\$FIXTURE" assert-ready-root "\$QA_ROOT" "\$DATABASE" "\$APP_EXECUTABLE_NAME" "\$AGENT_EXECUTABLE_NAME" "\$AGENT_LABEL"$' "$source" | cut -d: -f1)"
    [[ "$ready_line" == <-> && "$register_line" == <-> && "$open_line" == <-> && "$live_line" == <-> && "$unregister_line" == <-> && "$root_line" == <-> ]] \
        || fail "bootstrap readiness markers are missing"
    (( ready_line < register_line && register_line < open_line && open_line < live_line && live_line < unregister_line && unregister_line < root_line )) \
        || fail "bootstrap readiness order regressed"
    grep -Fq '"$BOOTSTRAP" "$EXPECTED_SIGNED_COMMIT" "$QA_ROOT" "$INSTALL_ROOT"' "$runbook" \
        || fail "runbook does not invoke the bound ready-state bootstrap"
    print -- "PASS: ZC-013-002 bootstrap path safety and readiness order self-test"
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit 0; fi
[[ $# == 3 ]] || fail "usage: $0 EXPECTED_COMMIT QA_ROOT INSTALL_ROOT"
readonly EXPECTED_COMMIT="$1" QA_ROOT="${2:A}" INSTALL_ROOT="${3:A}"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
is_safe_root "$QA_ROOT" && is_safe_root "$INSTALL_ROOT" || fail "runtime and install roots must remain in the ZC-013-002 namespace"
[[ "$(git -C "$REPOSITORY" rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] || fail "HEAD differs from expected commit"
[[ -z "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]] || fail "candidate worktree is not clean"

ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" "$INSTALLER"

readonly DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :qa:appDisplayName' "$REPOSITORY/App/PackageIdentities.plist")"
readonly APP="$INSTALL_ROOT/$DISPLAY_NAME E2E.app"
readonly APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
readonly APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
readonly -a AGENT_PLISTS=("$APP"/Contents/Library/LaunchAgents/*.plist(N))
[[ ${#AGENT_PLISTS[@]} == 1 ]] || fail "signed app must contain exactly one QA LaunchAgent plist"
readonly AGENT_PLIST="${AGENT_PLISTS[1]}"
readonly AGENT_LABEL="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
readonly AGENT_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :qa:agentExecutableName' "$REPOSITORY/App/PackageIdentities.plist")"
readonly DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"

"$APP_EXECUTABLE" --qa-unregister-agent >/dev/null 2>&1 || true
stop_exact_app "$APP_EXECUTABLE_NAME" "$APP_EXECUTABLE"
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
REGISTRATION_OUTPUT="$("$APP_EXECUTABLE" --qa-register-agent)"
[[ "$REGISTRATION_OUTPUT" == *"PASS: QA XPC runtime is writable and prompt timeline is available"* ]] \
    || fail "ready-state helper registration did not prove a writable policy boundary"
wait_for_policy_store "$DATABASE"
open -na "$APP" --args --qa-open-main
readonly PID="$(wait_for_app_database "$APP_EXECUTABLE_NAME" "$APP_EXECUTABLE" "$DATABASE")"
"$PREFLIGHT" --ready-app "$APP" "$DATABASE" "$EXPECTED_COMMIT" "$PID"
"$APP_EXECUTABLE" --qa-unregister-agent
stop_exact_app "$APP_EXECUTABLE_NAME" "$APP_EXECUTABLE"
wait_for_quiescence "$DATABASE"
"$FIXTURE" assert-ready-root "$QA_ROOT" "$DATABASE" "$APP_EXECUTABLE_NAME" "$AGENT_EXECUTABLE_NAME" "$AGENT_LABEL"

print -- "PASS: ZC-013-002 signed ready-state bootstrap completed"
print -- "app=$APP"
print -- "database=$DATABASE"
print -- "app_executable=$APP_EXECUTABLE_NAME"
print -- "agent_executable=$AGENT_EXECUTABLE_NAME"
print -- "agent_label=$AGENT_LABEL"
