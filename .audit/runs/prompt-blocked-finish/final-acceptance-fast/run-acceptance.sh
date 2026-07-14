#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:A:h:h:h:h}"
EXPECTED_COMMIT="f28ad1087623bd308fc410f78ab6215cf1b69131"
QA_ROOT="/private/tmp/zoid-666-zc034011-fast-root"
INSTALL_ROOT="/private/tmp/zoid-666-zc034011-fast-install"
PACKAGE_APP="$ROOT/.build/app-qa/Zoid 666 QA.app"
INSTALLED_APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
APP_EXECUTABLE="ZoidCoachQA"
AGENT_EXECUTABLE="ZoidCoachAgentQA"
AGENT_LABEL="qa.ziadnasreldin.ZoidCoach.agent"
APP_COMMAND="$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE"
DB="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
TOOL_DIR="$ROOT/.build/zc034011-fast"
AX_DRIVER="$TOOL_DIR/ax-driver"
WINDOW_PROBE="$TOOL_DIR/qa-window-content-probe"
MANIFEST="$SCRIPT_DIR/ready-state.json"
EVIDENCE="$SCRIPT_DIR/evidence"
USER_DOMAIN="gui/$(id -u)"

mkdir -p "$EVIDENCE"

log() {
    print -r -- "$*" | tee -a "$EVIDENCE/runtime.log"
}

stop_app() {
    pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
    pkill -f "${INSTALLED_APP}/Contents/MacOS/${APP_EXECUTABLE}" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        if ! pgrep -x "$APP_EXECUTABLE" >/dev/null 2>&1 \
            && ! pgrep -f "${INSTALLED_APP}/Contents/MacOS/${APP_EXECUTABLE}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    print -u2 "FAIL: foreground QA app did not stop"
    return 1
}

unregister_helper() {
    if [[ -x "$APP_COMMAND" ]]; then
        "$APP_COMMAND" --qa-unregister-agent >/dev/null 2>&1 || true
    fi
    launchctl bootout "$USER_DOMAIN/$AGENT_LABEL" >/dev/null 2>&1 || true
}

cleanup() {
    set +e
    stop_app
    unregister_helper
    rm -rf "$INSTALLED_APP" "$INSTALL_ROOT" "$QA_ROOT"
    set -e
}

trap cleanup EXIT INT TERM

helper_pid() {
    local service
    service="$(launchctl print "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true)"
    awk '/pid =/{print $3; exit}' <<<"$service"
}

wait_for_app_pid() {
    local pid=""
    for _ in {1..80}; do
        pid="$(pgrep -x "$APP_EXECUTABLE" | head -1 || true)"
        [[ -n "$pid" ]] && { print -r -- "$pid"; return 0; }
        sleep 0.1
    done
    print -u2 "FAIL: foreground QA app did not launch"
    return 1
}

register_helper() {
    local label="$1"
    local output
    output="$("$APP_COMMAND" --qa-register-agent)"
    print -r -- "$output" | tee "$EVIDENCE/$label-registration.txt"
    grep -Fq "PASS: QA XPC runtime is writable and prompt timeline is available" <<<"$output"
    local pid
    pid="$(helper_pid)"
    [[ -n "$pid" ]] || { print -u2 "FAIL: helper PID unavailable after $label registration"; return 1; }
    local expected_path="$INSTALLED_APP/Contents/MacOS/$AGENT_EXECUTABLE"
    local actual_path
    actual_path="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -F "$AGENT_EXECUTABLE" | head -1 || true)"
    [[ "$actual_path" == "$expected_path" ]] || {
        print -u2 "FAIL: $label helper executable mismatch: $actual_path"
        return 1
    }
    log "$label-helper-pid=$pid"
    log "$label-helper-executable=$actual_path"
}

