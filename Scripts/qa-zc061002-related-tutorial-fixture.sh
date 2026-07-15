#!/bin/zsh
set -euo pipefail

readonly TASK_ID="qa-zc061002-technical-task"
readonly TASK_TITLE="QA ZC-061-002 technical task"
readonly GENERAL_TASK_ID="qa-zc061002-general-boundary"
readonly GENERAL_TASK_TITLE="QA ZC-061-002 general boundary"
readonly TIME_LABEL_PREFIX="qa-zc061002-"
readonly WINDOW_TITLE="Swift concurrency tutorial - YouTube"
readonly PUBLIC_URL="https://www.youtube.com/tutorials/swift-concurrency"

fail() {
    print -u2 -- "FAIL: $*"
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
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records today_snapshots; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table production table"
    done
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('source_tasks') WHERE name = 'declared_context';" "1" "source_tasks.declared_context column"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('behavior_records') WHERE name IN ('window_title', 'url', 'classification');" "3" "behavior contextual evidence columns"
}

write_restore_state() {
    [[ -n "$STATE_FILE" ]] || fail "--state-file is required for prepare"
    [[ -d "${STATE_FILE:h}" ]] || fail "restore-state parent directory does not exist: ${STATE_FILE:h}"
    [[ ! -e "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail "restore-state path is already occupied: $STATE_FILE"
    umask 077
    {
        print -- "BEGIN IMMEDIATE;"
        print -- "DELETE FROM today_snapshots WHERE day_key = '$LOCAL_DAY';"
        sqlite3 -batch -noheader "$DATABASE" "SELECT 'INSERT INTO today_snapshots(day_key, payload, updated_at) VALUES (' || quote(day_key) || ', ' || quote(payload) || ', ' || quote(updated_at) || ');' FROM today_snapshots WHERE day_key = '$LOCAL_DAY';"
        print -- "COMMIT;"
    } > "$STATE_FILE"
    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail "could not create private restore state"
    chmod 600 "$STATE_FILE"
}

restore_snapshot() {
    [[ -n "$STATE_FILE" && -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] \
        || fail "private restore state is unavailable: $STATE_FILE"
    sqlite3 -batch "$DATABASE" < "$STATE_FILE"
    rm -f -- "$STATE_FILE"
}

assert_namespace_unused() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "unused source-task namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "unused plan namespace"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "unused execution namespace"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "unused interval namespace"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';" "0" "unused behavior namespace"
}

find_free_base_epoch() {
    local candidate shift occupied
    candidate="$(date +%s)"
    for shift in {0..60}; do
        occupied="$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND epoch IN ($((candidate - 240)), $((candidate - 180)), $((candidate - 120)), $((candidate - 60)), $candidate);")"
        if [[ "$occupied" == "0" ]]; then
            print -- "$candidate"
            return 0
        fi
        candidate=$((candidate - 1))
    done
    fail "could not reserve five current-day observation epochs"
}

prepare_fixture() {
    require_schema
    assert_namespace_unused
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no foreign active interval"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE state = 'active';" "0" "no foreign active task state"
    write_restore_state

    local base_epoch started_epoch local_midnight_epoch timestamp
    base_epoch="$(find_free_base_epoch)"
    started_epoch=$((base_epoch - 360))
    local_midnight_epoch="$(date -j -f '%Y-%m-%d %H:%M:%S' "$LOCAL_DAY 00:00:00" +%s)"
    (( started_epoch >= local_midnight_epoch )) || fail "current local day is too young for a six-minute overlap fixture"
    timestamp="$(date -u -r "$base_epoch" '+%Y-%m-%dT%H:%M:%SZ')"

    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(
    source_id, title, notes, list_id, list_name, due_at, priority,
    is_completed, modified_at, source_hash, updated_at, source_kind, declared_context
) VALUES
    ('$TASK_ID', '$TASK_TITLE', 'Public tutorial overlap QA fixture', 'qa-zc061002', 'Zoid 666 Local QA', NULL, 9, 0, '$timestamp', 'qa-zc061002-technical-hash', '$timestamp', 'local', 'technical'),
    ('$GENERAL_TASK_ID', '$GENERAL_TASK_TITLE', 'Legacy general boundary QA fixture', 'qa-zc061002', 'Zoid 666 Local QA', NULL, 0, 0, '$timestamp', 'qa-zc061002-general-hash', '$timestamp', 'local', NULL);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes,
    estimate_is_uncertain, selection_reason, selection_score, is_optional,
    blocked_reason, deferred_until_utc, updated_at
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 0, 1, 30, 0,
    'ZC-061-002 related tutorial verification', 100, 0, NULL, NULL, '$timestamp'
);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', 'active', '$timestamp');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$started_epoch" '+%Y-%m-%dT%H:%M:%SZ')', NULL);
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
) VALUES
    ('$LOCAL_DAY', $((base_epoch - 240)), '${TIME_LABEL_PREFIX}1', 'Safari', '$WINDOW_TITLE', '$PUBLIC_URL', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 180)), '${TIME_LABEL_PREFIX}2', 'Safari', '$WINDOW_TITLE', '$PUBLIC_URL', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 120)), '${TIME_LABEL_PREFIX}3', 'Safari', '$WINDOW_TITLE', '$PUBLIC_URL', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $((base_epoch - 60)), '${TIME_LABEL_PREFIX}4', 'Safari', '$WINDOW_TITLE', '$PUBLIC_URL', 0, NULL, '$timestamp', 'work', 0),
    ('$LOCAL_DAY', $base_epoch, '${TIME_LABEL_PREFIX}5', 'Safari', '$WINDOW_TITLE', '$PUBLIC_URL', 0, NULL, '$timestamp', 'work', 0);
