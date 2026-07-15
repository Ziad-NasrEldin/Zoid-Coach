#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc062003"
readonly TASK_ID="$PREFIX-active-technical"
readonly TASK_TITLE="QA ZC-062-003 active technical task"
readonly PROMPT_ID="$PREFIX-strong-gaming-drift"
readonly TIME_PREFIX="$PREFIX-gaming-"
readonly PRIVATE_TITLE="$PREFIX-private-window"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"
readonly STRONG_TITLE="Is this gaming intentional?"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|assert-healthy|outage|assert-outage|self-test> ..."
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
    [[ "$root" == /private/tmp/zoid-666-zc062003-* ]] || fail "refusing non-ZC-062-003 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / && ! -L "$root" ]] || fail "refusing unsafe or symlink root"
}

assert_owned_paths() {
    local qa_root="${DATABASE:h:h:h}"
    assert_safe_root "$qa_root"
    [[ "${DATABASE:A}" == "$qa_root/Application Support/Zoid 666/zoid-coach.sqlite" ]] || fail "wrong database root"
    [[ "${SCREENWATCH_ROOT:A}" == "$qa_root/Screenwatch/days" ]] || fail "wrong Screenwatch source root"
    [[ "${OS_STATE:A}" == "$qa_root/OS Fixtures/state.json" ]] || fail "wrong OS fixture root"
    [[ ! -L "$SCREENWATCH_ROOT" && ! -L "$OS_STATE" ]] || fail "symlink-owned runtime path rejected"
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
    [[ -d "$root" && ! -e "$snapshot" && "$snapshot" == /private/tmp/zoid-666-zc062003-* ]] || fail "invalid snapshot state"
    /usr/bin/ditto "$root" "$snapshot"
    print -r -- "$root" > "$snapshot.zc062003-target"
    root_manifest "$snapshot" > "$snapshot.zc062003-manifest"
    [[ -s "$snapshot.zc062003-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local root="${1:A}" snapshot="${2:A}"
    assert_safe_root "$root"
    [[ -d "$snapshot" && -f "$snapshot.zc062003-target" ]] || fail "snapshot is incomplete"
    [[ "$(<"$snapshot.zc062003-target")" == "$root" ]] || fail "snapshot target mismatch"
    rm -rf -- "$root"
    /usr/bin/ditto "$snapshot" "$root"
    root_manifest "$root" > "$snapshot.zc062003-restored"
    cmp -s "$snapshot.zc062003-manifest" "$snapshot.zc062003-restored" || fail "restored root differs from byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local root="${1:A}" snapshot="${2:A}" current
    assert_safe_root "$root"
    current="$(mktemp /private/tmp/zoid-666-zc062003-manifest.XXXXXX)"
    trap "rm -f -- ${current:q}" EXIT
    root_manifest "$root" > "$current"
    cmp -s "$snapshot.zc062003-manifest" "$current" || fail "cleanup mismatch"
    print -- "PASS: isolated QA root matches byte-exact baseline"
}

require_runtime() {
    assert_owned_paths
    [[ -f "$DATABASE" && -f "$OS_STATE" ]] || fail "database or OS fixture state is missing"
    jq -e '.notifications | type == "array"' "$OS_STATE" >/dev/null || fail "invalid OS notification fixture"
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records prompt_episodes baseline_observation_days today_snapshots; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 1 "$table production table"
    done
    assert_scalar "PRAGMA integrity_check;" ok "database integrity"
}

complete_baseline() {
    sqlite3 "$DATABASE" <<SQL
WITH RECURSIVE day(n) AS (VALUES(0) UNION ALL SELECT n+1 FROM day WHERE n<6)
INSERT INTO baseline_observation_days(local_day,observed_minutes,work_minutes,gaming_minutes,distracting_minutes,unknown_minutes,eligible_drift_count,coverage,recorded_at_utc)
SELECT date('2020-01-01','+'||n||' days'),60,45,0,0,15,0,'complete','$TIMESTAMP' FROM day
WHERE true
ON CONFLICT(local_day) DO UPDATE SET observed_minutes=60,work_minutes=45,coverage='complete',recorded_at_utc='$TIMESTAMP';
SQL
}

seed_notification() {
    local notification_state="$1" delivered_at=null temporary="$OS_STATE.$$.tmp"
    [[ "$notification_state" == delivered ]] && delivered_at=$(( $(date +%s) - 978307200 ))
    jq --arg id "$PROMPT_ID" --arg notificationState "$notification_state" --argjson deliveredAt "$delivered_at" '
        .notifications |= map(select(.id != $id and .desired.promptID != $id))
        | .notifications += [{id:$id,desired:{category:"GAMING_DRIFT",title:"Is this gaming intentional?",body:"Strong eligible control",promptID:$id},status:$notificationState,deliveredAt:$deliveredAt,actionIdentifier:null,respondedAt:null}]
    ' "$OS_STATE" > "$temporary"
    mv "$temporary" "$OS_STATE"
}

prepare() {
    require_runtime
    [[ "$MODE" == scheduled || "$MODE" == delivered || "$MODE" == no-eligible-baseline || "$MODE" == existing-handled ]] || fail "unsupported prepare mode"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id<>'$TASK_ID';" 0 "foreign active interval"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key='$LOCAL_DAY' AND reminder_id<>'$TASK_ID';" 0 "foreign planned-day entry"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day='$LOCAL_DAY' AND time_label NOT LIKE '$TIME_PREFIX%';" 0 "foreign current-day behavior evidence"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented') AND id<>'$PROMPT_ID';" 0 "foreign unresolved strong prompt"
    mkdir -p "$DAY_DIRECTORY"
    sqlite3 "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_plan_entries WHERE reminder_id='$TASK_ID';
DELETE FROM task_activity_intervals WHERE task_id='$TASK_ID';
DELETE FROM task_execution_states WHERE task_id='$TASK_ID';
DELETE FROM source_tasks WHERE source_id='$TASK_ID';
DELETE FROM behavior_records WHERE time_label LIKE '$TIME_PREFIX%';
DELETE FROM prompt_episodes WHERE id LIKE '$PREFIX-%';
DELETE FROM today_snapshots WHERE day_key='$LOCAL_DAY';
INSERT INTO source_tasks(source_id,title,priority,is_completed,updated_at,source_kind,declared_context)
VALUES('$TASK_ID','$TASK_TITLE',9,0,'$TIMESTAMP','local','technical');
INSERT INTO daily_plan_entries(day_key,reminder_id,rank,is_main_objective,estimate_minutes,updated_at)
VALUES('$LOCAL_DAY','$TASK_ID',1,1,45,'$TIMESTAMP');
INSERT INTO task_execution_states(task_id,state,updated_at) VALUES('$TASK_ID','active','$TIMESTAMP');
INSERT INTO task_activity_intervals(task_id,started_at,ended_at) VALUES('$TASK_ID',datetime('now','-12 minutes'),NULL);
WITH RECURSIVE minute(n) AS (VALUES(0) UNION ALL SELECT n+1 FROM minute WHERE n<9)
INSERT INTO behavior_records(source_day,epoch,time_label,app_name,window_title,url,has_screenshot,screenshot_path,ingested_at,classification,classification_policy_version)
SELECT '$LOCAL_DAY',$FIRST_EPOCH+(n*60),'$TIME_PREFIX'||n,'Steam','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'$TIMESTAMP','gaming',1 FROM minute;
INSERT INTO prompt_episodes(id,decision_key,prompt_type,state,title,summary,action_token,payload_json,created_at_utc,expires_at_utc)
VALUES('$PROMPT_ID','gaming-drift:$LOCAL_DAY:$FIRST_EPOCH','GAMING_DRIFT','queued','$STRONG_TITLE','Return to $TASK_TITLE.','$PREFIX-action','{"actions":[{"kind":"return_to_active_task","title":"Return to task","role":"primary","requiresConfirmation":false}],"payload":{"taskID":"$TASK_ID"}}','$TIMESTAMP','2999-01-01T00:00:00Z');
INSERT INTO today_snapshots(day_key,payload,updated_at)
VALUES('$LOCAL_DAY',json_object('activeTask',json_object('taskID','$TASK_ID'),'coverage',json_object('isLimited',json('false'),'explanation','Screenwatch coverage is current.'),'sources',json_array(json_object('sourceID','screenwatch','state','current','detail','Screenwatch coverage is current.'))),'$TIMESTAMP');
COMMIT;
SQL
    complete_baseline
    if [[ "$MODE" == no-eligible-baseline ]]; then
        sqlite3 "$DATABASE" "DELETE FROM baseline_observation_days WHERE local_day BETWEEN '2020-01-01' AND '2020-01-07';"
    elif [[ "$MODE" == existing-handled ]]; then
        sqlite3 "$DATABASE" <<SQL
INSERT INTO prompt_episodes(id,decision_key,prompt_type,state,title,summary,action_token,payload_json,created_at_utc,resolved_at_utc,resolution_origin,resolution_reason)
VALUES('$PREFIX-handled','gaming-drift:handled','GAMING_DRIFT','resolved','Handled earlier','Handled earlier','$PREFIX-handled-action','{}','$TIMESTAMP','$TIMESTAMP','user','return_to_task');
SQL
    fi
    : > "$LOG_FILE"
    local n epoch
    for n in {0..9}; do
        epoch=$((FIRST_EPOCH + n * 60))
        print -r -- "{\"t\":\"$TIME_PREFIX$n\",\"epoch\":$epoch,\"app\":\"Steam\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" >> "$LOG_FILE"
    done
    touch "$LOG_FILE"
    seed_notification "$([[ "$MODE" == delivered ]] && print delivered || print scheduled)"
    print -- "PASS: prepared $MODE healthy eligible control"
}

assert_preserved_eligibility() {
    assert_scalar "SELECT COUNT(*) FROM baseline_observation_days WHERE local_day BETWEEN '2020-01-01' AND '2020-01-07' AND coverage='complete';" 7 "seven complete baseline days"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key='$LOCAL_DAY' AND reminder_id='$TASK_ID' AND is_main_objective=1;" 1 "planned priority task"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id='$TASK_ID' AND declared_context='technical' AND is_completed=0;" 1 "technical task"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id='$TASK_ID' AND state='active';" 1 "active task state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id='$TASK_ID' AND ended_at IS NULL;" 1 "one open interval"
}

assert_healthy() {
    require_runtime
    assert_preserved_eligibility
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_PREFIX%' AND classification='gaming';" 10 "eligible gaming evidence"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id='$PROMPT_ID' AND state IN ('queued','presented') AND title='$STRONG_TITLE';" 1 "one healthy eligible strong prompt"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND json_extract(CAST(payload AS TEXT),'$.activeTask.taskID')='$TASK_ID' AND json_extract(value,'$.sourceID')='screenwatch' AND json_extract(value,'$.state')='current';" 1 "healthy current Today control"
    jq -e --arg id "$PROMPT_ID" '[.notifications[]|select(.id==$id or .desired.promptID==$id)]|length==1' "$OS_STATE" >/dev/null || fail "healthy strong notification missing"
    print -- "PASS: healthy source has preserved eligibility, one strong prompt, and one notification"
}

outage() {
    require_runtime
    assert_healthy >/dev/null
    case "$PHASE" in
        stale)
            sqlite3 "$DATABASE" "UPDATE behavior_records SET epoch=epoch-1200 WHERE time_label LIKE '$TIME_PREFIX%';"
            local temporary="$LOG_FILE.$$.tmp"
            jq -c '.epoch -= 1200' "$LOG_FILE" > "$temporary"
            mv "$temporary" "$LOG_FILE"
            touch -t 200001010000 "$LOG_FILE"
            ;;
        missing)
            sqlite3 "$DATABASE" "DELETE FROM behavior_records WHERE time_label LIKE '$TIME_PREFIX%';"
            rm -f -- "$LOG_FILE"
            ;;
        *) fail "unsupported outage phase: $PHASE" ;;
    esac
    print -- "PASS: controlled only $PHASE isolated Screenwatch evidence"
}

