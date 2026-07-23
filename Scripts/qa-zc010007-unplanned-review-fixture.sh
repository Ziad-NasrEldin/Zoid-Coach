#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly COMMAND="${1:-}"
readonly STATE="${2:-}"
readonly DATABASE="${3:-}"
readonly BACKUP="${4:-}"
readonly LOCAL_DAY="${5:-$(date +%F)}"
readonly PRIVATE_TITLE="qa-zc010007-private-window-title"
readonly PRIVATE_URL="https://qa-zc010007-private.invalid/client"
readonly AGENT_LABEL="qa.ziadnasreldin.ZoidCoach.agent"
readonly SIMULATED_APP_PID="${ZOID_COACH_ZC010007_SIMULATED_APP_PID:-}"
readonly SIMULATED_APP_OWNS_DATABASE="${ZOID_COACH_ZC010007_SIMULATED_APP_OWNS_DATABASE:-0}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local actual
    actual="$(scalar "$1")" || fail "$3: SQLite query failed"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}

validate_schema() {
    [[ -f "$DATABASE" ]] || fail "database is unavailable: $DATABASE"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='today_snapshots';" "1" "today_snapshots table"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('today_snapshots') WHERE name IN ('day_key','payload','updated_at');" "3" "today_snapshots columns"
    assert_scalar "SELECT json_valid('{\"ready\":true}');" "1" "SQLite JSON support"
}

read_backup() {
    [[ -s "$BACKUP" ]] || fail "backup is unavailable: $BACKUP"
    IFS=$'\t' read -r BACKUP_DAY BACKUP_UPDATED BACKUP_HEX < "$BACKUP"
    [[ "$BACKUP_DAY" == "$LOCAL_DAY" ]] || fail "backup belongs to another local day"
    [[ "$BACKUP_HEX" =~ '^[0-9A-F]+$' ]] || fail "backup payload is invalid"
}

restore_snapshot() {
    read_backup
    sqlite3 -batch "$DATABASE" <<SQL
.timeout 2000
BEGIN IMMEDIATE;
INSERT INTO today_snapshots(day_key, payload, updated_at)
VALUES('$BACKUP_DAY', X'$BACKUP_HEX', '$BACKUP_UPDATED')
ON CONFLICT(day_key) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at;
COMMIT;
SQL
}

assert_helper_stopped() {
    ! launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 \
        || fail "exact QA helper must be unregistered during snapshot verification"
    [[ -z "$(pgrep -x ZoidCoachAgentQA 2>/dev/null || true)" ]] \
        || fail "exact QA helper process must exit during snapshot verification"
}

active_qa_app_pids() {
    if [[ "$COMMAND" == _self-test-* && -n "$SIMULATED_APP_PID" ]]; then
        print -- "$SIMULATED_APP_PID"
    else
        pgrep -x ZoidCoachQA 2>/dev/null || true
    fi
}

qa_app_owns_database() {
    if [[ "$COMMAND" == _self-test-* && "$SIMULATED_APP_OWNS_DATABASE" == "1" ]]; then
        return 0
    fi
    lsof -a -p "$1" "$DATABASE" >/dev/null 2>&1
}

assert_read_isolation() {
    assert_helper_stopped
    local pids=( ${(f)"$(active_qa_app_pids)"} )
    (( ${#pids} <= 1 )) || fail "multiple QA app processes are active during snapshot assertion"
    local pid
    for pid in $pids; do
        qa_app_owns_database "$pid" \
            || fail "foreground QA app does not own the exact fixture database"
    done
}

assert_mutation_isolation() {
    assert_helper_stopped
    [[ -z "$(active_qa_app_pids)" ]] \
        || fail "exact QA app process must exit before snapshot mutation"
}

prepare() {
    assert_mutation_isolation
    validate_schema
    [[ ! -e "$BACKUP" ]] || fail "refusing to replace existing backup: $BACKUP"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY' AND json_valid(CAST(payload AS TEXT));" "1" "valid current-day snapshot"
    mkdir -p "${BACKUP:h}"
    sqlite3 -batch -noheader -separator $'\t' "$DATABASE" \
        "SELECT day_key, updated_at, hex(payload) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" > "$BACKUP"
    chmod 600 "$BACKUP"
    read_backup
    print -- "PASS: ZC-010-007 current-day snapshot backed up byte-for-byte"
}

set_state() {
    assert_mutation_isolation
    local mode active_task main_objective task_rows="json('[]')" remove_planning=0
    case "$STATE" in
        unplanned)
            mode="unplanned"
            active_task="json('null')"
            main_objective="json('null')"
            ;;
        planned)
            mode="planning"
            active_task="json('null')"
            main_objective="'QA planned focus'"
            ;;
        invitation|snoozed|dismissed)
            mode="$STATE"
            active_task="json('null')"
            main_objective="json('null')"
            ;;
        active-unplanned)
            mode="unplanned"
            active_task="json_object('taskID','qa-zc010007-active','startedAt',NULL,'elapsedMinutes',7)"
            main_objective="'QA active focus'"
            task_rows="json_array(json_object('taskID','qa-zc010007-active','title','QA active focus','estimateMinutes',25,'dueDate',NULL,'urgency','low','state','active','elapsedMinutes',7,'isMainObjective',json('true'),'isLocked',json('false')))"
            ;;
        nil)
            mode="invitation"
            active_task="json('null')"
            main_objective="json('null')"
            remove_planning=1
            ;;
        *) fail "unsupported state: $STATE" ;;
    esac
    restore_snapshot
    sqlite3 -batch "$DATABASE" <<SQL
