#!/usr/bin/env bash
set -euo pipefail

readonly TASK_ID="qa-zc056001-locale-duration"
readonly TASK_TITLE="Review localized duration copy"
readonly ESTIMATE_MINUTES=45

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local query="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(scalar "$query")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

require_schema() {
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals; do
        assert_scalar \
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" \
            "1" \
            "production table $table"
    done
}

cleanup_owned_rows() {
    sqlite3 -batch -bail "$DATABASE" <<SQL
PRAGMA busy_timeout = 5000;
BEGIN IMMEDIATE;
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
SQL
}

seed_fixture() {
    local foreign_active timestamp started_at
    foreign_active="$(scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id != '$TASK_ID';")"
    [[ "$foreign_active" == "0" ]] || fail "another active task exists; refusing to alter it"
    cleanup_owned_rows
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    started_at="$(date -u -v-12M +%Y-%m-%dT%H:%M:%SZ)"
    sqlite3 -batch -bail "$DATABASE" <<SQL
PRAGMA busy_timeout = 5000;
BEGIN IMMEDIATE;
INSERT INTO source_tasks(
    source_id, title, priority, is_completed, updated_at, source_kind
) VALUES (
    '$TASK_ID', '$TASK_TITLE', 9, 0, '$timestamp', 'local'
);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, is_optional
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 1, 1, $ESTIMATE_MINUTES, '$timestamp', 0
);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', 'active', '$timestamp');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$started_at', NULL);
COMMIT;
SQL
    verify_fixture
    printf 'FIXTURE_TASK_ID=%s\n' "$TASK_ID"
    printf 'FIXTURE_TASK_TITLE=%s\n' "$TASK_TITLE"
    printf 'ESTIMATE_MINUTES=%s\n' "$ESTIMATE_MINUTES"
}

verify_fixture() {
    assert_scalar \
        "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND title = '$TASK_TITLE' AND source_kind = 'local' AND is_completed = 0;" \
        "1" \
        "owned local task"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID' AND is_main_objective = 1 AND estimate_minutes = $ESTIMATE_MINUTES;" \
        "1" \
        "owned locale-duration plan"
    assert_scalar \
        "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" \
        "1" \
        "active execution state"
    assert_scalar \
        "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" \
        "1" \
        "single open activity interval"
    printf 'PASS: ZC-056-001 locale-duration fixture is ready\n'
}

verify_clean() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "source cleanup"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';" "0" "plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID';" "0" "state cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "interval cleanup"
    printf 'PASS: ZC-056-001 owned fixture rows were removed\n'
}

self_test() {
    local original_database="$DATABASE"
    local temporary_database
    temporary_database="$(mktemp -t zoid-zc056001-fixture).sqlite"
    trap "rm -f -- '$temporary_database' '$temporary_database-wal' '$temporary_database-shm'" EXIT
    DATABASE="$temporary_database"
    sqlite3 -batch -bail "$DATABASE" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, source_kind TEXT NOT NULL);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, updated_at TEXT NOT NULL, is_optional INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind)
VALUES ('foreign-task', 'Preserve this task', 1, 0, '2026-07-15T00:00:00Z', 'local');
SQL
    require_schema
    seed_fixture >/dev/null
    verify_fixture >/dev/null
    cleanup_owned_rows
    verify_clean >/dev/null
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = 'foreign-task';" "1" "foreign row preservation"
    DATABASE="$original_database"
    printf 'PASS: ZC-056-001 fixture self-test preserves foreign rows\n'
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

LOCAL_DAY="${LOCAL_DAY:-$(date +%F)}"
[[ "$LOCAL_DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "--local-day must use YYYY-MM-DD"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
if [[ "$ACTION" != "self-test" ]]; then
    [[ -n "$DATABASE" ]] || fail "--database is required"
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