assert_outage() {
    require_runtime
    assert_preserved_eligibility
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id='$PROMPT_ID' AND state='dismissed' AND resolution_origin='system' AND resolution_reason='screenwatch_evidence_invalid';" 1 "exact system withdrawal reason"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented');" 0 "no unresolved strong prompt"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" 1 "one Today snapshot"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.sources') WHERE day_key='$LOCAL_DAY' AND json_extract(CAST(payload AS TEXT),'$.activeTask.taskID')='$TASK_ID' AND json_extract(CAST(payload AS TEXT),'$.coverage.isLimited') IN (1,'true') AND json_extract(value,'$.sourceID')='screenwatch' AND json_extract(value,'$.state')='limited';" 1 "visible source warning state"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE CAST(payload AS TEXT) LIKE '%$STRONG_TITLE%' OR CAST(payload AS TEXT) LIKE '%$PRIVATE_TITLE%' OR CAST(payload AS TEXT) LIKE '%$PRIVATE_URL%';" 0 "no strong or private wording in Today"
    jq -e --arg id "$PROMPT_ID" '[.notifications[]|select(.id==$id or .desired.promptID==$id or .desired.category=="GAMING_DRIFT")]|length==0' "$OS_STATE" >/dev/null || fail "scheduled or delivered strong notification remains"
    case "$PHASE" in
        stale)
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_PREFIX%' AND CAST(strftime('%s','now') AS INTEGER)-epoch>900;" 10 "stale evidence boundary"
            [[ -f "$LOG_FILE" ]] || fail "stale source log missing"
            ;;
        missing)
            assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_PREFIX%';" 0 "missing evidence boundary"
            [[ ! -e "$LOG_FILE" ]] || fail "missing source log remains"
            ;;
        *) fail "unsupported outage result: $PHASE" ;;
    esac
    print -- "PASS: $PHASE warning, exact suppression, notification withdrawal, preserved eligibility, and privacy are exact"
}

