#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SCRIPT_PATH="${0:A}"
readonly TASK_ID="qa-zc044004-manual-workday-task"
readonly TASK_TITLE="QA ZC-044-004 manual workday task"
readonly DAY_KEY="${ZOID_666_QA_ZC044004_DAY:-$(date '+%Y-%m-%d')}"
readonly BACKUP_KEY="qa.zc044004.original-policy-version"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|assert-prepared|assert-manual|assert-active|assert-ended|assert-relaunch|inject-start-stale|assert-start-stale|restore-ready|inject-end-stale|assert-end-stale|restore-active|cleanup|self-test> [database]"
    exit 2
}

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local sql="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(scalar "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

require_table() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$1';" "1" "$1 table"
}

require_column() {
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('$1') WHERE name = '$2';" "1" "$1.$2 column"
}

validate_schema() {
    local table
    for table in settings policy_versions source_tasks daily_plan_entries task_execution_states task_activity_intervals task_pause_events; do
        require_table "$table"
    done
    require_column settings value_json
    require_column settings policy_version
    require_column policy_versions payload_json
    require_column source_tasks source_kind
    require_column daily_plan_entries is_optional
    require_column task_execution_states state
    require_column task_activity_intervals ended_at
    require_column task_pause_events reason
    assert_scalar "SELECT json_valid('{\"schedule\":{}}');" "1" "SQLite JSON support"
}

assert_prepared() {
    validate_schema
    assert_scalar "SELECT COUNT(*) FROM settings WHERE key = '$BACKUP_KEY' AND json_valid(value_json) AND json_type(value_json, '$.version') = 'integer';" "1" "policy backup"
    assert_scalar "SELECT json_extract(value_json, '$.schedule.workdayControlMode') FROM settings WHERE key = 'user_policy';" "scheduled" "scheduled baseline"
    assert_ready_state
}

assert_ready_state() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND title = '$TASK_TITLE' AND source_kind = 'local' AND is_completed = 0;" "1" "owned local task"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID' AND rank = 0 AND is_main_objective = 1 AND is_optional = 0;" "1" "owned daily plan row"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'ready';" "1" "ready task state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "no open task interval"
}

assert_manual() {
    validate_schema
    assert_scalar "SELECT json_extract(value_json, '$.schedule.workdayControlMode') FROM settings WHERE key = 'user_policy';" "manual" "saved manual policy"
    assert_scalar "SELECT CASE WHEN json_array_length(json_extract(value_json, '$.schedule.workWindows')) > 0 THEN 1 ELSE 0 END FROM settings WHERE key = 'user_policy';" "1" "planning windows preserved"
    assert_scalar "SELECT CASE WHEN policy_version > json_extract((SELECT value_json FROM settings WHERE key = '$BACKUP_KEY'), '$.version') THEN 1 ELSE 0 END FROM settings WHERE key = 'user_policy';" "1" "versioned policy save"
}

assert_active() {
    assert_manual
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "active task state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "1" "one open task interval"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND resumed_at IS NULL;" "0" "no open pause"
}

assert_ended() {
    assert_manual
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'paused';" "1" "ended task state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "closed task interval"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND reason = 'endingWorkday' AND resumed_at IS NULL;" "1" "persisted end-workday pause"
}

inject_start_stale() {
    assert_manual
    assert_ready_state
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
UPDATE task_execution_states SET state = 'paused', updated_at = '$timestamp' WHERE task_id = '$TASK_ID';
INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at)
VALUES('$TASK_ID', 'doneForNow', '$timestamp', NULL);
COMMIT;
SQL
    assert_start_stale
}

assert_start_stale() {
    assert_manual
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'paused';" "1" "stale Start source state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "stale Start did not open an interval"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND reason = 'doneForNow' AND resumed_at IS NULL;" "1" "stale Start pause preserved"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND reason = 'endingWorkday';" "0" "stale Start did not end the workday"
}

restore_ready() {
    assert_start_stale
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" "BEGIN IMMEDIATE; DELETE FROM task_pause_events WHERE task_id = '$TASK_ID'; UPDATE task_execution_states SET state = 'ready', updated_at = '$timestamp' WHERE task_id = '$TASK_ID'; COMMIT;"
    assert_ready_state
    assert_manual
}

