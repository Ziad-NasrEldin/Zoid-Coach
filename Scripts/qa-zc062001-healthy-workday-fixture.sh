#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc062001"
readonly TASK_ID="$PREFIX-planned-task"
readonly TIME_LABEL="$PREFIX-fresh-observation"
readonly PRIVATE_TITLE="$PREFIX-private-window"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"
readonly FRESHNESS_LIMIT=240

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|assert-result|self-test> ..."
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
    [[ "$root" == /private/tmp/zoid-666-zc062001-* ]] \
        || fail "refusing non-ZC-062-001 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / ]] || fail "refusing unsafe root"
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
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$root" && ! -e "$snapshot" ]] || fail "root or snapshot state is invalid"
    [[ "$snapshot" == /private/tmp/zoid-666-zc062001-* ]] || fail "unsafe snapshot namespace"
    /usr/bin/ditto "$root" "$snapshot"
    print -r -- "$root" > "$snapshot.zc062001-target"
    root_manifest "$snapshot" > "$snapshot.zc062001-manifest"
    [[ -s "$snapshot.zc062001-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$snapshot" && -f "$snapshot.zc062001-target" ]] || fail "snapshot is incomplete"
    [[ "$(<"$snapshot.zc062001-target")" == "$root" ]] || fail "snapshot target mismatch"
    rm -rf -- "$root"
    /usr/bin/ditto "$snapshot" "$root"
    root_manifest "$root" > "$snapshot.zc062001-restored-manifest"
    cmp -s "$snapshot.zc062001-manifest" "$snapshot.zc062001-restored-manifest" \
        || fail "restored root differs from byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local root="${1:A}" snapshot="${2:A}" current
    assert_safe_root "$root"
    current="$(mktemp /private/tmp/zoid-666-zc062001-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$root" > "$current"
    cmp -s "$snapshot.zc062001-manifest" "$current" \
        || fail "current root differs from byte baseline"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated QA root matches the byte-exact baseline"
}

require_database() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    local table
    for table in source_tasks daily_plan_entries today_snapshots processing_checkpoints behavior_records prompt_episodes; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 1 "$table production table"
    done
    assert_scalar "PRAGMA integrity_check;" ok "canonical database integrity"
}

prepare() {
    require_database
    mkdir -p "$DAY_DIRECTORY"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
DELETE FROM today_snapshots WHERE day_key = '$LOCAL_DAY';
DELETE FROM behavior_records WHERE time_label = '$TIME_LABEL';
INSERT INTO source_tasks(
    source_id, title, due_at, priority, is_completed, updated_at, source_kind
) VALUES (
    '$TASK_ID', 'Prepare the approved client brief', NULL, 9, 0, '$TIMESTAMP', 'local'
);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 1, 1, 45, '$TIMESTAMP'
);
COMMIT;
SQL
    print -r -- "{\"t\":\"$TIME_LABEL\",\"epoch\":$OBSERVATION_EPOCH,\"app\":\"Safari\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" > "$LOG_FILE"
    touch "$LOG_FILE"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key='$LOCAL_DAY' AND reminder_id='$TASK_ID' AND is_main_objective=1;" 1 "one durable approved plan entry"
    print -- "OBSERVATION_EPOCH=$OBSERVATION_EPOCH"
    print -- "PASS: prepared approved planned day and fresh private Screenwatch observation"
}

iso_epoch() {
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
        || fail "invalid ISO-8601 freshness timestamp"
}