expect_failure() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then fail "validator accepted $label"; fi; }

self_test() (
    local qa_root snapshot database source os_state day now
    qa_root="$(mktemp -d /private/tmp/zoid-666-zc062003-self-test.XXXXXX)"
    snapshot="$qa_root-snapshot"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    source="$qa_root/Screenwatch/days"
    os_state="$qa_root/OS Fixtures/state.json"
    day="$(date +%F)"; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "${database:h}" "${os_state:h}"
    trap 'rm -rf -- "$qa_root" "$snapshot" "$snapshot.zc062003-target" "$snapshot.zc062003-manifest" "$snapshot.zc062003-restored"' EXIT
    sqlite3 "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY,title TEXT,priority INTEGER,is_completed INTEGER,updated_at TEXT,source_kind TEXT,declared_context TEXT);
CREATE TABLE daily_plan_entries(day_key TEXT,reminder_id TEXT,rank INTEGER,is_main_objective INTEGER,estimate_minutes INTEGER,updated_at TEXT);
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY,state TEXT,updated_at TEXT);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT,task_id TEXT,started_at TEXT,ended_at TEXT);
CREATE TABLE behavior_records(source_day TEXT,epoch INTEGER,time_label TEXT,app_name TEXT,window_title TEXT,url TEXT,has_screenshot INTEGER,screenshot_path TEXT,ingested_at TEXT,classification TEXT,classification_policy_version INTEGER);
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY,decision_key TEXT UNIQUE,prompt_type TEXT,state TEXT,title TEXT,summary TEXT,action_token TEXT UNIQUE,payload_json TEXT,created_at_utc TEXT,expires_at_utc TEXT,presented_at_utc TEXT,resolved_at_utc TEXT,resolution_origin TEXT,resolution_reason TEXT);
CREATE TABLE baseline_observation_days(local_day TEXT PRIMARY KEY,observed_minutes INTEGER,work_minutes INTEGER,gaming_minutes INTEGER,distracting_minutes INTEGER,unknown_minutes INTEGER,eligible_drift_count INTEGER,coverage TEXT,recorded_at_utc TEXT);
CREATE TABLE today_snapshots(day_key TEXT,payload BLOB,updated_at TEXT);
CREATE TABLE foreign_state(value TEXT); INSERT INTO foreign_state VALUES('exact');
SQL
    jq -n '{notifications:[]}' > "$os_state"
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot" >/dev/null
    local mode phase
    for mode in scheduled delivered existing-handled; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        "$SCRIPT_PATH" prepare "$mode" "$database" "$source" "$os_state" >/dev/null
        "$SCRIPT_PATH" assert-healthy "$database" "$source" "$os_state" >/dev/null
        if [[ "$mode" == existing-handled ]]; then
            [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id='$PREFIX-handled' AND state='resolved' AND resolution_origin='user';")" == 1 ]] \
                || fail "existing handled prompt was not preserved exactly"
        fi
    done
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" prepare no-eligible-baseline "$database" "$source" "$os_state" >/dev/null
    expect_failure "no eligible baseline" "$SCRIPT_PATH" assert-healthy "$database" "$source" "$os_state"
    for phase in stale missing; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        "$SCRIPT_PATH" prepare delivered "$database" "$source" "$os_state" >/dev/null
        "$SCRIPT_PATH" outage "$phase" "$database" "$source" "$os_state" >/dev/null
        sqlite3 "$database" "UPDATE prompt_episodes SET state='dismissed',resolved_at_utc='$now',resolution_origin='system',resolution_reason='screenwatch_evidence_invalid' WHERE id='$PROMPT_ID'; UPDATE today_snapshots SET payload=json_object('activeTask',json_object('taskID','$TASK_ID'),'coverage',json_object('isLimited',json('true'),'explanation','Limited coverage: Screenwatch is $phase.'),'sources',json_array(json_object('sourceID','screenwatch','state','limited','detail','Screenwatch is $phase.')));"
        jq --arg id "$PROMPT_ID" '.notifications|=map(select(.id!=$id and .desired.promptID!=$id))' "$os_state" > "$os_state.tmp" && mv "$os_state.tmp" "$os_state"
        "$SCRIPT_PATH" assert-outage "$phase" "$database" "$source" "$os_state" >/dev/null
    done
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_set(payload,'$.leak','$PRIVATE_TITLE');"
    expect_failure "privacy leakage" "$SCRIPT_PATH" assert-outage missing "$database" "$source" "$os_state"
    sqlite3 "$database" "UPDATE today_snapshots SET payload=json_remove(payload,'$.leak'); INSERT INTO today_snapshots SELECT * FROM today_snapshots LIMIT 1;"
    expect_failure "duplicate snapshot" "$SCRIPT_PATH" assert-outage missing "$database" "$source" "$os_state"
    sqlite3 "$database" "DROP TABLE prompt_episodes;"
    expect_failure "SQL/schema failure" "$SCRIPT_PATH" assert-outage missing "$database" "$source" "$os_state"
    expect_failure "wrong source" "$SCRIPT_PATH" prepare scheduled "$database" "$qa_root/other/days" "$os_state"
    expect_failure "real Screenwatch path" "$SCRIPT_PATH" prepare scheduled "$database" "$HOME/screenwatch/days" "$os_state"
    expect_failure "real database path" "$SCRIPT_PATH" prepare scheduled "$HOME/Library/Application Support/Zoid 666/zoid-coach.sqlite" "$source" "$os_state"
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    print tampered > "$qa_root/tampered"
    expect_failure "cleanup mismatch" "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    rm "$qa_root/tampered"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    [[ "$(sqlite3 "$database" 'SELECT value FROM foreign_state;')" == exact ]] || fail "foreign baseline not restored"
    print -- "PASS: ZC-062-003 fixture self-test covers healthy control, scheduled/delivered removal, stale/missing, handled, baseline, roots, SQL, privacy, duplicates, relaunch state, and exact restore"
)

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
command -v jq >/dev/null || fail "jq is required"
readonly COMMAND="${1:-}"; shift || true
case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        (( $# == 2 )) || usage; "${COMMAND//-/_}" "$1" "$2" ;;
    prepare)
        (( $# == 4 )) || usage
        readonly MODE="$1"
        readonly DATABASE="${2:A}"
        readonly SCREENWATCH_ROOT="${3:A}"
        readonly OS_STATE="${4:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$LOCAL_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        readonly FIRST_EPOCH=$(( $(date +%s) - 570 ))
        prepare ;;
    assert-healthy)
        (( $# == 3 )) || usage
        readonly DATABASE="${1:A}"
        readonly SCREENWATCH_ROOT="${2:A}"
        readonly OS_STATE="${3:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly LOG_FILE="$SCREENWATCH_ROOT/$LOCAL_DAY/log.jsonl"
        assert_healthy ;;
    outage|assert-outage)
        (( $# == 4 )) || usage
        readonly PHASE="$1"
        readonly DATABASE="${2:A}"
        readonly SCREENWATCH_ROOT="${3:A}"
        readonly OS_STATE="${4:A}"
        readonly LOCAL_DAY="$(date +%F)"
        readonly LOG_FILE="$SCREENWATCH_ROOT/$LOCAL_DAY/log.jsonl"
        "${COMMAND//-/_}" ;;
    self-test)
        (( $# == 0 )) || usage; self_test ;;
    *) usage ;;
esac
