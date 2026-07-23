#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc062004"
readonly TASK_ID="$PREFIX-active-technical"
readonly TASK_TITLE="QA ZC-062-004 active technical task"
readonly INVALID_REMINDER_ID="$PREFIX-invalid-reminder-bootstrap"
readonly PRIVATE_TITLE="$PREFIX-private-window"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"
readonly INITIAL_MINUTES=14
readonly ADVANCE_MINUTES=5
readonly FRESH_LIMIT=240

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|simulate-invalid-bootstrap|source-state|advance|assert-control|assert-result|self-test> ..."
    exit 2
}
scalar() { sqlite3 -batch -noheader "$DATABASE" "$1"; }
assert_scalar() {
    local actual
    actual="$(scalar "$1")" || fail "$3 query failed"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc062004-* ]] || fail "refusing non-ZC-062-004 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / && ! -L "$root" ]] || fail "refusing unsafe or symlink root"
}

assert_owned_paths() {
    local qa_root="${DATABASE:h:h:h}"
    assert_safe_root "$qa_root"
    [[ "${DATABASE:A}" == "$qa_root/Application Support/Zoid 666/zoid-coach.sqlite" ]] || fail "wrong database root"
    [[ "${SCREENWATCH_ROOT:A}" == "$qa_root/Screenwatch/days" ]] || fail "wrong Screenwatch source root"
    [[ ! -L "$SCREENWATCH_ROOT" ]] || fail "symlink Screenwatch source rejected"
}

root_manifest() {
    local root="$1"
    [[ -d "$root" ]] || fail "root does not exist: $root"
    (
        cd "$root"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do /usr/bin/shasum -a 256 "$file"; done
        find . -type l -print | LC_ALL=C sort | while IFS= read -r file; do print -r -- "SYMLINK $file -> $(readlink "$file")"; done
    )
}

snapshot_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$root" && ! -e "$snapshot" && "$snapshot" == /private/tmp/zoid-666-zc062004-* ]] || fail "invalid snapshot state"
    /usr/bin/ditto "$root" "$snapshot"
    print -r -- "$root" > "$snapshot.zc062004-target"
    root_manifest "$snapshot" > "$snapshot.zc062004-manifest"
    [[ -s "$snapshot.zc062004-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$snapshot" && -f "$snapshot.zc062004-target" ]] || fail "snapshot is incomplete"
    [[ "$(<"$snapshot.zc062004-target")" == "$root" ]] || fail "snapshot target mismatch"
    rm -rf -- "$root"
    /usr/bin/ditto "$snapshot" "$root"
    root_manifest "$root" > "$snapshot.zc062004-restored"
    cmp -s "$snapshot.zc062004-manifest" "$snapshot.zc062004-restored" || fail "restored root differs from byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local root="${1:A}" snapshot="${2:A}" current
    assert_safe_root "$root"
    current="$(mktemp /private/tmp/zoid-666-zc062004-manifest.XXXXXX)"
    trap "rm -f -- ${current:q}" EXIT
    root_manifest "$root" > "$current"
    cmp -s "$snapshot.zc062004-manifest" "$current" || fail "cleanup mismatch"
    print -- "PASS: isolated QA root matches byte-exact baseline"
}

require_database() {
    assert_owned_paths
    [[ -f "$DATABASE" ]] || fail "database is missing"
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records today_snapshots prompt_episodes; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 1 "$table production table"
    done
    assert_scalar "PRAGMA integrity_check;" ok "database integrity"
}

prepare() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id<>'$TASK_ID';" 0 "foreign active interval"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key='$LOCAL_DAY' AND reminder_id<>'$TASK_ID';" 0 "foreign planned-day entry"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day='$LOCAL_DAY' AND time_label NOT LIKE '$PREFIX-%';" 0 "foreign current-day behavior evidence"
    mkdir -p "$DAY_DIRECTORY" "${MARKER:h}"
    sqlite3 "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM task_activity_intervals WHERE task_id='$TASK_ID';