seed_presented_fixture() {
    python3 - "$DB" <<'PY'
import datetime
import json
import sqlite3
import sys

database = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
now_text = now.isoformat().replace("+00:00", "Z")
day = datetime.datetime.now().astimezone().date().isoformat()
actions = [
    {"kind": "return_to_active_task", "title": "Return to Ship client proposal", "role": "primary", "requiresConfirmation": False},
    {"kind": "start_work_sprint", "title": "Start a 20-minute work sprint", "role": "secondary", "requiresConfirmation": False},
    {"kind": "start_break", "title": "Take a break", "role": "secondary", "requiresConfirmation": False},
    {"kind": "reschedule_task", "title": "Reschedule Ship client proposal", "role": "destructive", "requiresConfirmation": True},
    {"kind": "mark_blocked", "title": "Mark Ship client proposal blocked", "role": "destructive", "requiresConfirmation": True},
    {"kind": "continue_intentionally", "title": "Continue intentionally", "role": "secondary", "requiresConfirmation": False},
]
envelope = json.dumps({
    "decisionKey": "qa:block:1",
    "actions": actions,
    "payload": {"taskID": "task-1", "taskTitle": "Ship client proposal"},
}, separators=(",", ":"))

connection = sqlite3.connect(database)
connection.execute("PRAGMA foreign_keys = ON")
connection.execute("BEGIN IMMEDIATE")
connection.execute("DELETE FROM prompt_response_effects")
connection.execute("DELETE FROM prompt_responses")
connection.execute("DELETE FROM prompt_episodes")
connection.execute("DELETE FROM task_mutation_steps")
connection.execute("DELETE FROM task_mutation_operations")
connection.execute("DELETE FROM task_activity_intervals")
connection.execute("DELETE FROM task_execution_states WHERE task_id IN ('task-1', 'task-2')")
connection.execute("DELETE FROM task_history WHERE task_id IN ('task-1', 'task-2')")
connection.execute("DELETE FROM daily_plan_entries WHERE day_key = ?", (day,))
connection.executemany(
    """INSERT OR REPLACE INTO source_tasks
       (source_id, title, priority, is_completed, updated_at, source_kind)
       VALUES (?, ?, ?, 0, ?, 'local')""",
    [
        ("task-1", "Ship client proposal", 9, now_text),
        ("task-2", "Prepare launch notes", 7, now_text),
    ],
)
connection.executemany(
    """INSERT INTO daily_plan_entries
       (day_key, reminder_id, rank, is_main_objective, estimate_minutes,
        estimate_is_uncertain, selection_reason, selection_score, is_optional,
        blocked_reason, deferred_until_utc, updated_at)
       VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0, NULL, NULL, ?)""",
    [
        (day, "task-1", 0, 1, 45, "Primary launch deliverable", 100, now_text),
        (day, "task-2", 1, 0, 25, "Follow-up deliverable", 80, now_text),
    ],
)
connection.execute(
    "INSERT INTO task_execution_states(task_id, state, updated_at) VALUES ('task-1', 'active', ?)",
    (now_text,),
)
connection.execute(
    "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES ('task-1', ?, NULL)",
    (now_text,),
)
connection.execute(
    """INSERT INTO prompt_episodes
       (id, decision_key, prompt_type, state, title, summary, action_token,
        payload_json, created_at_utc, expires_at_utc)
       VALUES ('qa-block-1', 'qa:block:1', 'GAMING_DRIFT', 'presented',
        'Gaming drift detected', 'Choose how to recover.', 'qa-block-token', ?, ?, NULL)""",
    (envelope, now_text),
)
connection.commit()
print(json.dumps({
    "day": day,
    "prompt": connection.execute(
        "SELECT id, state, prompt_type, json_array_length(payload_json, '$.actions') FROM prompt_episodes"
    ).fetchone(),
    "plan": connection.execute(
        "SELECT reminder_id, rank, is_main_objective, blocked_reason FROM daily_plan_entries WHERE day_key = ? ORDER BY rank",
        (day,),
    ).fetchall(),
    "execution": connection.execute(
        "SELECT task_id, state FROM task_execution_states WHERE task_id = 'task-1'"
    ).fetchone(),
    "openIntervals": connection.execute(
        "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL"
    ).fetchone()[0],
    "responses": connection.execute("SELECT COUNT(*) FROM prompt_responses").fetchone()[0],
}, sort_keys=True))
connection.close()
PY
}

prepare_presented_runtime() {
    local label="$1"
    stop_app
    unregister_helper
    python3 "$ROOT/Scripts/prepare-qa-ready-state.py" --replace "$MANIFEST" "$QA_ROOT" \
        | tee "$EVIDENCE/$label-ready-state.txt"
    register_helper "$label-migration"
    unregister_helper
    seed_presented_fixture | tee "$EVIDENCE/$label-seed.json"
    register_helper "$label-final"
}