inject_end_stale() {
    assert_active
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
UPDATE task_activity_intervals SET ended_at = '$timestamp' WHERE task_id = '$TASK_ID' AND ended_at IS NULL;
UPDATE task_execution_states SET state = 'paused', updated_at = '$timestamp' WHERE task_id = '$TASK_ID';
INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at)
VALUES('$TASK_ID', 'doneForNow', '$timestamp', NULL);
COMMIT;
SQL
    assert_end_stale
}

assert_end_stale() {
    assert_manual
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'paused';" "1" "stale End source state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "stale End kept the interval closed"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND reason = 'doneForNow' AND resumed_at IS NULL;" "1" "stale End pause preserved"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID' AND reason = 'endingWorkday';" "0" "stale End did not apply an end-workday mutation"
}

restore_active() {
    assert_end_stale
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM task_pause_events WHERE task_id = '$TASK_ID';
UPDATE task_execution_states SET state = 'active', updated_at = '$timestamp' WHERE task_id = '$TASK_ID';
INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES('$TASK_ID', '$timestamp', NULL);
COMMIT;
SQL
    assert_active
}

prepare() {
    validate_schema
    assert_scalar "SELECT COUNT(*) FROM settings WHERE key = '$BACKUP_KEY';" "0" "unused fixture namespace"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "task ownership collision"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID';" "0" "plan ownership collision"
    local original_version next_version timestamp
    original_version="$(scalar "SELECT policy_version FROM settings WHERE key = 'user_policy';")"
    [[ "$original_version" == <-> ]] || fail "active user policy is unavailable"
    next_version="$(scalar "SELECT COALESCE(MAX(version), 0) + 1 FROM policy_versions WHERE policy_type = 'user_policy';")"
    assert_scalar "SELECT COUNT(*) FROM settings WHERE key = 'user_policy' AND json_valid(value_json);" "1" "active policy payload"
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO settings(key, value_json, policy_version, updated_at_utc)
VALUES('$BACKUP_KEY', json_object('version', $original_version), $original_version, '$timestamp');
UPDATE policy_versions SET is_active = 0 WHERE policy_type = 'user_policy';
INSERT INTO policy_versions(policy_type, version, payload_json, created_at_utc, is_active)
SELECT 'user_policy', $next_version, json_set(value_json, '$.schedule.workdayControlMode', 'scheduled'), '$timestamp', 1
FROM settings WHERE key = 'user_policy';
UPDATE settings SET value_json = json_set(value_json, '$.schedule.workdayControlMode', 'scheduled'), policy_version = $next_version, updated_at_utc = '$timestamp'
WHERE key = 'user_policy';
INSERT INTO source_tasks(source_id, title, due_at, priority, is_completed, updated_at, notes, list_id, list_name, modified_at, source_hash, source_kind)
VALUES('$TASK_ID', '$TASK_TITLE', NULL, 9, 0, '$timestamp', 'ZC-044-004 signed QA fixture', NULL, 'Zoid 666 QA', '$timestamp', '$TASK_ID', 'local');
INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, estimate_is_uncertain)
VALUES('$DAY_KEY', '$TASK_ID', 0, 1, 30, '$timestamp', 'ZC-044-004 signed QA fixture', 100, 0, NULL, NULL, 0);
DELETE FROM task_pause_events WHERE task_id = '$TASK_ID';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES('$TASK_ID', 'ready', '$timestamp')
ON CONFLICT(task_id) DO UPDATE SET state = excluded.state, updated_at = excluded.updated_at;
COMMIT;
SQL
    assert_prepared
}

cleanup() {
    validate_schema
    local original_version timestamp
    original_version="$(scalar "SELECT json_extract(value_json, '$.version') FROM settings WHERE key = '$BACKUP_KEY';")"
    [[ "$original_version" == <-> ]] || fail "fixture policy backup is unavailable"
    assert_scalar "SELECT COUNT(*) FROM policy_versions WHERE policy_type = 'user_policy' AND version = $original_version AND json_valid(payload_json);" "1" "original policy payload"
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM task_pause_events WHERE task_id = '$TASK_ID';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
UPDATE policy_versions SET is_active = CASE WHEN version = $original_version THEN 1 ELSE 0 END
WHERE policy_type = 'user_policy';
UPDATE settings SET value_json = (SELECT payload_json FROM policy_versions WHERE policy_type = 'user_policy' AND version = $original_version), policy_version = $original_version, updated_at_utc = '$timestamp'
WHERE key = 'user_policy';
DELETE FROM settings WHERE key = '$BACKUP_KEY';
COMMIT;
SQL
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "fixture task cleanup"
    assert_scalar "SELECT policy_version FROM settings WHERE key = 'user_policy';" "$original_version" "original policy restoration"
    assert_scalar "SELECT COUNT(*) FROM settings WHERE key = '$BACKUP_KEY';" "0" "fixture backup cleanup"
    assert_scalar "SELECT COUNT(*) FROM policy_versions WHERE policy_type = 'user_policy' AND version = $original_version AND is_active = 1;" "1" "original active policy restoration"
    assert_scalar "SELECT CASE WHEN json((SELECT value_json FROM settings WHERE key = 'user_policy')) = json((SELECT payload_json FROM policy_versions WHERE policy_type = 'user_policy' AND version = $original_version)) THEN 1 ELSE 0 END;" "1" "original policy payload restoration"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';" "0" "fixture plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID';" "0" "fixture execution cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "fixture interval cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$TASK_ID';" "0" "fixture pause cleanup"
}

