#!/usr/bin/env bash
set -euo pipefail

readonly PRIVATE_TITLE="qa-zc013001-private-window-title"
readonly PRIVATE_URL="https://qa-zc013001-private.invalid/client"
SQLITE3_COMMAND="${ZC013001_SQLITE3_COMMAND:-sqlite3}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

usage() {
    fail "usage: $0 {prepare|set|assert|cleanup|self-test} [state] --database PATH --backup PATH [--local-day YYYY-MM-DD]"
}

scalar() {
    "$SQLITE3_COMMAND" -batch -noheader "$DATABASE" "$1"
}

sqlite_write() {
    local sql attempts timeout_ms retry_delay output
    sql="$(cat)"
    attempts="${ZC013001_SQLITE_WRITE_ATTEMPTS:-4}"
    timeout_ms="${ZC013001_SQLITE_BUSY_TIMEOUT_MS:-1000}"
    retry_delay="${ZC013001_SQLITE_RETRY_DELAY_SECONDS:-0.1}"
    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || fail "invalid SQLite write attempt bound"
    [[ "$timeout_ms" =~ ^[0-9]+$ ]] || fail "invalid SQLite busy timeout"

    local attempt
    for (( attempt = 1; attempt <= attempts; attempt += 1 )); do
        if output="$({ printf '.timeout %s\n' "$timeout_ms"; printf '%s\n' "$sql"; } \
            | "$SQLITE3_COMMAND" -batch "$DATABASE" 2>&1)"; then
            return 0
        fi
        (( attempt == attempts )) || sleep "$retry_delay"
    done
    printf 'FAIL: SQLite write remained locked after %s attempts: %s\n' "$attempts" "$output" >&2
    return 1
}

assert_scalar() {
    local sql="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(scalar "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

validate_schema() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'today_snapshots';" "1" "today_snapshots table"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('today_snapshots') WHERE name IN ('day_key', 'payload', 'updated_at');" "3" "today_snapshots columns"
    assert_scalar "SELECT json_valid('{\"state\":\"ready\"}');" "1" "SQLite JSON support"
}

read_backup() {
    [[ -f "$BACKUP" ]] || fail "snapshot backup is unavailable: $BACKUP"
    IFS=$'\t' read -r BACKUP_DAY BACKUP_UPDATED BACKUP_HEX < "$BACKUP"
    [[ "$BACKUP_DAY" == "$LOCAL_DAY" ]] || fail "snapshot backup belongs to another day"
    [[ "$BACKUP_HEX" =~ ^[0-9A-F]+$ ]] || fail "snapshot backup payload is invalid"
}

restore_snapshot() {
    read_backup
    sqlite_write <<SQL
BEGIN IMMEDIATE;
INSERT INTO today_snapshots(day_key, payload, updated_at)
VALUES('$BACKUP_DAY', X'$BACKUP_HEX', '$BACKUP_UPDATED')
ON CONFLICT(day_key) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;
COMMIT;
SQL
}

prepare() {
    validate_schema
    [[ ! -e "$BACKUP" ]] || fail "refusing to replace existing snapshot backup: $BACKUP"
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key = '$LOCAL_DAY' AND json_valid(CAST(payload AS TEXT));" "1" "valid current-day snapshot"
    mkdir -p "$(dirname "$BACKUP")"
    "$SQLITE3_COMMAND" -batch -noheader -separator $'\t' "$DATABASE" \
        "SELECT day_key, updated_at, hex(payload) FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" > "$BACKUP"
    chmod 600 "$BACKUP"
    read_backup
    printf 'PASS: ZC-013-001 original Today snapshot backed up outside the repository\n'
}

set_state() {
    local state="$1"
    [[ "$state" != "preparing" ]] || {
        read_backup
        sqlite_write <<SQL
BEGIN IMMEDIATE;
DELETE FROM today_snapshots WHERE day_key = '$LOCAL_DAY';
COMMIT;
SQL
        assert_state preparing
        return
    }
    local mode main_objective active_task
    case "$state" in
        invitation)
            mode="invitation"
            main_objective="json('null')"
            active_task="json('null')"
            ;;
        snoozed)
            mode="snoozed"
            main_objective="json('null')"
            active_task="json('null')"
            ;;
        dismissed)
            mode="dismissed"
            main_objective="json('null')"
            active_task="json('null')"
            ;;
        planned)
            mode="planning"
            main_objective="'QA planned focus'"
            active_task="json('null')"
            ;;
        unplanned)
            mode="unplanned"
            main_objective="json('null')"
            active_task="json('null')"
            ;;
        active)
            mode="unplanned"
            main_objective="'QA active focus'"
            active_task="json_object('taskID', 'qa-zc013001-active', 'startedAt', NULL, 'elapsedMinutes', 0)"
            ;;
        *) fail "unsupported day state: $state" ;;
    esac
    restore_snapshot
    sqlite_write <<SQL