.timeout 2000
BEGIN IMMEDIATE;
UPDATE today_snapshots
SET payload=CAST(json_set(
    CAST(payload AS TEXT),
    '$.planningStatus', json_object('mode','$mode','resumesAt',NULL,'driftInterventionsAllowed',json('false')),
    '$.activeTask', $active_task,
    '$.mainObjective', $main_objective,
    '$.taskRows', $task_rows,
    '$.coverage', json_object(
        'isLimited', json('false'),
        'explanation', '$PRIVATE_TITLE $PRIVATE_URL',
        'lastObservationAt', NULL
    )
) AS BLOB), updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')
WHERE day_key='$LOCAL_DAY';
COMMIT;
SQL
    if (( remove_planning )); then
        sqlite3 -batch "$DATABASE" <<SQL
.timeout 2000
BEGIN IMMEDIATE;
UPDATE today_snapshots
SET payload=CAST(json_remove(CAST(payload AS TEXT),'$.planningStatus') AS BLOB)
WHERE day_key='$LOCAL_DAY';
COMMIT;
SQL
    fi
    assert_state
}

assert_state() {
    assert_read_isolation
    validate_schema
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key='$LOCAL_DAY' AND json_valid(CAST(payload AS TEXT));" "1" "valid fixture snapshot"
    assert_scalar "SELECT instr(json_extract(CAST(payload AS TEXT),'$.coverage.explanation'),'$PRIVATE_TITLE') > 0 FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "1" "decoded private title sentinel"
    assert_scalar "SELECT instr(json_extract(CAST(payload AS TEXT),'$.coverage.explanation'),'$PRIVATE_URL') > 0 FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "1" "decoded private URL sentinel"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT),'$.coverage.isLimited') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "0" "private coverage explanation remains hidden"
    case "$STATE" in
        nil)
            assert_scalar "SELECT json_type(CAST(payload AS TEXT),'$.planningStatus') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "" "nil planning status"
            ;;
        planned)
            assert_scalar "SELECT json_extract(CAST(payload AS TEXT),'$.planningStatus.mode') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "planning" "planned mode"
            ;;
        active-unplanned)
            assert_scalar "SELECT json_extract(CAST(payload AS TEXT),'$.planningStatus.mode') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "unplanned" "active unplanned mode"
            assert_scalar "SELECT json_extract(CAST(payload AS TEXT),'$.activeTask.taskID') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "qa-zc010007-active" "active task"
            assert_scalar "SELECT COUNT(*) FROM today_snapshots, json_each(CAST(payload AS TEXT),'$.taskRows') WHERE day_key='$LOCAL_DAY' AND json_extract(json_each.value,'$.taskID')='qa-zc010007-active' AND json_extract(json_each.value,'$.state')='active';" "1" "active task row"
            ;;
        *)
            assert_scalar "SELECT json_extract(CAST(payload AS TEXT),'$.planningStatus.mode') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "$STATE" "planning mode"
            ;;
    esac
    if [[ "$STATE" != "active-unplanned" ]]; then
        assert_scalar "SELECT json_type(CAST(payload AS TEXT),'$.activeTask') FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "null" "no active task"
    fi
    print -- "PASS: ZC-010-007 fixture state $STATE"
}

cleanup() {
    assert_mutation_isolation
    validate_schema
    restore_snapshot
    assert_scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "$BACKUP_HEX" "exact payload restoration"
    assert_scalar "SELECT updated_at FROM today_snapshots WHERE day_key='$LOCAL_DAY';" "$BACKUP_UPDATED" "exact timestamp restoration"
    rm -f -- "$BACKUP"
    [[ ! -e "$BACKUP" ]] || fail "backup cleanup failed"
    print -- "PASS: ZC-010-007 snapshot restored byte-for-byte"
}

