#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly FIXTURE="$SCRIPT_DIR/qa-prompt-zero-actions-fixture.sh"
readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zoid-prompt-fixture.XXXXXX")"
readonly DATABASE="$TEMP_ROOT/zoid-coach.sqlite"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

sqlite3 -batch -bail "$DATABASE" <<'SQL'
PRAGMA foreign_keys = ON;
CREATE TABLE prompt_episodes (
    id TEXT PRIMARY KEY,
    decision_key TEXT NOT NULL UNIQUE,
    prompt_type TEXT NOT NULL,
    state TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    action_token TEXT NOT NULL UNIQUE,
    payload_json TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    expires_at_utc TEXT,
    resolution_origin TEXT,
    resolution_reason TEXT
);
CREATE TABLE prompt_responses (
    id TEXT PRIMARY KEY,
    prompt_id TEXT NOT NULL,
    action_token TEXT NOT NULL UNIQUE,
    response TEXT NOT NULL,
    surface TEXT NOT NULL,
    responded_at_utc TEXT NOT NULL,
    FOREIGN KEY(prompt_id) REFERENCES prompt_episodes(id)
);
CREATE TABLE prompt_response_effects (
    response_id TEXT NOT NULL,
    prompt_id TEXT NOT NULL,
    effect_type TEXT NOT NULL,
    state TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL
);
CREATE TABLE source_tasks (
    source_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    due_at TEXT,
    priority INTEGER NOT NULL DEFAULT 0,
    is_completed INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    notes TEXT,
    list_id TEXT,
    list_name TEXT,
    modified_at TEXT,
    source_hash TEXT,
    source_kind TEXT NOT NULL DEFAULT 'reminders'
);
CREATE TABLE daily_plan_entries (
    day_key TEXT NOT NULL,
    reminder_id TEXT NOT NULL,
    rank INTEGER NOT NULL,
    is_main_objective INTEGER NOT NULL,
    estimate_minutes INTEGER,
    updated_at TEXT NOT NULL,
    selection_reason TEXT,
    selection_score INTEGER,
    is_optional INTEGER NOT NULL DEFAULT 0,
    blocked_reason TEXT,
    deferred_until_utc TEXT,
    estimate_is_uncertain INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(day_key, reminder_id)
);
CREATE TABLE task_execution_states (
    task_id TEXT PRIMARY KEY,
    state TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE task_activity_intervals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT
);
CREATE UNIQUE INDEX task_activity_one_open
ON task_activity_intervals((ended_at IS NULL))
WHERE ended_at IS NULL;
SQL

"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" insert "$DATABASE"

sqlite3 -batch -bail "$DATABASE" "
UPDATE prompt_episodes SET state = 'responded' WHERE id = 'qa-zero-actions-block-1';
INSERT INTO prompt_responses(id, prompt_id, action_token, response, surface, responded_at_utc)
VALUES(
    'qa-zero-actions-response-1',
    'qa-zero-actions-block-1',
    'qa-zero-actions-response-token-1',
    'mark_blocked',
    'today',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
UPDATE task_execution_states SET state = 'blocked' WHERE task_id = 'qa-zero-actions-active';
UPDATE daily_plan_entries
SET blocked_reason = 'Waiting for approval.', is_main_objective = 0
WHERE reminder_id = 'qa-zero-actions-active';
UPDATE daily_plan_entries
SET is_main_objective = 1
WHERE reminder_id = 'qa-zero-actions-replacement';
"

"$FIXTURE" assert-resolved "$DATABASE"
"$FIXTURE" cleanup "$DATABASE"

if [[ -e "$TEMP_ROOT/should-not-exist" ]]; then
    print -u2 "FAIL: unreachable cleanup sentinel exists"
    exit 1
fi

print "PASS: zero-actions fixture schema, SQL, JSON, state assertions, and cleanup are deterministic"
print "RUNTIME SEQUENCE: prepare -> open Today and require today.prompt-inbox.empty -> insert -> Reviews -> Today"
print "RUNTIME AX: require 1 WAITING and exactly six unique today.prompt.qa-zero-actions-block-1.action.* buttons before Save Blocker"
