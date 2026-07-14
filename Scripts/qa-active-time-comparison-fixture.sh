#!/usr/bin/env bash
set -euo pipefail

readonly TASK_ID="qa-zc024008-active-task"
readonly APP_PREFIX="qa-zc024008-"
readonly EXPECTED_ALIGNED_MINUTES=5

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
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

require_schema() {
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records; do
        [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';")" == "1" ]] \
            || fail "production table is unavailable: $table"
    done
}

cleanup_owned_rows() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
DELETE FROM behavior_records WHERE app_name LIKE '$APP_PREFIX%';
COMMIT;
SQL
}

find_free_base_epoch() {
    local candidate shift occupied
    candidate="$(date +%s)"
    for shift in {0..30}; do
        candidate=$((candidate - (shift == 0 ? 0 : 1)))
        occupied="$(scalar "SELECT COUNT(*) FROM behavior_records WHERE epoch IN ($((candidate - 840)), $((candidate - 300)), $((candidate - 240)), $((candidate - 180)), $((candidate - 120)), $((candidate - 60)), $candidate);")"
        if [[ "$occupied" == "0" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    fail "could not find seven unowned observation epochs near the current time"
}

seed_fixture() {
    cleanup_owned_rows
    local foreign_open_count base_epoch started_epoch timestamp
    foreign_open_count="$(scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id != '$TASK_ID';")"
    [[ "$foreign_open_count" == "0" ]] || fail "another active task exists; refusing to alter it"
    base_epoch="$(find_free_base_epoch)"
    started_epoch=$((base_epoch - 840))
    timestamp="$(date -u -r "$base_epoch" +%Y-%m-%dT%H:%M:%SZ)"

    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(
    source_id, title, notes, list_id, list_name, due_at, priority,
    is_completed, modified_at, source_hash, updated_at, source_kind
) VALUES (
    '$TASK_ID', 'Verify elapsed versus aligned time', 'ZC-024-008 verifier fixture',
    'qa-zc024008-list', 'QA ZC-024-008', NULL, 9, 0,
    '$timestamp', 'qa-zc024008-source-hash', '$timestamp', 'reminders'
);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes,
    estimate_is_uncertain, selection_reason, selection_score, is_optional,
    blocked_reason, deferred_until_utc, updated_at
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 1, 1, 30, 0,
    'ZC-024-008 signed verifier', 100, 0, NULL, NULL, '$timestamp'
);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', 'active', '$timestamp');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$started_epoch" +%Y-%m-%dT%H:%M:%SZ)', NULL);
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
) VALUES
    ('$LOCAL_DAY', $started_epoch, 'qa-start', '${APP_PREFIX}unaligned-start', '', '', 0, NULL, '$timestamp', 'distracting', 0),
    ('$LOCAL_DAY', $((base_epoch - 300)), 'qa-work-1', '${APP_PREFIX}work-1', '', '', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 240)), 'qa-work-2', '${APP_PREFIX}work-2', '', '', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 180)), 'qa-work-3', '${APP_PREFIX}work-3', '', '', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 120)), 'qa-work-4', '${APP_PREFIX}work-4', '', '', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 60)), 'qa-work-5', '${APP_PREFIX}work-5', '', '', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $base_epoch, 'qa-end', '${APP_PREFIX}unaligned-end', '', '', 0, NULL, '$timestamp', 'distracting', 0);
COMMIT;
SQL

    verify_fixture
    printf 'FIXTURE_TASK_ID=%s\n' "$TASK_ID"
    printf 'MINIMUM_ELAPSED_MINUTES=14\n'
    printf 'EXPECTED_ALIGNED_MINUTES=%s\n' "$EXPECTED_ALIGNED_MINUTES"
}

verify_fixture() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND source_kind = 'reminders';" "1" "namespaced source task"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID';" "1" "namespaced plan entry"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "active execution state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "1" "open active interval"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name LIKE '$APP_PREFIX%';" "7" "namespaced observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name LIKE '$APP_PREFIX%' AND classification = 'work';" "5" "five aligned work intervals"
    printf 'PASS: ZC-024-008 fixture rows are ready\n'
}

verify_clean() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "source-task cleanup"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';" "0" "plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID';" "0" "execution cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "interval cleanup"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE app_name LIKE '$APP_PREFIX%';" "0" "observation cleanup"
    printf 'PASS: only ZC-024-008 owned fixture rows were removed\n'
}

self_test() {
    local original_database="$DATABASE" temporary_database
    temporary_database="$(mktemp -t zoid-zc024008-fixture).sqlite"
    trap "rm -f -- '$temporary_database' '$temporary_database-wal' '$temporary_database-shm'" EXIT
    DATABASE="$temporary_database"
    sqlite3 -batch "$DATABASE" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, due_at TEXT, priority INTEGER NOT NULL, is_completed INTEGER NOT NULL, modified_at TEXT, source_hash TEXT, updated_at TEXT NOT NULL, source_kind TEXT NOT NULL);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES ('foreign-task', 'Preserve me', 0, 0, '2026-07-14T00:00:00Z', 'reminders');
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at, classification, classification_policy_version) VALUES ('2026-07-14', 1, 'foreign', 'foreign-app', '', '', 0, '2026-07-14T00:00:00Z', 'work', 0);
SQL
    require_schema
    seed_fixture >/dev/null
    verify_fixture >/dev/null
    cleanup_owned_rows
    verify_clean >/dev/null
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = 'foreign-task';" "1" "foreign source row preservation"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE app_name = 'foreign-app';" "1" "foreign behavior row preservation"
    DATABASE="$original_database"
    printf 'PASS: temporary production-schema fixture self-test preserved foreign rows\n'
}

ACTION="${1:-}"
shift || true
DATABASE=""
LOCAL_DAY=""
while (( $# > 0 )); do
    case "$1" in
        --database) DATABASE="${2:-}"; shift 2 ;;
        --local-day) LOCAL_DAY="${2:-}"; shift 2 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

[[ "$ACTION" == "self-test" || -n "$DATABASE" ]] || fail "--database is required"
LOCAL_DAY="${LOCAL_DAY:-$(date +%F)}"
[[ "$LOCAL_DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "--local-day must use YYYY-MM-DD"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

if [[ "$ACTION" != "self-test" ]]; then
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    require_schema
fi

case "$ACTION" in
    seed) seed_fixture ;;
    verify) verify_fixture ;;
    cleanup) cleanup_owned_rows; verify_clean ;;
    verify-clean) verify_clean ;;
    self-test) self_test ;;
    *) fail "usage: $0 {seed|verify|cleanup|verify-clean|self-test} [--database PATH] [--local-day YYYY-MM-DD]" ;;
esac
