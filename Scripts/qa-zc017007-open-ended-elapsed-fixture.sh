#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc017007"
readonly TASK_ID="$PREFIX-task"
readonly TASK_TITLE="Verify live elapsed time"
readonly PRIVATE_SENTINEL="PRIVATE-ZC017007-DO-NOT-RENDER"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|verify|cleanup-owned|self-test> ..."
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

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc017007-* ]] \
        || fail "root is outside the isolated ZC-017-007 namespace: $root"
    [[ "$root" != "/" && "$root" != "/private" && "$root" != "/private/tmp" ]] \
        || fail "refusing unsafe root: $root"
}

root_manifest() {
    local root="$1"
    [[ -d "$root" ]] || fail "root does not exist: $root"
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
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    assert_safe_root "$qa_root"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$snapshot" == /private/tmp/zoid-666-zc017007-* ]] \
        || fail "snapshot is outside the isolated ZC-017-007 namespace"
    [[ ! -e "$snapshot" ]] || fail "snapshot already exists: $snapshot"
    [[ ! -e "$snapshot.zc017007-target" ]] || fail "snapshot target marker already exists"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc017007-target"
    root_manifest "$snapshot" > "$snapshot.zc017007-manifest"
    [[ -s "$snapshot.zc017007-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated ZC-017-007 QA root"
}

restore_root() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc017007-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc017007-target")" == "$qa_root" ]] \
        || fail "snapshot target does not match requested QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc017007-restored-manifest"
    cmp -s "$snapshot.zc017007-manifest" "$snapshot.zc017007-restored-manifest" \
        || fail "restored QA root differs from the byte manifest"
    print -- "PASS: restored isolated ZC-017-007 QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    local current
    assert_safe_root "$qa_root"
    [[ -f "$snapshot.zc017007-manifest" ]] || fail "snapshot manifest is missing"
    current="$(mktemp /private/tmp/zoid-666-zc017007-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc017007-manifest" "$current" \
        || fail "current QA root differs from the byte manifest"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated ZC-017-007 QA root matches the byte baseline"
}

require_database() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals task_sprint_sessions; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table table"
    done
}

cleanup_owned() {
    sqlite3 -batch "$DATABASE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM task_sprint_sessions WHERE task_id = '$TASK_ID';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
SQL
}

insert_task() {
    local state="$1"
    local timestamp="$2"
    sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO source_tasks(
    source_id, title, notes, list_id, list_name, due_at, priority,
    is_completed, modified_at, source_hash, updated_at, source_kind
) VALUES (
    '$TASK_ID', '$TASK_TITLE', '$PRIVATE_SENTINEL', '$PREFIX-list',
    'Zoid 666 Local QA', NULL, 9, 0, '$timestamp', '$PREFIX-hash', '$timestamp', 'local'
);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes,
    estimate_is_uncertain, selection_reason, selection_score, is_optional,
    blocked_reason, deferred_until_utc, updated_at
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 1, 1, 45, 0,
    'ZC-017-007 signed verifier', 100, 0, NULL, NULL, '$timestamp'
);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', '$state', '$timestamp');
SQL
}

prepare() {
    local mode="$1"
    local now_epoch timestamp open_epoch closed_start closed_end
    cleanup_owned
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "foreign open interval refusal"
    now_epoch="$(date +%s)"
    timestamp="$(date -u -r "$now_epoch" +%Y-%m-%dT%H:%M:%SZ)"
    insert_task "$([[ "$mode" == paused ]] && print paused || print active)" "$timestamp"
    case "$mode" in
        live)
            open_epoch=$((now_epoch - 175))
            sqlite3 -batch "$DATABASE" "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES ('$TASK_ID', '$(date -u -r "$open_epoch" +%Y-%m-%dT%H:%M:%SZ)', NULL);"
            ;;
        rollback)
            closed_start=$((now_epoch - 1_800))
            closed_end=$((closed_start + 540))
            open_epoch=$((now_epoch + 1_200))
            sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$closed_start" +%Y-%m-%dT%H:%M:%SZ)', '$(date -u -r "$closed_end" +%Y-%m-%dT%H:%M:%SZ)');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$open_epoch" +%Y-%m-%dT%H:%M:%SZ)', NULL);
SQL
            ;;
        fallback)
            closed_start=$((now_epoch - 900))
            closed_end=$((closed_start + 540))
            sqlite3 -batch "$DATABASE" "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES ('$TASK_ID', '$(date -u -r "$closed_start" +%Y-%m-%dT%H:%M:%SZ)', '$(date -u -r "$closed_end" +%Y-%m-%dT%H:%M:%SZ)');"
            ;;
        bounded)
            open_epoch=$((now_epoch - 300))
            sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$open_epoch" +%Y-%m-%dT%H:%M:%SZ)', NULL);