DELETE FROM task_execution_states WHERE task_id='$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id='$TASK_ID';
DELETE FROM source_tasks WHERE source_id IN ('$TASK_ID','$INVALID_REMINDER_ID');
DELETE FROM behavior_records WHERE time_label LIKE '$PREFIX-%';
DELETE FROM today_snapshots WHERE day_key='$LOCAL_DAY';
INSERT INTO source_tasks(source_id,title,priority,is_completed,updated_at,source_kind,declared_context)
VALUES('$TASK_ID','$TASK_TITLE',9,0,'$TIMESTAMP','local','technical');
INSERT INTO source_tasks(source_id,title,priority,is_completed,updated_at,source_kind,declared_context)
VALUES('$INVALID_REMINDER_ID','Invalid Reminder bootstrap row',0,0,'$TIMESTAMP','reminders',NULL);
INSERT INTO daily_plan_entries(day_key,reminder_id,rank,is_main_objective,estimate_minutes,updated_at)
VALUES('$LOCAL_DAY','$TASK_ID',1,1,45,'$TIMESTAMP');
INSERT INTO task_execution_states(task_id,state,updated_at) VALUES('$TASK_ID','active','$TIMESTAMP');
INSERT INTO task_activity_intervals(task_id,started_at,ended_at)
VALUES('$TASK_ID',datetime('now','-$INITIAL_MINUTES minutes'),NULL);
COMMIT;
SQL
    local interval_id
    interval_id="$(scalar "SELECT id FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;")"
    jq -n --argjson intervalID "$interval_id" --argjson initial "$INITIAL_MINUTES" --argjson advanced "$((INITIAL_MINUTES+ADVANCE_MINUTES))" \
        '{intervalID:$intervalID,initialElapsed:$initial,advancedElapsed:$advanced}' > "$MARKER"
    print -r -- "{\"t\":\"$PREFIX-fresh\",\"epoch\":$(( $(date +%s)-30 )),\"app\":\"Terminal\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" > "$LOG_FILE"
    touch "$LOG_FILE"
    print -- "PASS: prepared one local manually tracked active task and fresh isolated source"
}

simulate_invalid_bootstrap() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$INVALID_REMINDER_ID' AND source_kind='reminders';" 1 "invalid Reminder bootstrap seed"
    sqlite3 "$DATABASE" "DELETE FROM source_tasks WHERE source_id='$INVALID_REMINDER_ID' AND source_kind='reminders';"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$TASK_ID' AND source_kind='local' AND is_completed=0;" 1 "local task survives invalid Reminder bootstrap"
    print -- "PASS: invalid Reminder bootstrap cannot remove the local active task"
}

source_state() {
    require_database
    case "$PHASE" in
        fresh)
            print -r -- "{\"t\":\"$PREFIX-fresh-advance\",\"epoch\":$(( $(date +%s)-10 )),\"app\":\"Terminal\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" >> "$LOG_FILE"
            touch "$LOG_FILE"
            ;;
        stale)
            [[ -f "$LOG_FILE" ]] || fail "source missing before stale transition"
            sqlite3 "$DATABASE" "UPDATE behavior_records SET epoch=epoch-1200 WHERE time_label LIKE '$PREFIX-%';"
            local temporary="$LOG_FILE.$$.tmp"
            jq -c '.epoch -= 1200' "$LOG_FILE" > "$temporary"
            mv "$temporary" "$LOG_FILE"
            touch -t 200001010000 "$LOG_FILE"
            ;;
        missing)
            [[ -f "$LOG_FILE" ]] || fail "source missing before controlled removal"
            sqlite3 "$DATABASE" "DELETE FROM behavior_records WHERE time_label LIKE '$PREFIX-%';"
            rm -f -- "$LOG_FILE"
            ;;
        *) fail "unsupported source phase: $PHASE" ;;
    esac
    print -- "PASS: applied $PHASE only to the isolated Screenwatch stream"
}

advance() {
    require_database
    [[ -s "$MARKER" ]] || fail "tracking marker missing"
    local before_id
    before_id="$(scalar "SELECT id FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;")"
    [[ "$before_id" == "$(jq -r .intervalID "$MARKER")" ]] || fail "interval identity changed before deterministic advance"
    sqlite3 "$DATABASE" "UPDATE task_activity_intervals SET started_at=datetime(started_at,'-$ADVANCE_MINUTES minutes') WHERE id=$before_id AND task_id='$TASK_ID' AND ended_at IS NULL;"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE id=$before_id AND task_id='$TASK_ID' AND ended_at IS NULL;" 1 "singular interval after deterministic advance"
    print -- "PASS: advanced owned manual-tracking clock without replacing the interval"
}

assert_task_and_interval() {
    local expected_id
    expected_id="$(jq -r .intervalID "$MARKER")"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$TASK_ID' AND source_kind='local' AND declared_context='technical' AND is_completed=0;" 1 "local technical task"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$INVALID_REMINDER_ID';" 0 "invalid Reminder bootstrap row removed"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id='$TASK_ID' AND state='active';" 1 "active task state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;" 1 "one open interval"
    assert_scalar "SELECT id FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;" "$expected_id" "stable interval identity"
}