sqlite_failure_self_test() {
    assert_scalar "SELECT value FROM qa_zc010007_missing_table;" "" "intentional SQLite failure"
}

allowed_read_self_test() {
    assert_read_isolation
}

forbidden_mutation_self_test() {
    assert_mutation_isolation
}

self_test() {
    local root
    root="$(mktemp -d /private/tmp/zoid-666-zc010007-fixture.XXXXXX)"
    trap "rm -rf '$root'" EXIT
    local database="$root/test.sqlite"
    local backup="$root/original.tsv"
    local day="2026-07-15"
    if "$SCRIPT_PATH" _self-test-sqlite-failure unused "$database" unused "$day" >/dev/null 2>&1; then
        fail "SQLite query failure was masked by local assignment"
    fi
    sqlite3 "$database" <<'SQL'
CREATE TABLE today_snapshots(day_key TEXT PRIMARY KEY, payload BLOB NOT NULL, updated_at TEXT NOT NULL);
INSERT INTO today_snapshots VALUES('2026-07-15',CAST('{"localDate":"2026-07-15T08:00:00Z","planningStatus":{"mode":"invitation","resumesAt":null,"driftInterventionsAllowed":false},"activeTask":null,"mainObjective":null,"taskRows":[]}' AS BLOB),'2026-07-15T08:00:00Z');
SQL
    env ZOID_COACH_ZC010007_SIMULATED_APP_PID=31337 \
        ZOID_COACH_ZC010007_SIMULATED_APP_OWNS_DATABASE=1 \
        "$SCRIPT_PATH" _self-test-allowed-read unused "$database" unused "$day"
    if env ZOID_COACH_ZC010007_SIMULATED_APP_PID=31337 \
        ZOID_COACH_ZC010007_SIMULATED_APP_OWNS_DATABASE=1 \
        "$SCRIPT_PATH" _self-test-forbidden-mutation unused "$database" unused "$day" >/dev/null 2>&1; then
        fail "active foreground QA app was allowed to mutate the fixture"
    fi
    print -- "PASS: exact DB-owning foreground app may read but cannot mutate the fixture"
    "$SCRIPT_PATH" prepare unused "$database" "$backup" "$day"
    local state
    for state in unplanned planned invitation snoozed dismissed nil active-unplanned; do
        "$SCRIPT_PATH" set "$state" "$database" "$backup" "$day"
        "$SCRIPT_PATH" assert "$state" "$database" "$backup" "$day"
    done
    sqlite3 "$database" <<'SQL'
UPDATE today_snapshots
SET payload=CAST(json_set(CAST(payload AS TEXT),'$.taskRows[0].taskID','qa-zc010007-mismatch') AS BLOB)
WHERE day_key='2026-07-15';
SQL
    if "$SCRIPT_PATH" assert active-unplanned "$database" "$backup" "$day" >/dev/null 2>&1; then
        fail "mismatched active task row ID was accepted"
    fi
    print -- "PASS: mismatched active task row ID is rejected"
    "$SCRIPT_PATH" set active-unplanned "$database" "$backup" "$day"
    sqlite3 "$database" <<'SQL'
UPDATE today_snapshots
SET payload=CAST(json_set(
    CAST(payload AS TEXT),
    '$.planningStatus.mode', 'invitation',
    '$.coverage.isLimited', json('true'),
    '$.coverage.explanation', 'Limited coverage: simulated active helper refresh.'
) AS BLOB)
WHERE day_key='2026-07-15';
SQL
    if "$SCRIPT_PATH" assert active-unplanned "$database" "$backup" "$day" >/dev/null 2>&1; then
        fail "active helper overwrite did not invalidate the private sentinel assertion"
    fi
    print -- "PASS: simulated active helper refresh overwrites and invalidates private sentinels"
    "$SCRIPT_PATH" set active-unplanned "$database" "$backup" "$day"
    "$SCRIPT_PATH" cleanup unused "$database" "$backup" "$day"
    [[ ! -e "$backup" ]] || fail "self-test backup remains after cleanup"
    rm -rf "$root"
    trap - EXIT
    print -- "PASS: ZC-010-007 fixture self-test"
}

case "$COMMAND" in
    prepare) prepare ;;
    set) set_state ;;
    assert) assert_state ;;
    cleanup) cleanup ;;
    _self-test-sqlite-failure) sqlite_failure_self_test ;;
    _self-test-allowed-read) allowed_read_self_test ;;
    _self-test-forbidden-mutation) forbidden_mutation_self_test ;;
    self-test) self_test ;;
    *) fail "usage: $0 {prepare|set|assert|cleanup|self-test} STATE DATABASE BACKUP [LOCAL_DAY]" ;;
esac
