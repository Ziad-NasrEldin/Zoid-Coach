#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly ARGUMENT_ONE="${2:-}"
readonly ARGUMENT_TWO="${3:-}"
readonly SCRIPT_PATH="${0:A}"
readonly PRIMARY_TASK_ID="qa-zc055003-keyboard-primary"
readonly PRIMARY_TASK_TITLE="QA keyboard lifecycle primary"
readonly TARGET_TASK_ID="qa-zc055003-keyboard-target"
readonly TARGET_TASK_TITLE="QA keyboard lifecycle switch target"
readonly PRIVATE_NOTE="qa-zc055003-private-note"
readonly DAY_KEY="${ZOID_666_QA_ZC055003_DAY:-$(date '+%Y-%m-%d')}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|prepare-ambiguous|prepare-no-active|assert-ready|assert-active-primary|assert-paused-primary|assert-resumed-primary|assert-switched|assert-target-completed|assert-primary-completed|assert-ambiguous|assert-no-active|cleanup|snapshot-root|restore-root|assert-root-restored|self-test> [database-or-root] [snapshot]"
    exit 2
}

scalar() {
    sqlite3 -batch -noheader "$ARGUMENT_ONE" "$1"
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
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals task_pause_events; do
        require_table "$table"
    done
    require_column source_tasks source_kind
    require_column daily_plan_entries is_main_objective
    require_column task_execution_states state
    require_column task_activity_intervals ended_at
    require_column task_pause_events reason
}

assert_owned_rows() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "2" "owned source tasks"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "2" "owned plan rows"
}

assert_ready() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$PRIMARY_TASK_ID' AND title = '$PRIMARY_TASK_TITLE' AND source_kind = 'local' AND is_completed = 0;" "1" "ready primary task"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TARGET_TASK_ID' AND title = '$TARGET_TASK_TITLE' AND source_kind = 'local' AND is_completed = 0;" "1" "ready switch target"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$PRIMARY_TASK_ID' AND rank = 0 AND is_main_objective = 1;" "1" "primary recommendation precedence"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TARGET_TASK_ID' AND rank = 1 AND is_main_objective = 0;" "1" "secondary switch target"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND state = 'ready';" "2" "ready execution states"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "no owned intervals"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "no owned pauses"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no pre-existing open interval"
}

assert_active_primary() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$PRIMARY_TASK_ID' AND state = 'active';" "1" "active primary state"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TARGET_TASK_ID' AND state = 'ready';" "1" "ready switch target state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NULL;" "1" "one primary open interval"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "1" "one global open interval"
}

assert_paused_primary() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$PRIMARY_TASK_ID' AND state = 'paused';" "1" "paused primary state"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TARGET_TASK_ID' AND state = 'ready';" "1" "ready target after pause"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NOT NULL;" "1" "preserved closed primary interval"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no open interval after pause"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$PRIMARY_TASK_ID' AND reason = 'doneForNow' AND resumed_at IS NULL;" "1" "open done-for-now pause"
}

assert_resumed_primary() {
    assert_active_primary
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NOT NULL;" "1" "first primary interval remains closed"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID';" "2" "one preserved and one resumed interval"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$PRIMARY_TASK_ID' AND reason = 'doneForNow' AND resumed_at IS NOT NULL;" "1" "done-for-now pause resumed"
}

assert_switched() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$PRIMARY_TASK_ID' AND state = 'paused';" "1" "primary paused by switch"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TARGET_TASK_ID' AND state = 'active';" "1" "target active after switch"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NOT NULL;" "2" "both primary work intervals preserved"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TARGET_TASK_ID' AND ended_at IS NULL;" "1" "one target open interval"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "1" "one global open interval after switch"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$PRIMARY_TASK_ID' AND reason = 'switchingTasks' AND resumed_at IS NULL;" "1" "durable switch reason"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NOT NULL AND julianday(ended_at) >= julianday(started_at);" "2" "non-negative preserved primary timing"
}

assert_target_completed() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TARGET_TASK_ID' AND state = 'completed';" "1" "completed switch target"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TARGET_TASK_ID' AND is_completed = 1;" "1" "durable local target completion"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$PRIMARY_TASK_ID' AND state = 'paused';" "1" "primary remains paused"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TARGET_TASK_ID' AND ended_at IS NOT NULL;" "1" "target interval closed by completion"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no open interval after target completion"
}

assert_primary_completed() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND state = 'completed';" "2" "both tasks completed"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND is_completed = 1;" "2" "both local completions persisted"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id = '$PRIMARY_TASK_ID' AND resumed_at IS NULL;" "0" "primary pause closed by completion"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no open interval after both completions"
}

assert_ambiguous() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND state = 'paused';" "2" "two ambiguous paused tasks"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND reason = 'doneForNow' AND resumed_at IS NULL;" "2" "two ordinary open pauses"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no active task in ambiguous state"
}

assert_no_active() {
    validate_schema
    assert_owned_rows
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND state = 'completed';" "2" "no-active completed states"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND is_completed = 1;" "2" "no-active source completion"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "no-active open interval absence"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID') AND resumed_at IS NULL;" "0" "no-active open pause absence"
}