assert_result() {
    require_database
    [[ -f "$LOG_FILE" ]] || fail "fresh Screenwatch log is missing"
    local now_epoch observation_epoch log_age heartbeat heartbeat_epoch heartbeat_age ingested_epoch lag
    now_epoch="$(date +%s)"
    observation_epoch="$(sed -nE 's/.*"epoch":([0-9]+).*/\1/p' "$LOG_FILE" | tail -1)"
    [[ "$observation_epoch" == <-> ]] || fail "Screenwatch epoch is missing"
    log_age=$((now_epoch - $(stat -f %m "$LOG_FILE")))
    (( log_age >= 0 && log_age <= FRESHNESS_LIMIT )) || fail "Screenwatch file is stale"
    (( now_epoch - observation_epoch >= 0 && now_epoch - observation_epoch <= FRESHNESS_LIMIT )) \
        || fail "Screenwatch observation is stale or future-dated"

    heartbeat="$(scalar "SELECT last_success_at_utc FROM processing_checkpoints WHERE source_id='agent-runtime';")"
    [[ -n "$heartbeat" ]] || fail "agent heartbeat is missing"
    heartbeat_epoch="$(iso_epoch "$heartbeat")"
    heartbeat_age=$((now_epoch - heartbeat_epoch))
    (( heartbeat_age >= 0 && heartbeat_age <= FRESHNESS_LIMIT )) || fail "agent heartbeat is stale"

    ingested_epoch="$(scalar "SELECT epoch FROM behavior_records WHERE time_label='$TIME_LABEL';")"
    [[ "$ingested_epoch" == <-> ]] || fail "owned Screenwatch observation was not ingested exactly once"
    lag=$((observation_epoch - ingested_epoch))
    (( lag >= 0 && lag <= FRESHNESS_LIMIT )) || fail "canonical ingestion is behind Screenwatch"

    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label='$TIME_LABEL';" 1 "exactly one ingested observation"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key='$LOCAL_DAY' AND reminder_id='$TASK_ID' AND is_main_objective=1;" 1 "approved plan survived helper and relaunch"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$TASK_ID' AND is_completed=0;" 1 "planned task survived helper and relaunch"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" 1 "one canonical Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY' AND json_extract(CAST(payload AS TEXT),'$.planningStatus.mode')='planning';" 1 "planned day snapshot"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.taskRows') WHERE day_key='$LOCAL_DAY' AND json_extract(value,'$.taskID')='$TASK_ID';" 1 "planned task is user-visible"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND json_extract(value,'$.sourceID')='reminders' AND json_extract(value,'$.state')='available';" 1 "Reminders is available"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND json_extract(value,'$.sourceID')='screenwatch' AND json_extract(value,'$.state')='current';" 1 "Screenwatch is current"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND json_extract(value,'$.sourceID')='agent' AND json_extract(value,'$.state')='running';" 1 "agent is running"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND (lower(COALESCE(json_extract(value,'$.state'),'')) IN ('stale','limited','blocked','missing','unknown','not_connected') OR lower(COALESCE(json_extract(value,'$.detail'),'')) LIKE '%stale%');" 0 "no stale or limited source fallback"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY' AND COALESCE(json_extract(CAST(payload AS TEXT),'$.coverage.isLimited'),0) IN (1,'true');" 0 "no limited coverage fallback"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE CAST(payload AS TEXT) LIKE '%$PRIVATE_TITLE%' OR CAST(payload AS TEXT) LIKE '%$PRIVATE_URL%';" 0 "private Screenwatch evidence excluded from Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE title LIKE '%$PRIVATE_TITLE%' OR summary LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_TITLE%' OR title LIKE '%$PRIVATE_URL%' OR summary LIKE '%$PRIVATE_URL%' OR payload_json LIKE '%$PRIVATE_URL%';" 0 "private Screenwatch evidence excluded from prompts"
    print -- "PASS: approved day, five health rows, freshness, ownership, ingestion, privacy, and relaunch persistence are exact"
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "validator accepted $label"; fi
}

self_test() (
    local seed qa_root snapshot database screenwatch local_day log timestamp observation_epoch
    seed="$(mktemp -d /private/tmp/zoid-666-zc062001-self-test.XXXXXX)"
    qa_root="$seed-runtime"
    snapshot="$seed-snapshot"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    screenwatch="$qa_root/Screenwatch/days"
    local_day="$(date +%F)"
    log="$screenwatch/$local_day/log.jsonl"
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    observation_epoch=$(( $(date +%s) - 30 ))
    mkdir -p "${database:h}" "${log:h}"
    trap 'rm -rf -- "$seed" "$qa_root" "$snapshot" "$snapshot.zc062001-target" "$snapshot.zc062001-manifest" "$snapshot.zc062001-restored-manifest"' EXIT
    sqlite3 -batch "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY,title TEXT,due_at TEXT,priority INTEGER,is_completed INTEGER,updated_at TEXT,source_kind TEXT);
CREATE TABLE daily_plan_entries(day_key TEXT,reminder_id TEXT,rank INTEGER,is_main_objective INTEGER,estimate_minutes INTEGER,updated_at TEXT);
CREATE TABLE today_snapshots(day_key TEXT,payload BLOB,updated_at TEXT);
CREATE TABLE processing_checkpoints(source_id TEXT PRIMARY KEY,last_success_at_utc TEXT);
CREATE TABLE behavior_records(source_day TEXT,epoch INTEGER,time_label TEXT,app_name TEXT,window_title TEXT,url TEXT,has_screenshot INTEGER,screenshot_path TEXT,ingested_at TEXT,classification TEXT,classification_policy_version INTEGER);
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY,title TEXT,summary TEXT,payload_json TEXT);
CREATE TABLE foreign_state(id TEXT PRIMARY KEY,value TEXT);
INSERT INTO foreign_state VALUES('preserve','exact');
SQL
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" prepare "$database" "$screenwatch" >/dev/null
    observation_epoch="$(sed -nE 's/.*"epoch":([0-9]+).*/\1/p' "$log")"
    sqlite3 -batch "$database" <<SQL