assert_control() {
    require_database
    assert_task_and_interval
    [[ -f "$LOG_FILE" ]] || fail "fresh source control missing"
    (( $(date +%s)-$(stat -f %m "$LOG_FILE") <= FRESH_LIMIT )) || fail "fresh source control is stale"
    local initial
    initial="$(jq -r .initialElapsed "$MARKER")"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.taskRows') WHERE day_key='$LOCAL_DAY' AND json_extract(value,'$.taskID')='$TASK_ID' AND json_extract(value,'$.state')='active' AND json_extract(value,'$.elapsedMinutes')>=$initial;" 1 "fresh elapsed Today control"
    print -- "PASS: fresh control has one active interval and truthful elapsed time"
}

assert_result() {
    require_database
    assert_task_and_interval
    local advanced
    advanced="$(jq -r .advancedElapsed "$MARKER")"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" 1 "one canonical Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.taskRows') WHERE day_key='$LOCAL_DAY' AND json_extract(CAST(payload AS TEXT),'$.activeTask.taskID')='$TASK_ID' AND json_extract(value,'$.taskID')='$TASK_ID' AND json_extract(value,'$.state')='active' AND json_extract(value,'$.elapsedMinutes')>=$advanced;" 1 "advanced elapsed Today state"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE CAST(payload AS TEXT) LIKE '%$PRIVATE_TITLE%' OR CAST(payload AS TEXT) LIKE '%$PRIVATE_URL%';" 0 "private source evidence excluded"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE title LIKE '%$PRIVATE_TITLE%' OR summary LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_URL%';" 0 "private prompt evidence excluded"
    case "$PHASE" in
        fresh)
            [[ -f "$LOG_FILE" ]] || fail "fresh source missing"
            (( $(date +%s)-$(stat -f %m "$LOG_FILE") <= FRESH_LIMIT )) || fail "fresh source accepted as stale"
            assert_scalar "SELECT CASE WHEN COUNT(*)>=1 THEN 1 ELSE 0 END FROM behavior_records WHERE time_label LIKE '$PREFIX-%' AND CAST(strftime('%s','now') AS INTEGER)-epoch<=240;" 1 "fresh derived evidence"
            ;;
        stale)
            [[ -f "$LOG_FILE" ]] || fail "stale source missing"
            (( $(date +%s)-$(stat -f %m "$LOG_FILE") > FRESH_LIMIT )) || fail "stale source accepted as fresh"
            assert_scalar "SELECT CASE WHEN COUNT(*)>=1 AND MIN(CAST(strftime('%s','now') AS INTEGER)-epoch)>900 THEN 1 ELSE 0 END FROM behavior_records WHERE time_label LIKE '$PREFIX-%';" 1 "stale derived evidence"
            ;;
        missing)
            [[ ! -e "$LOG_FILE" ]] || fail "missing source remains"
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$PREFIX-%';" 0 "missing derived evidence"
            ;;
        *) fail "unsupported result phase: $PHASE" ;;
    esac
    print -- "PASS: $PHASE source keeps one active interval and advanced elapsed state across reconstruction"
}

expect_failure() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then fail "validator accepted $label"; fi; }