assert_success_database() {
    local label="$1"
    python3 - "$DB" <<'PY' | tee "$EVIDENCE/$label-database.json"
import datetime
import json
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
day = datetime.datetime.now().astimezone().date().isoformat()
result = {
    "promptState": connection.execute("SELECT state FROM prompt_episodes WHERE id = 'qa-block-1'").fetchone()[0],
    "responseCount": connection.execute("SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = 'qa-block-1' AND response = 'mark_blocked' AND surface = 'dashboard'").fetchone()[0],
    "blockedReason": connection.execute("SELECT blocked_reason FROM daily_plan_entries WHERE day_key = ? AND reminder_id = 'task-1'", (day,)).fetchone()[0],
    "taskState": connection.execute("SELECT state FROM task_execution_states WHERE task_id = 'task-1'").fetchone()[0],
    "openIntervals": connection.execute("SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL").fetchone()[0],
    "mainObjective": connection.execute("SELECT reminder_id FROM daily_plan_entries WHERE day_key = ? AND is_main_objective = 1", (day,)).fetchone()[0],
}
expected = {
    "promptState": "responded",
    "responseCount": 1,
    "blockedReason": "Waiting for approval.",
    "taskState": "blocked",
    "openIntervals": 0,
    "mainObjective": "task-2",
}
print(json.dumps(result, sort_keys=True))
if result != expected:
    raise SystemExit(f"success database mismatch: expected {expected!r}")
connection.close()
PY
}

assert_unchanged_database() {
    local label="$1"
    python3 - "$DB" <<'PY' | tee "$EVIDENCE/$label-database.json"
import datetime
import json
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
day = datetime.datetime.now().astimezone().date().isoformat()
result = {
    "promptState": connection.execute("SELECT state FROM prompt_episodes WHERE id = 'qa-block-1'").fetchone()[0],
    "responseCount": connection.execute("SELECT COUNT(*) FROM prompt_responses").fetchone()[0],
    "blockedReason": connection.execute("SELECT blocked_reason FROM daily_plan_entries WHERE day_key = ? AND reminder_id = 'task-1'", (day,)).fetchone()[0],
    "taskState": connection.execute("SELECT state FROM task_execution_states WHERE task_id = 'task-1'").fetchone()[0],
    "openIntervals": connection.execute("SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL").fetchone()[0],
    "mainObjective": connection.execute("SELECT reminder_id FROM daily_plan_entries WHERE day_key = ? AND is_main_objective = 1", (day,)).fetchone()[0],
}
expected = {
    "promptState": "presented",
    "responseCount": 0,
    "blockedReason": None,
    "taskState": "active",
    "openIntervals": 1,
    "mainObjective": "task-1",
}
print(json.dumps(result, sort_keys=True))
if result != expected:
    raise SystemExit(f"helper-down database mismatch: expected {expected!r}")
connection.close()
PY
}

launch_and_wait_for_actions() {
    open "$INSTALLED_APP"
    local pid
    pid="$(wait_for_app_pid)"
    "$AX_DRIVER" "$pid" wait-count-prefix "today.prompt.qa-block-1.action." 6 12 \
        | tee -a "$EVIDENCE/runtime.log" >&2
    print -r -- "$pid"
}

preflight() {
    git -C "$ROOT" merge-base --is-ancestor "$EXPECTED_COMMIT" HEAD
    git -C "$ROOT" diff --quiet "$EXPECTED_COMMIT" -- \
        App Package.swift Sources Scripts Tests
    [[ -d "$PACKAGE_APP" ]]
    [[ -x "$AX_DRIVER" ]]
    [[ -x "$WINDOW_PROBE" ]]
    python3 -m json.tool "$MANIFEST" >/dev/null
    "$ROOT/Scripts/verify-build-identity.sh" \
        "$PACKAGE_APP/Contents/Info.plist" \
        --expected-commit "$EXPECTED_COMMIT" --require-clean \
        | tee "$EVIDENCE/package-identity.txt"
    codesign --verify --deep --strict --verbose=2 "$PACKAGE_APP"
    log "PASS: harness preflight complete"
}

preflight
if [[ "${1:-}" == "--dry-run" ]]; then
    log "DRY RUN: no install, app launch, helper registration, or runtime mutation performed"
    trap - EXIT INT TERM
    exit 0
fi

[[ "${ZOID_ACCEPT_RUNTIME_LEASE:-}" == "granted" ]] || {
    print -u2 "Set ZOID_ACCEPT_RUNTIME_LEASE=granted only while holding the serialized signed-runtime lease."
    exit 2
}

rm -rf "$INSTALL_ROOT" "$QA_ROOT"
mkdir -p "$INSTALL_ROOT"
ditto "$PACKAGE_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
register_helper "install"
open "$INSTALLED_APP"
install_app_pid="$(wait_for_app_pid)"
install_helper_pid="$(helper_pid)"
log "install-app-pid=$install_app_pid"
log "install-helper-pid=$install_helper_pid"