INSERT INTO behavior_records VALUES('$local_day',$observation_epoch,'$TIME_LABEL','Safari','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$timestamp','unknown',1);
INSERT INTO processing_checkpoints VALUES('agent-runtime','$timestamp');
INSERT INTO today_snapshots VALUES('$local_day',json_object(
  'planningStatus',json_object('mode','planning'),
  'taskRows',json_array(json_object('taskID','$TASK_ID')),
  'sources',json_array(
    json_object('sourceID','reminders','state','available'),
    json_object('sourceID','screenwatch','state','current'),
    json_object('sourceID','agent','state','running')
  )
),'$timestamp');
SQL
    "$SCRIPT_PATH" assert-result "$database" "$screenwatch" >/dev/null

    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_set(payload,'$.sources[0].state','blocked');"
    expect_failure "one-source unhealthy" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_remove(json_set(payload,'$.sources[0].state','available'),'$.sources[1]');"
    expect_failure "one-source missing" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_insert(payload,'$.sources[#]',json_object('sourceID','screenwatch','state','current')); UPDATE processing_checkpoints SET last_success_at_utc='2000-01-01T00:00:00Z';"
    expect_failure "stale heartbeat" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "UPDATE processing_checkpoints SET last_success_at_utc='$timestamp'; DELETE FROM behavior_records WHERE time_label='$TIME_LABEL';"
    expect_failure "missing ingestion" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "INSERT INTO behavior_records VALUES('$local_day',$observation_epoch,'$TIME_LABEL','Safari','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$timestamp','unknown',1); DELETE FROM daily_plan_entries WHERE reminder_id='$TASK_ID';"
    expect_failure "relaunch plan loss" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "INSERT INTO daily_plan_entries VALUES('$local_day','$TASK_ID',1,1,45,'$timestamp'); INSERT INTO today_snapshots SELECT * FROM today_snapshots LIMIT 1;"
    expect_failure "duplicate snapshot" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "DELETE FROM today_snapshots WHERE rowid NOT IN (SELECT MIN(rowid) FROM today_snapshots); UPDATE today_snapshots SET payload=json_set(payload,'$.leak','$PRIVATE_TITLE');"
    expect_failure "privacy leakage" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"
    sqlite3 "$database" "DROP TABLE behavior_records;"
    expect_failure "SQL failure" "$SCRIPT_PATH" assert-result "$database" "$screenwatch"

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    print -r -- "tampered" > "$qa_root/foreign.txt"
    expect_failure "cleanup mismatch" "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    rm -f "$qa_root/foreign.txt"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    expect_failure "unsafe cleanup root" "$SCRIPT_PATH" assert-root-restored /private/tmp "$snapshot"
    [[ "$(sqlite3 "$database" "SELECT value FROM foreign_state WHERE id='preserve';")" == exact ]] \
        || fail "foreign baseline state was not restored"
    print -- "PASS: ZC-062-001 fixture self-test covers healthy, unhealthy, stale, missing, relaunch, duplicate, SQL, privacy, cleanup, and byte restoration"
)

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
readonly COMMAND="${1:-}"
shift || true
case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        (( $# == 2 )) || usage
        "${COMMAND//-/_}" "$1" "$2"
        ;;
    prepare|assert-result)
        (( $# == 2 )) || usage
        readonly DATABASE="${1:A}"
        readonly SCREENWATCH_ROOT="${2:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        readonly OBSERVATION_EPOCH=$(( $(date +%s) - 30 ))
        "${COMMAND//-/_}"
        ;;
    self-test)
        (( $# == 0 )) || usage
        self_test
        ;;
    *) usage ;;
esac