BEGIN IMMEDIATE;
UPDATE today_snapshots
SET payload = CAST(json_set(
        CAST(payload AS TEXT),
        '$.planningStatus', json_object(
            'mode', '$mode',
            'resumesAt', NULL,
            'driftInterventionsAllowed', json('false')
        ),
        '$.activeTask', $active_task,
        '$.mainObjective', $main_objective,
        '$.taskRows', json('[]'),
        '$.qaPrivateWindowTitle', '$PRIVATE_TITLE',
        '$.qaPrivateURL', '$PRIVATE_URL'
    ) AS BLOB),
    updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE day_key = '$LOCAL_DAY';
COMMIT;
SQL
    assert_state "$state"
}

assert_state() {
    local state="$1"
    if [[ "$state" == "preparing" ]]; then
        assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "0" "no-snapshot preparing state"
        printf 'PASS: ZC-013-001 fixture state preparing\n'
        return
    fi
    local expected_mode
    case "$state" in
        invitation|snoozed|dismissed|unplanned) expected_mode="$state" ;;
        planned) expected_mode="planning" ;;
        active) expected_mode="unplanned" ;;
        *) fail "unsupported assertion state: $state" ;;
    esac
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key = '$LOCAL_DAY' AND json_valid(CAST(payload AS TEXT));" "1" "valid state snapshot"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.planningStatus.mode') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "$expected_mode" "planning mode"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.qaPrivateWindowTitle') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "$PRIVATE_TITLE" "private title sentinel"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.qaPrivateURL') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "$PRIVATE_URL" "private URL sentinel"
    if [[ "$state" == "active" ]]; then
        assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.activeTask.taskID') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "qa-zc013001-active" "active precedence fixture"
    else
        assert_scalar "SELECT json_type(CAST(payload AS TEXT), '$.activeTask') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "null" "inactive state"
    fi
    if [[ "$state" == "planned" ]]; then
        assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.mainObjective') FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "QA planned focus" "planned-day fixture"
    fi
    printf 'PASS: ZC-013-001 fixture state %s\n' "$state"
}

cleanup() {
    restore_snapshot
    assert_scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "$BACKUP_HEX" "exact original snapshot restoration"
    rm -f -- "$BACKUP"
    [[ ! -e "$BACKUP" ]] || fail "snapshot backup cleanup failed"
    printf 'PASS: ZC-013-001 exact original Today snapshot restored and external backup removed\n'
}

