#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SCRIPT_PATH="${0:A}"
readonly SOURCE_DAY="${ZOID_666_QA_ZC024004_DAY:-$(date '+%Y-%m-%d')}"
readonly BASE_EPOCH="${ZOID_666_QA_ZC024004_BASE_EPOCH:-$(( $(date '+%s') - 2100 ))}"
readonly PREFIX="qa-zc024004"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|advance-live|advance-settings|advance-background|advance-relaunch|assert-phase|cleanup|self-test> [database] [phase]"
    exit 2
}

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local sql="$1" expected="$2" label="$3" actual
    actual="$(scalar "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

owned_filter() {
    print -- "source_day = '$SOURCE_DAY' AND window_title LIKE '$PREFIX-private-%' AND epoch >= $BASE_EPOCH AND epoch <= $((BASE_EPOCH + 1800))"
}

require_schema() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'behavior_records';" "1" "behavior_records table"
    for column in source_day epoch app_name window_title url classification; do
        assert_scalar "SELECT COUNT(*) FROM pragma_table_info('behavior_records') WHERE name = '$column';" "1" "behavior_records.$column column"
    done
}

phase_count() {
    case "$1" in
        baseline) print 3 ;;
        live) print 9 ;;
        settings) print 15 ;;
        background) print 21 ;;
        relaunch) print 27 ;;
        *) fail "unknown phase: $1" ;;
    esac
}

phase_idle_count() {
    case "$1" in
        baseline) print 1 ;;
        live) print 2 ;;
        settings) print 3 ;;
        background) print 4 ;;
        relaunch) print 5 ;;
        *) fail "unknown phase: $1" ;;
    esac
}

assert_phase() {
    local phase="$1"
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "$(phase_count "$phase")" "owned rows for $phase"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND classification = 'work';" "$(( $(phase_count "$phase") - $(phase_idle_count "$phase") ))" "owned Work rows for $phase"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND (url != '$PREFIX-private-url' OR app_name != 'Zoid QA Fixture');" "0" "private sentinel ownership"
}

insert_block() {
    local phase="$1" start_offset="$2" work_rows="$3" expected_before="$4"
    local statements="" index epoch
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "$expected_before" "phase order before $phase"
    for (( index = 0; index < work_rows; index += 1 )); do
        epoch=$((BASE_EPOCH + start_offset + index * 60))
        statements+="INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('$SOURCE_DAY',$epoch,'qa','Zoid QA Fixture','$PREFIX-private-$phase-work-$index','$PREFIX-private-url',0,NULL,'2026-07-14T00:00:00Z','work',1);"$'\n'
    done
    epoch=$((BASE_EPOCH + start_offset + work_rows * 60))
    statements+="INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('$SOURCE_DAY',$epoch,'qa','Zoid QA Fixture','$PREFIX-private-$phase-cap','$PREFIX-private-url',0,NULL,'2026-07-14T00:00:00Z','idle',1);"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
$statements
COMMIT;
SQL
}

prepare() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "0" "unused fixture namespace"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY';" "0" "isolated ready-state day"
    insert_block baseline 0 2 0
    assert_phase baseline
}

cleanup() {
    require_schema
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE $(owned_filter);
COMMIT;
SQL
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "0" "fixture cleanup"
}

self_test() {
    local root database
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc024004-fixture.XXXXXX")"
    database="$root/fixture.sqlite"
    trap 'rm -rf -- "$root"' EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
SQL
    export ZOID_666_QA_ZC024004_DAY="2026-07-14"
    export ZOID_666_QA_ZC024004_BASE_EPOCH="1784000000"
    "$SCRIPT_PATH" prepare "$database"
    "$SCRIPT_PATH" advance-live "$database"
    "$SCRIPT_PATH" advance-settings "$database"
    "$SCRIPT_PATH" advance-background "$database"
    "$SCRIPT_PATH" advance-relaunch "$database"
    "$SCRIPT_PATH" assert-phase "$database" relaunch
    "$SCRIPT_PATH" cleanup "$database"
    rm -rf -- "$root"
    trap - EXIT
    print -- "PASS: ZC-024-004 live-refresh fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then self_test; exit 0; fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

case "$COMMAND" in
    prepare) prepare ;;
    advance-live) insert_block live 1500 5 3; assert_phase live ;;
    advance-settings) insert_block settings 240 5 9; assert_phase settings ;;
    advance-background) insert_block background 660 5 15; assert_phase background ;;
    advance-relaunch) insert_block relaunch 1080 5 21; assert_phase relaunch ;;
    assert-phase) [[ -n "${3:-}" ]] || usage; assert_phase "$3" ;;
    cleanup) cleanup ;;
    *) usage ;;
esac
