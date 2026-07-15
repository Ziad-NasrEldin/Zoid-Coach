#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc062002"
readonly TASK_ID="$PREFIX-active-technical"
readonly BASELINE_LABEL="$PREFIX-baseline"
readonly ADVANCE_LABEL="$PREFIX-advance"
readonly PRIVATE_TITLE="$PREFIX-private-window"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"
readonly FRESHNESS_LIMIT=240

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|disrupt|assert-result|self-test> ..."
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
    [[ "$root" == /private/tmp/zoid-666-zc062002-* ]] || fail "refusing non-ZC-062-002 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / && ! -L "$root" ]] || fail "refusing unsafe or symlink root"
}

assert_owned_paths() {
    local qa_root="${DATABASE:h:h:h}"
    assert_safe_root "$qa_root"
    [[ "${DATABASE:A}" == "$qa_root/Application Support/Zoid 666/zoid-coach.sqlite" ]] \
        || fail "database is not the exact isolated QA database"
    [[ "${SCREENWATCH_ROOT:A}" == "$qa_root/Screenwatch/days" ]] \
        || fail "Screenwatch source is not owned by the same isolated QA root"
}

root_manifest() {
    local root="$1"
    [[ -d "$root" ]] || fail "root does not exist: $root"
    (
        cd "$root"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            /usr/bin/shasum -a 256 "$file"
        done
        find . -type l -print | LC_ALL=C sort | while IFS= read -r file; do
            print -r -- "SYMLINK $file -> $(readlink "$file")"
        done
    )
}

snapshot_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$root" && ! -e "$snapshot" && "$snapshot" == /private/tmp/zoid-666-zc062002-* ]] || fail "invalid snapshot state"
    /usr/bin/ditto "$root" "$snapshot"
    print -r -- "$root" > "$snapshot.zc062002-target"
    root_manifest "$snapshot" > "$snapshot.zc062002-manifest"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$snapshot" && "$(<"$snapshot.zc062002-target")" == "$root" ]] || fail "snapshot target mismatch"
    rm -rf -- "$root"
    /usr/bin/ditto "$snapshot" "$root"
    root_manifest "$root" > "$snapshot.zc062002-restored"
    cmp -s "$snapshot.zc062002-manifest" "$snapshot.zc062002-restored" || fail "restored root differs from byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local root="${1:A}" snapshot="${2:A}" current
    assert_safe_root "$root"
    current="$(mktemp /private/tmp/zoid-666-zc062002-manifest.XXXXXX)"
    trap "rm -f -- ${current:q}" EXIT
    root_manifest "$root" > "$current"
    cmp -s "$snapshot.zc062002-manifest" "$current" || fail "cleanup mismatch"
    print -- "PASS: isolated QA root matches byte-exact baseline"
}

require_database() {
    assert_owned_paths
    [[ -f "$DATABASE" ]] || fail "database does not exist"
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records today_snapshots prompt_episodes; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 1 "$table production table"
    done
    assert_scalar "PRAGMA integrity_check;" ok "database integrity"
}

prepare() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id <> '$TASK_ID';" 0 "foreign active interval"
    mkdir -p "$DAY_DIRECTORY"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_plan_entries WHERE day_key='$LOCAL_DAY';