COMMIT;
SQL
    verify_fixture
    print -- "FIXTURE_TASK_ID=$TASK_ID"
    print -- "FIXTURE_TASK_TITLE=$TASK_TITLE"
    print -- "PASS: active technical task and related public tutorial evidence prepared"
}

verify_fixture() {
    require_schema
    [[ -n "$STATE_FILE" && -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail "private restore state is not ready"
    [[ "$(stat -f '%Lp' "$STATE_FILE")" == "600" ]] || fail "private restore state must use mode 600"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND title = '$TASK_TITLE' AND source_kind = 'local' AND is_completed = 0 AND declared_context = 'technical';" "1" "declared technical task"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$GENERAL_TASK_ID' AND title = '$GENERAL_TASK_TITLE' AND source_kind = 'local' AND is_completed = 0 AND declared_context IS NULL;" "1" "general task boundary"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID' AND rank = 0 AND is_main_objective = 1;" "1" "technical task plan row"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$GENERAL_TASK_ID';" "0" "general task remains unplanned"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "technical task active state"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE state = 'active';" "1" "technical task is the only active task"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "1" "technical task open interval"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$GENERAL_TASK_ID';" "0" "general task has no execution state"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND time_label LIKE '$TIME_LABEL_PREFIX%';" "5" "five namespaced browser observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND time_label LIKE '$TIME_LABEL_PREFIX%' AND app_name = 'Safari' AND window_title = '$WINDOW_TITLE' AND url = '$PUBLIC_URL' AND classification = 'work' AND has_screenshot = 0 AND screenshot_path IS NULL;" "5" "exact public Safari tutorial evidence"
    assert_scalar "SELECT COUNT(*) FROM behavior_records AS record JOIN task_activity_intervals AS interval ON interval.task_id = '$TASK_ID' AND interval.ended_at IS NULL WHERE record.source_day = '$LOCAL_DAY' AND record.time_label LIKE '$TIME_LABEL_PREFIX%' AND record.epoch >= CAST(strftime('%s', interval.started_at) AS INTEGER);" "5" "tutorial evidence overlaps the active task"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%' AND (lower(classification) = 'research' OR lower(window_title) NOT LIKE '%tutorial%youtube%' OR lower(url) NOT LIKE 'https://www.youtube.com/%');" "0" "no invented Research label or unrelated context"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%' AND (lower(window_title) LIKE '%/users/%' OR lower(window_title) LIKE '%token%' OR lower(window_title) LIKE '%private%' OR lower(url) LIKE '%/users/%' OR lower(url) LIKE '%token%' OR lower(url) LIKE '%private%' OR lower(url) LIKE '%localhost%' OR lower(url) LIKE '%127.0.0.1%' OR instr(url, '?') > 0 OR instr(url, '#') > 0);" "0" "privacy-safe fixture evidence"
    print -- "PASS: exact technical-task and related-tutorial contract verified without Research classification"
}

cleanup_fixture() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';
DELETE FROM task_activity_intervals WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');
DELETE FROM task_execution_states WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');
DELETE FROM daily_plan_entries WHERE reminder_id IN ('$TASK_ID', '$GENERAL_TASK_ID');
DELETE FROM source_tasks WHERE source_id IN ('$TASK_ID', '$GENERAL_TASK_ID');
COMMIT;
SQL
    restore_snapshot
    verify_clean
}

verify_clean() {
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';" "0" "behavior cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "interval cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "execution cleanup"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$TASK_ID', '$GENERAL_TASK_ID');" "0" "source cleanup"
    if [[ -n "$STATE_FILE" ]]; then
        [[ ! -e "$STATE_FILE" && ! -L "$STATE_FILE" ]] || fail "private restore state was not removed"
    fi
    print -- "PASS: only the ZC-061-002 namespace was removed"
}