prepare_presented_runtime "success"
success_helper_pid="$(helper_pid)"
success_app_pid="$(launch_and_wait_for_actions)"
"$WINDOW_PROBE" "$success_app_pid" --expect-today --screenshot "$EVIDENCE/success-actions.png" \
    | tee -a "$EVIDENCE/runtime.log"
"$AX_DRIVER" "$success_app_pid" frame "today.prompt.qa-block-1.action.mark_blocked" \
    | tee "$EVIDENCE/success-mark-blocked-frame-before-scroll.txt"
"$AX_DRIVER" "$success_app_pid" scroll-visible "today.prompt.qa-block-1.action.mark_blocked" 10 \
    | tee "$EVIDENCE/success-mark-blocked-scroll.txt"
"$AX_DRIVER" "$success_app_pid" frame "today.prompt.qa-block-1.action.mark_blocked" \
    | tee "$EVIDENCE/success-mark-blocked-frame-visible.txt"
"$WINDOW_PROBE" "$success_app_pid" --expect-today --screenshot "$EVIDENCE/success-actions-scrolled.png" \
    | tee -a "$EVIDENCE/runtime.log"
"$AX_DRIVER" "$success_app_pid" click "today.prompt.qa-block-1.action.mark_blocked"
"$AX_DRIVER" "$success_app_pid" wait "today.prompt.block.suggestion.approval" 6
"$AX_DRIVER" "$success_app_pid" click "today.prompt.block.suggestion.approval"
"$AX_DRIVER" "$success_app_pid" click "today.prompt.block.confirm"
"$AX_DRIVER" "$success_app_pid" wait "today.prompt.qa-block-1.history.blocked-reason" 10 \
    | tee "$EVIDENCE/success-history.txt"
assert_success_database "success"
"$WINDOW_PROBE" "$success_app_pid" --expect-today --screenshot "$EVIDENCE/success-saved.png" \
    | tee -a "$EVIDENCE/runtime.log"

stop_app
open "$INSTALLED_APP"
app_relaunch_pid="$(wait_for_app_pid)"
"$AX_DRIVER" "$app_relaunch_pid" wait "today.prompt.qa-block-1.history.blocked-reason" 10 \
    | tee "$EVIDENCE/app-relaunch-history.txt"
[[ "$(helper_pid)" == "$success_helper_pid" ]]
assert_success_database "app-relaunch"

stop_app
unregister_helper
register_helper "helper-relaunch"
restarted_helper_pid="$(helper_pid)"
[[ "$restarted_helper_pid" != "$success_helper_pid" ]]
open "$INSTALLED_APP"
helper_relaunch_app_pid="$(wait_for_app_pid)"
"$AX_DRIVER" "$helper_relaunch_app_pid" wait "today.prompt.qa-block-1.history.blocked-reason" 10 \
    | tee "$EVIDENCE/helper-relaunch-history.txt"
assert_success_database "helper-relaunch"
"$WINDOW_PROBE" "$helper_relaunch_app_pid" --expect-today --screenshot "$EVIDENCE/helper-relaunch.png" \
    | tee -a "$EVIDENCE/runtime.log"

prepare_presented_runtime "helper-down"
failure_app_pid="$(launch_and_wait_for_actions)"
"$AX_DRIVER" "$failure_app_pid" scroll-visible "today.prompt.qa-block-1.action.mark_blocked" 10 \
    | tee "$EVIDENCE/helper-down-mark-blocked-scroll.txt"
"$AX_DRIVER" "$failure_app_pid" click "today.prompt.qa-block-1.action.mark_blocked"
"$AX_DRIVER" "$failure_app_pid" wait "today.prompt.block.suggestion.approval" 6
"$AX_DRIVER" "$failure_app_pid" click "today.prompt.block.suggestion.approval"
unregister_helper
"$AX_DRIVER" "$failure_app_pid" click "today.prompt.block.confirm"
failure_text="$($AX_DRIVER "$failure_app_pid" text "today.prompt.block.err" 10)"
print -r -- "$failure_text" | tee "$EVIDENCE/helper-down-error.txt"
grep -Fq "The blocker was not saved. The last confirmed task and plan state are still shown." <<<"$failure_text"
assert_unchanged_database "helper-down"
"$WINDOW_PROBE" "$failure_app_pid" --expect-today --screenshot "$EVIDENCE/helper-down.png" \
    | tee -a "$EVIDENCE/runtime.log"

log "PASS: ZC-034-011 signed final acceptance complete"