DELETE FROM task_activity_intervals WHERE task_id='$TASK_ID';
DELETE FROM task_execution_states WHERE task_id='$TASK_ID';
DELETE FROM source_tasks WHERE source_id='$TASK_ID';
DELETE FROM today_snapshots WHERE day_key='$LOCAL_DAY';
DELETE FROM behavior_records WHERE time_label IN ('$BASELINE_LABEL','$ADVANCE_LABEL');
INSERT INTO source_tasks(source_id,title,priority,is_completed,updated_at,source_kind,declared_context)
VALUES('$TASK_ID','QA ZC-062-002 active technical task',9,0,'$TIMESTAMP','local','technical');
INSERT INTO daily_plan_entries(day_key,reminder_id,rank,is_main_objective,estimate_minutes,updated_at)
VALUES('$LOCAL_DAY','$TASK_ID',1,1,45,'$TIMESTAMP');
INSERT INTO task_execution_states(task_id,state,updated_at) VALUES('$TASK_ID','active','$TIMESTAMP');
INSERT INTO task_activity_intervals(task_id,started_at,ended_at) VALUES('$TASK_ID',datetime('now','-2 minutes'),NULL);
COMMIT;
SQL
    print -r -- "{\"t\":\"$BASELINE_LABEL\",\"epoch\":$(( $(date +%s) - 60 )),\"app\":\"Safari\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" > "$LOG_FILE"
    touch "$LOG_FILE"
    print -- "PASS: prepared one active technical task and isolated baseline stream"
}

disrupt() {
    require_database
    case "$PHASE" in
        fresh)
            print -r -- "{\"t\":\"$ADVANCE_LABEL\",\"epoch\":$(( $(date +%s) - 10 )),\"app\":\"Terminal\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" >> "$LOG_FILE"
            touch "$LOG_FILE"
            ;;
        stale)
            [[ -f "$LOG_FILE" ]] || fail "isolated log is missing before stale transition"
            touch -t 200001010000 "$LOG_FILE"
            ;;
        missing)
            [[ -f "$LOG_FILE" ]] || fail "isolated log is missing before controlled removal"
            rm -f -- "$LOG_FILE"
            ;;
        *) fail "unsupported phase: $PHASE" ;;
    esac
    print -- "PASS: applied $PHASE only to isolated Screenwatch source"
}

assert_result() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$TASK_ID' AND is_completed=0 AND declared_context='technical';" 1 "active technical task"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id='$TASK_ID' AND state='active';" 1 "active execution state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;" 1 "one open activity interval"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" 1 "one canonical Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY' AND json_extract(CAST(payload AS TEXT),'$.activeTask.taskID')='$TASK_ID';" 1 "active task persisted in Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label='$BASELINE_LABEL';" 1 "baseline ingestion"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE CAST(payload AS TEXT) LIKE '%$PRIVATE_TITLE%' OR CAST(payload AS TEXT) LIKE '%$PRIVATE_URL%';" 0 "private evidence excluded from Today"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE title LIKE '%$PRIVATE_TITLE%' OR summary LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_URL%';" 0 "private evidence excluded from prompts"
    case "$PHASE" in
        fresh)
            [[ -f "$LOG_FILE" ]] || fail "fresh stream missing"
            (( $(date +%s) - $(stat -f %m "$LOG_FILE") <= FRESHNESS_LIMIT )) || fail "fresh stream accepted as stale"
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label='$ADVANCE_LABEL';" 1 "fresh advance ingestion"
            ;;
        stale)
            [[ -f "$LOG_FILE" ]] || fail "stale stream missing"
            (( $(date +%s) - $(stat -f %m "$LOG_FILE") > FRESHNESS_LIMIT )) || fail "stale stream accepted as fresh"
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label='$ADVANCE_LABEL';" 1 "no duplicate ingestion after stale transition"
            ;;
        missing)
            [[ ! -e "$LOG_FILE" ]] || fail "missing stream still exists"
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label='$ADVANCE_LABEL';" 1 "no duplicate ingestion after missing transition"
            ;;
        *) fail "unsupported phase: $PHASE" ;;
    esac
    print -- "PASS: $PHASE stream state leaves the active task, open interval, snapshot, privacy, and ingestion exact"
}

expect_failure() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then fail "validator accepted $label"; fi; }