expect_verification_failure() {
    local label="$1"
    if (verify_fixture >/dev/null 2>&1); then
        fail "verification accepted $label"
    fi
}

self_test() {
    local original_database="$DATABASE" original_state_file="$STATE_FILE" temporary_database temporary_state_file
    temporary_database="$(mktemp -t zoid-zc061002-fixture).sqlite"
    temporary_state_file="${temporary_database}.restore.sql"
    trap "rm -f -- ${temporary_database:q} ${temporary_database:q}-wal ${temporary_database:q}-shm ${temporary_state_file:q}" EXIT
    DATABASE="$temporary_database"
    STATE_FILE="$temporary_state_file"
    sqlite3 -batch "$DATABASE" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, due_at TEXT, priority INTEGER NOT NULL, is_completed INTEGER NOT NULL, modified_at TEXT, source_hash TEXT, updated_at TEXT NOT NULL, source_kind TEXT NOT NULL, declared_context TEXT);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE UNIQUE INDEX task_activity_one_open ON task_activity_intervals((ended_at IS NULL)) WHERE ended_at IS NULL;
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE today_snapshots(day_key TEXT PRIMARY KEY, payload BLOB NOT NULL, updated_at TEXT NOT NULL);
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind, declared_context) VALUES ('foreign-task', 'Preserve foreign source', 0, 0, '2026-07-15T00:00:00Z', 'local', NULL);
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at, classification, classification_policy_version) VALUES ('2026-07-15', 1, 'foreign-label', 'Foreign App', 'Foreign window', 'https://example.com/', 0, '2026-07-15T00:00:00Z', 'work', 0);
INSERT INTO today_snapshots(day_key, payload, updated_at) VALUES (date('now', 'localtime'), X'010203', '2026-07-15T00:00:00Z');
SQL
    require_schema
    prepare_fixture >/dev/null
    verify_fixture >/dev/null
    sqlite3 "$DATABASE" "UPDATE today_snapshots SET payload = X'AABB', updated_at = '2026-07-15T01:00:00Z' WHERE day_key = '$LOCAL_DAY';"

    sqlite3 "$DATABASE" "UPDATE task_activity_intervals SET started_at = '2999-01-01T00:00:00Z' WHERE task_id = '$TASK_ID';"
    expect_verification_failure "missing temporal overlap"
    sqlite3 "$DATABASE" "UPDATE task_activity_intervals SET started_at = datetime((SELECT MIN(epoch) - 60 FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%'), 'unixepoch') WHERE task_id = '$TASK_ID';"

    sqlite3 "$DATABASE" "UPDATE source_tasks SET declared_context = NULL WHERE source_id = '$TASK_ID';"
    expect_verification_failure "wrong task context"
    sqlite3 "$DATABASE" "UPDATE source_tasks SET declared_context = 'technical' WHERE source_id = '$TASK_ID';"

    sqlite3 "$DATABASE" "UPDATE task_execution_states SET state = 'ready' WHERE task_id = '$TASK_ID'; INSERT INTO task_execution_states(task_id, state, updated_at) VALUES ('foreign-active', 'active', '2026-07-15T00:00:00Z');"
    expect_verification_failure "wrong active task"
    sqlite3 "$DATABASE" "DELETE FROM task_execution_states WHERE task_id = 'foreign-active'; UPDATE task_execution_states SET state = 'active' WHERE task_id = '$TASK_ID';"

    sqlite3 "$DATABASE" "UPDATE behavior_records SET window_title = 'Unrelated feed', url = 'https://example.com/' WHERE time_label = '${TIME_LABEL_PREFIX}1';"
    expect_verification_failure "unrelated URL and window"
    sqlite3 "$DATABASE" "UPDATE behavior_records SET window_title = '$WINDOW_TITLE', url = '$PUBLIC_URL' WHERE time_label = '${TIME_LABEL_PREFIX}1';"

    sqlite3 "$DATABASE" "UPDATE behavior_records SET url = '$PUBLIC_URL?token=private' WHERE time_label = '${TIME_LABEL_PREFIX}2';"
    expect_verification_failure "privacy leakage"
    sqlite3 "$DATABASE" "UPDATE behavior_records SET url = '$PUBLIC_URL' WHERE time_label = '${TIME_LABEL_PREFIX}2';"

    verify_fixture >/dev/null
    cleanup_fixture >/dev/null
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = 'foreign-task' AND title = 'Preserve foreign source';" "1" "foreign source preservation"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label = 'foreign-label' AND url = 'https://example.com/';" "1" "foreign behavior preservation"
    assert_scalar "SELECT hex(payload) || '|' || updated_at FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "010203|2026-07-15T00:00:00Z" "exact Today snapshot restoration"

    sqlite3 "$DATABASE" "DROP TABLE behavior_records;"
    if (verify_fixture >/dev/null 2>&1); then
        fail "verification accepted a SQL/schema failure"
    fi
    DATABASE="$original_database"
    STATE_FILE="$original_state_file"
    print -- "PASS: ZC-061-002 fixture self-test rejects overlap, wrong task, context, relevance, privacy, and SQL failures while restoring foreign state"
}

readonly ACTION="${1:-}"
shift || true
DATABASE=""
STATE_FILE=""
LOCAL_DAY="$(date '+%Y-%m-%d')"
while (( $# > 0 )); do
    case "$1" in
        --database) DATABASE="${2:-}"; shift 2 ;;
        --local-day) LOCAL_DAY="${2:-}"; shift 2 ;;
        --state-file) STATE_FILE="${2:-}"; shift 2 ;;
        *) fail "unknown argument: $1" ;;
    esac
done
[[ "$LOCAL_DAY" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] || fail "--local-day must use YYYY-MM-DD"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
if [[ "$ACTION" != "self-test" ]]; then
    [[ -n "$DATABASE" && -f "$DATABASE" ]] || fail "--database must name an existing database"
    [[ -n "$STATE_FILE" ]] || fail "--state-file is required"
fi

case "$ACTION" in
    prepare) prepare_fixture ;;
    verify) verify_fixture ;;
    cleanup) cleanup_fixture ;;
    verify-clean) verify_clean ;;
    self-test) self_test ;;
    *) fail "usage: $0 {prepare|verify|cleanup|verify-clean|self-test} [--database PATH] [--state-file PATH] [--local-day YYYY-MM-DD]" ;;
esac
