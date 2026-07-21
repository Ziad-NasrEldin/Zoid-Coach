#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly FIXTURE="$SCRIPT_DIR/qa-zc016003-dashboard-prompt-start-fixture.sh"
readonly TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zoid-zc016003-fixture.XXXXXX")"
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
    responded_at_utc TEXT NOT NULL
);
CREATE TABLE prompt_response_effects (
    response_id TEXT PRIMARY KEY,
    prompt_id TEXT NOT NULL,
    effect_type TEXT NOT NULL,
    state TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    updated_at_utc TEXT NOT NULL
);
CREATE TABLE source_tasks (
    source_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    is_completed INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
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
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at)
VALUES('qa-ready-task', 'QA Ready Task', 9, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES('qa-ready-task', 'ready', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
SQL

"$FIXTURE" insert "$DATABASE"
"$FIXTURE" assert-waiting "$DATABASE"

sqlite3 -batch -bail "$DATABASE" <<'SQL'
UPDATE prompt_episodes
SET state = 'responded'
WHERE id = 'qa-zc016003-start-prompt';
INSERT INTO prompt_responses(id, prompt_id, action_token, response, surface, responded_at_utc)
VALUES(
    'qa-zc016003-response',
    'qa-zc016003-start-prompt',
    'qa-zc016003-response-token',
    'start_recommended_task',
    'dashboard',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
INSERT INTO prompt_response_effects(response_id, prompt_id, effect_type, state, created_at_utc, updated_at_utc)
VALUES(
    'qa-zc016003-response',
    'qa-zc016003-start-prompt',
    'coaching_task_start',
    'applied',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
);
UPDATE task_execution_states
SET state = 'active', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = 'qa-ready-task';
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES('qa-ready-task', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), NULL);
SQL

"$FIXTURE" assert-started "$DATABASE"
"$FIXTURE" cleanup "$DATABASE"

print "PASS: ZC-016-003 canonical prompt seed, task binding, exactly-once assertions, and cleanup are deterministic"