prepare() {
    validate_schema
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "unused task namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "unused plan namespace"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "clean active-session baseline"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$ARGUMENT_ONE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_plan_entries WHERE day_key = '$DAY_KEY';
INSERT INTO source_tasks(source_id, title, due_at, priority, is_completed, updated_at, notes, list_id, list_name, modified_at, source_hash, source_kind)
VALUES
('$PRIMARY_TASK_ID', '$PRIMARY_TASK_TITLE', '$DAY_KEY' || 'T12:00:00Z', 9, 0, '$timestamp', '$PRIVATE_NOTE', NULL, 'Zoid 666 QA', '$timestamp', '$PRIMARY_TASK_ID', 'local'),
('$TARGET_TASK_ID', '$TARGET_TASK_TITLE', NULL, 1, 0, '$timestamp', '$PRIVATE_NOTE', NULL, 'Zoid 666 QA', '$timestamp', '$TARGET_TASK_ID', 'local');
INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, estimate_is_uncertain)
VALUES
('$DAY_KEY', '$PRIMARY_TASK_ID', 0, 1, 30, '$timestamp', 'ZC-055-003 keyboard fixture', 100, 0, NULL, NULL, 0),
('$DAY_KEY', '$TARGET_TASK_ID', 1, 0, 30, '$timestamp', 'ZC-055-003 keyboard fixture', 10, 0, NULL, NULL, 0);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES
('$PRIMARY_TASK_ID', 'ready', '$timestamp'),
('$TARGET_TASK_ID', 'ready', '$timestamp');
COMMIT;
SQL
    assert_ready
}

prepare_ambiguous() {
    prepare
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$ARGUMENT_ONE" <<SQL
BEGIN IMMEDIATE;
UPDATE task_execution_states SET state = 'paused', updated_at = '$timestamp'
WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at)
VALUES
('$PRIMARY_TASK_ID', 'doneForNow', '$timestamp', NULL),
('$TARGET_TASK_ID', 'doneForNow', '$timestamp', NULL);
COMMIT;
SQL
    assert_ambiguous
}

prepare_no_active() {
    prepare
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$ARGUMENT_ONE" <<SQL
BEGIN IMMEDIATE;
UPDATE task_execution_states SET state = 'completed', updated_at = '$timestamp'
WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
UPDATE source_tasks SET is_completed = 1, updated_at = '$timestamp'
WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
COMMIT;
SQL
    assert_no_active
}

cleanup() {
    validate_schema
    sqlite3 -batch "$ARGUMENT_ONE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
DELETE FROM task_activity_intervals WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
DELETE FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
DELETE FROM daily_plan_entries WHERE reminder_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
DELETE FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');
COMMIT;
PRAGMA foreign_keys = ON;
SQL
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "owned source cleanup"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "owned plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "owned state cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "owned interval cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_pause_events WHERE task_id IN ('$PRIMARY_TASK_ID', '$TARGET_TASK_ID');" "0" "owned pause cleanup"
}

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc055003-* ]] || fail "refusing non-ZC-055-003 isolated root: $root"
    [[ "$root" != "/private/tmp" && "$root" != "/" ]] || fail "refusing unsafe root: $root"
}

root_manifest() {
    local root="${1:A}"
    (
        cd "$root"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
            /usr/bin/shasum -a 256 "$entry"
        done
        find . -type l -print | LC_ALL=C sort | while IFS= read -r entry; do
            print -r -- "SYMLINK $entry -> $(readlink "$entry")"
        done
    )
}

snapshot_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$snapshot" == /private/tmp/zoid-666-zc055003-* ]] || fail "snapshot must use the isolated ZC-055-003 namespace"
    [[ ! -e "$snapshot" && ! -e "$snapshot.zc055003-target" ]] || fail "snapshot already exists"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc055003-target"
    root_manifest "$snapshot" > "$snapshot.zc055003-manifest"
    [[ -s "$snapshot.zc055003-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated ZC-055-003 QA root"
}

restore_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc055003-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc055003-target")" == "$qa_root" ]] || fail "snapshot target does not match QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc055003-restored-manifest"
    cmp -s "$snapshot.zc055003-manifest" "$snapshot.zc055003-restored-manifest" || fail "restored QA root differs from baseline"
    print -- "PASS: restored isolated ZC-055-003 QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -f "$snapshot.zc055003-manifest" ]] || fail "snapshot manifest is missing"
    local current
    current="$(mktemp /private/tmp/zoid-666-zc055003-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc055003-manifest" "$current" || fail "current QA root differs from byte baseline"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated ZC-055-003 QA root matches byte baseline"
}