self_test() (
    local qa_root snapshot database screenwatch day log now
    qa_root="$(mktemp -d /private/tmp/zoid-666-zc062002-self-test.XXXXXX)"
    snapshot="$qa_root-snapshot"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    screenwatch="$qa_root/Screenwatch/days"
    day="$(date +%F)"
    log="$screenwatch/$day/log.jsonl"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "${database:h}"
    trap 'rm -rf -- "$qa_root" "$snapshot" "$snapshot.zc062002-target" "$snapshot.zc062002-manifest" "$snapshot.zc062002-restored"' EXIT
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
    "$SCRIPT_PATH" prepare "$database" "$screenwatch" >/dev/null
    sqlite3 "$database" "INSERT INTO behavior_records VALUES('$day',1,'$BASELINE_LABEL','Safari','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$now',NULL,NULL); INSERT INTO today_snapshots VALUES('$day',json_object('activeTask',json_object('taskID','$TASK_ID')),'$now');"
    "$SCRIPT_PATH" disrupt fresh "$database" "$screenwatch" >/dev/null
    sqlite3 "$database" "INSERT INTO behavior_records VALUES('$day',2,'$ADVANCE_LABEL','Terminal','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$now',NULL,NULL);"
    "$SCRIPT_PATH" assert-result fresh "$database" "$screenwatch" >/dev/null
    "$SCRIPT_PATH" disrupt stale "$database" "$screenwatch" >/dev/null
    "$SCRIPT_PATH" assert-result stale "$database" "$screenwatch" >/dev/null
    "$SCRIPT_PATH" disrupt missing "$database" "$screenwatch" >/dev/null
    "$SCRIPT_PATH" assert-result missing "$database" "$screenwatch" >/dev/null
    sqlite3 "$database" "UPDATE task_execution_states SET state='paused' WHERE task_id='$TASK_ID';"
    expect_failure "active task loss" "$SCRIPT_PATH" assert-result missing "$database" "$screenwatch"
    sqlite3 "$database" "UPDATE task_execution_states SET state='active'; UPDATE today_snapshots SET payload=json_set(payload,'$.leak','$PRIVATE_TITLE');"
    expect_failure "privacy leak" "$SCRIPT_PATH" assert-result missing "$database" "$screenwatch"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_remove(payload,'$.leak'); INSERT INTO today_snapshots SELECT * FROM today_snapshots LIMIT 1;"
    expect_failure "duplicate snapshot" "$SCRIPT_PATH" assert-result missing "$database" "$screenwatch"
    sqlite3 "$database" "DROP TABLE behavior_records;"
    expect_failure "SQL/schema failure" "$SCRIPT_PATH" assert-result missing "$database" "$screenwatch"
    expect_failure "wrong source root" "$SCRIPT_PATH" prepare "$database" "$qa_root/other/days"
    expect_failure "real Screenwatch path" "$SCRIPT_PATH" prepare "$database" "$HOME/screenwatch/days"
    expect_failure "real database path" "$SCRIPT_PATH" prepare "$HOME/Library/Application Support/Zoid 666/zoid-coach.sqlite" "$screenwatch"
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    print tampered > "$qa_root/tampered"
    expect_failure "cleanup mismatch" "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    rm "$qa_root/tampered"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    [[ "$(sqlite3 "$database" 'SELECT value FROM foreign_state;')" == exact ]] || fail "foreign state not restored"
    print -- "PASS: ZC-062-002 fixture self-test covers fresh, stale, missing, active loss, wrong roots, SQL, privacy, duplicates, relaunch state, and exact restore"
)

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
readonly COMMAND="${1:-}"
shift || true
case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        (( $# == 2 )) || usage
        "${COMMAND//-/_}" "$1" "$2"
        ;;
    prepare)
        (( $# == 2 )) || usage
        readonly DATABASE="${1:A}"
        readonly SCREENWATCH_ROOT="${2:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        prepare
        ;;
    disrupt|assert-result)
        (( $# == 3 )) || usage
        readonly PHASE="$1"
        readonly DATABASE="${2:A}"
        readonly SCREENWATCH_ROOT="${3:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "${COMMAND//-/_}"
        ;;
    self-test)
        (( $# == 0 )) || usage
        self_test
        ;;
    *) usage ;;
esac