INSERT INTO task_sprint_sessions(
    task_id, duration_minutes, started_at_utc, active_segment_started_at_utc,
    accumulated_active_seconds, state, ended_at_utc
) VALUES (
    '$TASK_ID', 20, '$(date -u -r "$open_epoch" +%Y-%m-%dT%H:%M:%SZ)',
    '$(date -u -r "$open_epoch" +%Y-%m-%dT%H:%M:%SZ)', 0, 'active', NULL
);
SQL
            ;;
        paused)
            closed_start=$((now_epoch - 600))
            closed_end=$((closed_start + 300))
            sqlite3 -batch "$DATABASE" "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES ('$TASK_ID', '$(date -u -r "$closed_start" +%Y-%m-%dT%H:%M:%SZ)', '$(date -u -r "$closed_end" +%Y-%m-%dT%H:%M:%SZ)');"
            ;;
        *) fail "unsupported fixture mode: $mode" ;;
    esac
    verify "$mode"
    print -- "FIXTURE_TASK_TITLE=$TASK_TITLE"
    print -- "PRIVATE_SENTINEL=$PRIVATE_SENTINEL"
}

verify() {
    local mode="$1"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND source_kind = 'local' AND is_completed = 0;" "1" "local source task"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID' AND is_main_objective = 1;" "1" "Today plan entry"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND notes = '$PRIVATE_SENTINEL';" "1" "private sentinel"
    case "$mode" in
        live)
            assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "live state"
            assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "1" "live open interval"
            assert_scalar "SELECT COUNT(*) FROM task_sprint_sessions WHERE task_id = '$TASK_ID';" "0" "live sprint exclusion"
            ;;
        rollback)
            assert_scalar "SELECT SUM(strftime('%s', ended_at) - strftime('%s', started_at)) / 60 FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NOT NULL;" "9" "rollback confirmed elapsed"
            assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL AND started_at > datetime('now');" "1" "future rollback interval"
            ;;
        fallback)
            assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "fallback active state"
            assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "fallback missing open metadata"
            assert_scalar "SELECT SUM(strftime('%s', ended_at) - strftime('%s', started_at)) / 60 FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NOT NULL;" "9" "fallback confirmed elapsed"
            ;;
        bounded)
            assert_scalar "SELECT COUNT(*) FROM task_sprint_sessions WHERE task_id = '$TASK_ID' AND state = 'active' AND duration_minutes = 20;" "1" "bounded sprint"
            ;;
        paused)
            assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'paused';" "1" "paused state"
            assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "0" "paused interval closure"
            ;;
    esac
    print -- "PASS: ZC-017-007 $mode fixture is ready"
}

self_test() {
    local root qa_root snapshot database mode
    root="$(mktemp -d /private/tmp/zoid-666-zc017007-self-test.XXXXXX)"
    qa_root="$root-runtime"
    snapshot="$root-snapshot"
    mkdir -p "$qa_root/Application Support/Zoid 666"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    trap 'rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc017007-target" "$snapshot.zc017007-manifest" "$snapshot.zc017007-restored-manifest"' EXIT
    sqlite3 "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, due_at TEXT, priority INTEGER NOT NULL, is_completed INTEGER NOT NULL, modified_at TEXT, source_hash TEXT, updated_at TEXT NOT NULL, source_kind TEXT NOT NULL);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE task_sprint_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, duration_minutes INTEGER NOT NULL, started_at_utc TEXT NOT NULL, active_segment_started_at_utc TEXT, accumulated_active_seconds REAL NOT NULL DEFAULT 0, state TEXT NOT NULL, ended_at_utc TEXT);
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES ('foreign-task', 'Preserve me', 0, 0, '2026-07-15T00:00:00Z', 'local');
SQL
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot"
    for mode in live rollback fallback bounded paused; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        "$SCRIPT_PATH" prepare "$mode" "$database" --local-day 2026-07-15 >/dev/null
        "$SCRIPT_PATH" verify "$mode" "$database" --local-day 2026-07-15 >/dev/null
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM source_tasks WHERE source_id = 'foreign-task';")" == "1" ]] \
            || fail "$mode altered a foreign row"
    done
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc017007-target" "$snapshot.zc017007-manifest" "$snapshot.zc017007-restored-manifest"
    trap - EXIT
    print -- "PASS: ZC-017-007 fixture self-test"
}

COMMAND="${1:-}"
shift || true
case "$COMMAND" in
    snapshot-root)
        (( $# == 2 )) || usage
        snapshot_root "$1" "$2"
        ;;
    restore-root)
        (( $# == 2 )) || usage
        restore_root "$1" "$2"
        ;;
    assert-root-restored)
        (( $# == 2 )) || usage
        assert_root_restored "$1" "$2"
        ;;
    prepare|verify)
        MODE="${1:-}"
        DATABASE="${2:-}"
        shift $(( $# < 2 ? $# : 2 ))
        LOCAL_DAY="$(date +%F)"
        while (( $# > 0 )); do
            case "$1" in
                --local-day) LOCAL_DAY="${2:-}"; shift 2 ;;
                *) fail "unknown argument: $1" ;;
            esac
        done
        [[ "$LOCAL_DAY" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] || fail "invalid local day"
        require_database
        if [[ "$COMMAND" == prepare ]]; then
            prepare "$MODE"
        else
            verify "$MODE"
        fi
        ;;
    cleanup-owned)
        DATABASE="${1:-}"
        require_database
        cleanup_owned
        assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "source cleanup"
        assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "interval cleanup"
        print -- "PASS: removed only ZC-017-007 namespaced rows"
        ;;
    self-test) self_test ;;
    *) usage ;;
esac