self_test() {
    typeset -g SELF_TEST_ROOT
    SELF_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zc055003-fixture.XXXXXX")"
    local database="$SELF_TEST_ROOT/fixture.sqlite"
    local timestamp="2026-07-15T03:00:00Z"
    local qa_root="/private/tmp/zoid-666-zc055003-fixture-self-test-root"
    local snapshot="/private/tmp/zoid-666-zc055003-fixture-self-test-snapshot"
    trap 'rm -rf -- "${SELF_TEST_ROOT:-}" "$qa_root" "$snapshot" "$snapshot".zc055003-*(N)' EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, due_at TEXT, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, modified_at TEXT, source_hash TEXT, source_kind TEXT NOT NULL DEFAULT 'reminders');
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, updated_at TEXT NOT NULL, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE task_pause_events(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, reason TEXT NOT NULL, paused_at TEXT NOT NULL, resumed_at TEXT);
SQL
    "$SCRIPT_PATH" prepare "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = CASE task_id WHEN '$PRIMARY_TASK_ID' THEN 'active' ELSE state END; INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES('$PRIMARY_TASK_ID', '$timestamp', NULL);"
    "$SCRIPT_PATH" assert-active-primary "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'paused' WHERE task_id = '$PRIMARY_TASK_ID'; UPDATE task_activity_intervals SET ended_at = '$timestamp' WHERE task_id = '$PRIMARY_TASK_ID'; INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES('$PRIMARY_TASK_ID', 'doneForNow', '$timestamp', NULL);"
    "$SCRIPT_PATH" assert-paused-primary "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'active' WHERE task_id = '$PRIMARY_TASK_ID'; UPDATE task_pause_events SET resumed_at = '$timestamp' WHERE task_id = '$PRIMARY_TASK_ID'; INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES('$PRIMARY_TASK_ID', '$timestamp', NULL);"
    "$SCRIPT_PATH" assert-resumed-primary "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'paused' WHERE task_id = '$PRIMARY_TASK_ID'; UPDATE task_execution_states SET state = 'active' WHERE task_id = '$TARGET_TASK_ID'; UPDATE task_activity_intervals SET ended_at = '$timestamp' WHERE task_id = '$PRIMARY_TASK_ID' AND ended_at IS NULL; INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES('$TARGET_TASK_ID', '$timestamp', NULL); INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES('$PRIMARY_TASK_ID', 'switchingTasks', '$timestamp', NULL);"
    "$SCRIPT_PATH" assert-switched "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'completed' WHERE task_id = '$TARGET_TASK_ID'; UPDATE source_tasks SET is_completed = 1 WHERE source_id = '$TARGET_TASK_ID'; UPDATE task_activity_intervals SET ended_at = '$timestamp' WHERE task_id = '$TARGET_TASK_ID' AND ended_at IS NULL;"
    "$SCRIPT_PATH" assert-target-completed "$database"
    sqlite3 -batch "$database" "UPDATE task_execution_states SET state = 'completed' WHERE task_id = '$PRIMARY_TASK_ID'; UPDATE source_tasks SET is_completed = 1 WHERE source_id = '$PRIMARY_TASK_ID'; UPDATE task_pause_events SET resumed_at = '$timestamp' WHERE task_id = '$PRIMARY_TASK_ID' AND resumed_at IS NULL;"
    "$SCRIPT_PATH" assert-primary-completed "$database"
    "$SCRIPT_PATH" cleanup "$database"
    "$SCRIPT_PATH" prepare-ambiguous "$database"
    "$SCRIPT_PATH" assert-ambiguous "$database"
    "$SCRIPT_PATH" cleanup "$database"
    "$SCRIPT_PATH" prepare-no-active "$database"
    "$SCRIPT_PATH" assert-no-active "$database"
    "$SCRIPT_PATH" cleanup "$database"
    rm -rf -- "$qa_root" "$snapshot" "$snapshot".zc055003-*(N)
    mkdir -p "$qa_root"
    print -r -- "baseline" > "$qa_root/state"
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot"
    print -r -- "changed" > "$qa_root/state"
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    [[ "$(<"$qa_root/state")" == "baseline" ]] || fail "root restore did not recover original bytes"
    rm -rf -- "$SELF_TEST_ROOT" "$qa_root" "$snapshot" "$snapshot".zc055003-*(N)
    SELF_TEST_ROOT=""
    trap - EXIT
    print -- "PASS: ZC-055-003 keyboard fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then
    self_test
    exit 0
fi

case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        [[ -n "$ARGUMENT_ONE" && -n "$ARGUMENT_TWO" ]] || usage
        ;;
    *)
        [[ -n "$ARGUMENT_ONE" && -f "$ARGUMENT_ONE" ]] || usage
        command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
        ;;
esac

case "$COMMAND" in
    prepare) prepare ;;
    prepare-ambiguous) prepare_ambiguous ;;
    prepare-no-active) prepare_no_active ;;
    assert-ready) assert_ready ;;
    assert-active-primary) assert_active_primary ;;
    assert-paused-primary) assert_paused_primary ;;
    assert-resumed-primary) assert_resumed_primary ;;
    assert-switched) assert_switched ;;
    assert-target-completed) assert_target_completed ;;
    assert-primary-completed) assert_primary_completed ;;
    assert-ambiguous) assert_ambiguous ;;
    assert-no-active) assert_no_active ;;
    cleanup) cleanup ;;
    snapshot-root) snapshot_root ;;
    restore-root) restore_root ;;
    assert-root-restored) assert_root_restored ;;
    *) usage ;;
esac