self_test() {
    local root original_database original_backup original_day original_sqlite3
    root="$(mktemp -d /private/tmp/zoid-666-zc013001-fixture.XXXXXX)"
    trap 'rm -rf "$root"' EXIT
    original_database="$DATABASE"
    original_backup="$BACKUP"
    original_day="$LOCAL_DAY"
    original_sqlite3="$SQLITE3_COMMAND"
    DATABASE="$root/test.sqlite"
    BACKUP="$root/original-snapshot.tsv"
    LOCAL_DAY="2026-07-14"
    "$SQLITE3_COMMAND" -batch "$DATABASE" <<'SQL'
CREATE TABLE today_snapshots(day_key TEXT PRIMARY KEY, payload BLOB NOT NULL, updated_at TEXT NOT NULL);
INSERT INTO today_snapshots(day_key, payload, updated_at) VALUES(
    '2026-07-14',
    CAST('{"localDate":"2026-07-14T08:00:00Z","planningStatus":{"mode":"invitation","resumesAt":null,"driftInterventionsAllowed":false},"activeTask":null,"mainObjective":null,"taskRows":[]}' AS BLOB),
    '2026-07-14T08:00:00Z'
);
INSERT INTO today_snapshots(day_key, payload, updated_at) VALUES(
    '2026-07-13', CAST('{"foreign":true}' AS BLOB), '2026-07-13T08:00:00Z'
);
SQL
    local sqlite_wrapper="$root/sqlite-lock-wrapper"
    cat > "$sqlite_wrapper" <<'SH'
#!/bin/bash
set -euo pipefail
sql="$(cat)"
count="$(cat "$ZC013001_LOCK_COUNTER")"
count=$((count + 1))
printf '%s\n' "$count" > "$ZC013001_LOCK_COUNTER"
mode="$(cat "$ZC013001_LOCK_MODE")"
if [[ "$mode" == "never" || ( "$mode" == "delayed" && "$count" -lt 3 ) ]]; then
    printf 'Error: database is locked (5)\n' >&2
    exit 5
fi
printf '%s\n' "$sql" | "$ZC013001_REAL_SQLITE3" "$@"
SH
    chmod +x "$sqlite_wrapper"
    export ZC013001_REAL_SQLITE3="$original_sqlite3"
    export ZC013001_LOCK_COUNTER="$root/lock-counter"
    export ZC013001_LOCK_MODE="$root/lock-mode"
    SQLITE3_COMMAND="$sqlite_wrapper"
    printf '0\n' > "$ZC013001_LOCK_COUNTER"
    printf 'delayed\n' > "$ZC013001_LOCK_MODE"
    ZC013001_SQLITE_WRITE_ATTEMPTS=3 ZC013001_SQLITE_BUSY_TIMEOUT_MS=0 \
        ZC013001_SQLITE_RETRY_DELAY_SECONDS=0 sqlite_write <<SQL
BEGIN IMMEDIATE;
UPDATE today_snapshots SET updated_at = updated_at WHERE day_key = '$LOCAL_DAY';
COMMIT;
SQL
    [[ "$(<"$ZC013001_LOCK_COUNTER")" == "3" ]] || fail "delayed lock release did not exercise bounded retries"
    printf '0\n' > "$ZC013001_LOCK_COUNTER"
    printf 'never\n' > "$ZC013001_LOCK_MODE"
    if ZC013001_SQLITE_WRITE_ATTEMPTS=3 ZC013001_SQLITE_BUSY_TIMEOUT_MS=0 \
        ZC013001_SQLITE_RETRY_DELAY_SECONDS=0 sqlite_write >/dev/null 2>&1 <<SQL
BEGIN IMMEDIATE;
UPDATE today_snapshots SET updated_at = updated_at WHERE day_key = '$LOCAL_DAY';
COMMIT;
SQL
    then
        fail "permanent SQLite lock unexpectedly succeeded"
    fi
    [[ "$(<"$ZC013001_LOCK_COUNTER")" == "3" ]] || fail "permanent lock did not stop at the retry bound"
    SQLITE3_COMMAND="$original_sqlite3"
    local original_hex foreign_hex
    original_hex="$(scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '$LOCAL_DAY';")"
    foreign_hex="$(scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '2026-07-13';")"
    prepare >/dev/null
    local state
    for state in invitation snoozed dismissed planned unplanned active; do
        set_state "$state" >/dev/null
        assert_state "$state" >/dev/null
    done
    set_state preparing >/dev/null
    assert_state preparing >/dev/null
    cleanup >/dev/null
    assert_scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '$LOCAL_DAY';" "$original_hex" "self-test exact restoration"
    assert_scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '2026-07-13';" "$foreign_hex" "byte-exact foreign snapshot preservation"
    DATABASE="$original_database"
    BACKUP="$original_backup"
    LOCAL_DAY="$original_day"
    SQLITE3_COMMAND="$original_sqlite3"
    rm -rf "$root"
    trap - EXIT
    printf 'PASS: ZC-013-001 fixture self-test covered every state, exact restore, cleanup, and foreign-row preservation\n'
}

ACTION="${1:-}"
shift || true
STATE=""
if [[ "$ACTION" == "set" || "$ACTION" == "assert" ]]; then
    STATE="${1:-}"
    shift || true
fi
DATABASE=""
BACKUP=""
LOCAL_DAY="$(date +%F)"
while (( $# > 0 )); do
    case "$1" in
        --database) DATABASE="${2:-}"; shift 2 ;;
        --backup) BACKUP="${2:-}"; shift 2 ;;
        --local-day) LOCAL_DAY="${2:-}"; shift 2 ;;
        *) usage ;;
    esac
done

command -v "$SQLITE3_COMMAND" >/dev/null 2>&1 || fail "sqlite3 is required"
if [[ "$ACTION" == "self-test" ]]; then
    self_test
    exit 0
fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || fail "--database must name an existing database"
[[ -n "$BACKUP" ]] || fail "--backup is required"
[[ "$LOCAL_DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "--local-day must use YYYY-MM-DD"
validate_schema

case "$ACTION" in
    prepare) prepare ;;
    set) [[ -n "$STATE" ]] || usage; set_state "$STATE" ;;
    assert) [[ -n "$STATE" ]] || usage; assert_state "$STATE" ;;
    cleanup) cleanup ;;
    *) usage ;;
esac