self_test() (
    local qa_root snapshot database source day now marker
    qa_root="$(mktemp -d /private/tmp/zoid-666-zc062004-self-test.XXXXXX)"
    snapshot="$qa_root-snapshot"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    source="$qa_root/Screenwatch/days"
    day="$(date +%F)"; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; marker="$qa_root/ZC062004/tracking.json"
    mkdir -p "${database:h}"
    trap 'rm -rf -- "$qa_root" "$snapshot" "$snapshot.zc062004-target" "$snapshot.zc062004-manifest" "$snapshot.zc062004-restored"' EXIT
    sqlite3 "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY,title TEXT,priority INTEGER,is_completed INTEGER,updated_at TEXT,source_kind TEXT,declared_context TEXT);
CREATE TABLE daily_plan_entries(day_key TEXT,reminder_id TEXT,rank INTEGER,is_main_objective INTEGER,estimate_minutes INTEGER,updated_at TEXT);
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY,state TEXT,updated_at TEXT);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT,task_id TEXT,started_at TEXT,ended_at TEXT);
CREATE TABLE behavior_records(source_day TEXT,epoch INTEGER,time_label TEXT,app_name TEXT,window_title TEXT,url TEXT,has_screenshot INTEGER,screenshot_path TEXT,ingested_at TEXT,classification TEXT,classification_policy_version INTEGER);
CREATE TABLE today_snapshots(day_key TEXT,payload BLOB,updated_at TEXT);
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY,title TEXT,summary TEXT,payload_json TEXT);
CREATE TABLE foreign_state(value TEXT); INSERT INTO foreign_state VALUES('exact');
SQL
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot" >/dev/null
    local phase initial advanced task_id
    for phase in fresh stale missing; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        "$SCRIPT_PATH" prepare "$database" "$source" >/dev/null
        "$SCRIPT_PATH" simulate-invalid-bootstrap "$database" "$source" >/dev/null
        initial="$(jq -r .initialElapsed "$marker")"; advanced="$(jq -r .advancedElapsed "$marker")"; task_id="$TASK_ID"
        sqlite3 "$database" "INSERT INTO behavior_records VALUES('$day',CAST(strftime('%s','now') AS INTEGER)-30,'$PREFIX-fresh','Terminal','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$now','work',1); INSERT INTO today_snapshots VALUES('$day',json_object('activeTask',json_object('taskID','$task_id'),'taskRows',json_array(json_object('taskID','$task_id','state','active','elapsedMinutes',$initial))),'$now');"
        "$SCRIPT_PATH" assert-control "$database" "$source" >/dev/null
        "$SCRIPT_PATH" source-state "$phase" "$database" "$source" >/dev/null
        "$SCRIPT_PATH" advance "$database" "$source" >/dev/null
        sqlite3 "$database" "UPDATE today_snapshots SET payload=json_set(payload,'$.taskRows[0].elapsedMinutes',$advanced);"
        "$SCRIPT_PATH" assert-result "$phase" "$database" "$source" >/dev/null
    done
    sqlite3 "$database" "UPDATE task_execution_states SET state='paused' WHERE task_id='$TASK_ID';"
    expect_failure "task loss" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    sqlite3 "$database" "UPDATE task_execution_states SET state='active' WHERE task_id='$TASK_ID';"
    sqlite3 "$database" "INSERT INTO task_activity_intervals(task_id,started_at,ended_at) SELECT task_id,started_at,NULL FROM task_activity_intervals WHERE task_id='$TASK_ID' LIMIT 1;"
    expect_failure "duplicate intervals" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    sqlite3 "$database" "DELETE FROM task_activity_intervals WHERE id=(SELECT MAX(id) FROM task_activity_intervals WHERE task_id='$TASK_ID'); UPDATE today_snapshots SET payload=json_set(payload,'$.taskRows[0].elapsedMinutes',0);"
    expect_failure "elapsed reset" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_set(payload,'$.taskRows[0].elapsedMinutes',19),payload=json_set(payload,'$.leak','$PRIVATE_TITLE');"
    expect_failure "privacy leakage" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_remove(payload,'$.leak'); INSERT INTO today_snapshots SELECT * FROM today_snapshots LIMIT 1;"
    expect_failure "duplicate snapshot" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    sqlite3 "$database" "DROP TABLE task_execution_states;"
    expect_failure "SQL/schema failure" "$SCRIPT_PATH" assert-result missing "$database" "$source"
    expect_failure "wrong source root" "$SCRIPT_PATH" prepare "$database" "$qa_root/other/days"
    expect_failure "real Screenwatch path" "$SCRIPT_PATH" prepare "$database" "$HOME/screenwatch/days"
    expect_failure "real database path" "$SCRIPT_PATH" prepare "$HOME/Library/Application Support/Zoid 666/zoid-coach.sqlite" "$source"
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    print tampered > "$qa_root/tampered"
    expect_failure "cleanup mismatch" "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    rm "$qa_root/tampered"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    [[ "$(sqlite3 "$database" 'SELECT value FROM foreign_state;')" == exact ]] || fail "foreign baseline not restored"
    print -- "PASS: ZC-062-004 fixture self-test covers fresh/stale/missing, invalid Reminder bootstrap, singular interval, elapsed advance/reset, task loss boundary, roots, SQL, privacy, duplicates, relaunch state, and exact restore"
)

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
command -v jq >/dev/null || fail "jq is required"
readonly COMMAND="${1:-}"; shift || true
case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        (( $# == 2 )) || usage; "${COMMAND//-/_}" "$1" "$2" ;;
    prepare|simulate-invalid-bootstrap|advance|assert-control)
        (( $# == 2 )) || usage
        readonly DATABASE="${1:A}"
        readonly SCREENWATCH_ROOT="${2:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly MARKER="${DATABASE:h:h:h}/ZC062004/tracking.json"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "${COMMAND//-/_}" ;;
    source-state|assert-result)
        (( $# == 3 )) || usage
        readonly PHASE="$1"
        readonly DATABASE="${2:A}"
        readonly SCREENWATCH_ROOT="${3:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly MARKER="${DATABASE:h:h:h}/ZC062004/tracking.json"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "${COMMAND//-/_}" ;;
    self-test)
        (( $# == 0 )) || usage; self_test ;;
    *) usage ;;
esac