self_test() {
    local database timestamp
    typeset -g SELF_TEST_ROOT
    SELF_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zc044004-fixture.XXXXXX")"
    database="$SELF_TEST_ROOT/fixture.sqlite"
    timestamp="2026-07-14T08:00:00Z"
    trap '[[ -z "${SELF_TEST_ROOT:-}" ]] || rm -rf -- "$SELF_TEST_ROOT"' EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE settings(key TEXT PRIMARY KEY, value_json TEXT NOT NULL, policy_version INTEGER NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE policy_versions(policy_type TEXT NOT NULL, version INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, is_active INTEGER NOT NULL, PRIMARY KEY(policy_type, version));
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, due_at TEXT, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, modified_at TEXT, source_hash TEXT, source_kind TEXT NOT NULL DEFAULT 'reminders');
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, updated_at TEXT NOT NULL, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE task_pause_events(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, reason TEXT NOT NULL, paused_at TEXT NOT NULL, resumed_at TEXT);
INSERT INTO policy_versions VALUES('user_policy', 1, '{"schedule":{"workdayControlMode":"scheduled","workWindows":[{"weekdays":[2],"start":{"hour":9,"minute":0},"end":{"hour":17,"minute":0}}]}}', '$timestamp', 1);
INSERT INTO settings VALUES('user_policy', '{"schedule":{"workdayControlMode":"scheduled","workWindows":[{"weekdays":[2],"start":{"hour":9,"minute":0},"end":{"hour":17,"minute":0}}]}}', 1, '$timestamp');
SQL
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" prepare "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-prepared "$database"
    sqlite3 -batch "$database" "INSERT INTO policy_versions SELECT 'user_policy', 3, json_set(value_json, '$.schedule.workdayControlMode', 'manual'), '$timestamp', 1 FROM settings WHERE key = 'user_policy'; UPDATE policy_versions SET is_active = CASE WHEN version = 3 THEN 1 ELSE 0 END WHERE policy_type = 'user_policy'; UPDATE settings SET value_json = json_set(value_json, '$.schedule.workdayControlMode', 'manual'), policy_version = 3 WHERE key = 'user_policy';"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-manual "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" inject-start-stale "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-start-stale "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" restore-ready "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'active'; INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES('$TASK_ID', '$timestamp', NULL);"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-active "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" inject-end-stale "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-end-stale "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" restore-active "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'paused'; UPDATE task_activity_intervals SET ended_at = '2026-07-14T09:00:00Z' WHERE task_id = '$TASK_ID'; INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES('$TASK_ID', 'endingWorkday', '2026-07-14T09:00:00Z', NULL);"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-ended "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" assert-relaunch "$database"
    ZOID_666_QA_ZC044004_DAY="$DAY_KEY" "$SCRIPT_PATH" cleanup "$database"
    rm -rf -- "$SELF_TEST_ROOT"
    SELF_TEST_ROOT=""
    print -- "PASS: ZC-044-004 fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then
    self_test
    exit 0
fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

case "$COMMAND" in
    prepare) prepare ;;
    assert-prepared) assert_prepared ;;
    assert-manual) assert_manual ;;
    assert-active) assert_active ;;
    assert-ended|assert-relaunch) assert_ended ;;
    inject-start-stale) inject_start_stale ;;
    assert-start-stale) assert_start_stale ;;
    restore-ready) restore_ready ;;
    inject-end-stale) inject_end_stale ;;
    assert-end-stale) assert_end_stale ;;
    restore-active) restore_active ;;
    cleanup) cleanup ;;
    *) usage ;;
esac
