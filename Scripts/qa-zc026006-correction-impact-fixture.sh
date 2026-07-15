#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly BACKUP_ROOT="${3:-}"
readonly SCRIPT_PATH="${0:A}"
readonly SOURCE_DAY="${ZOID_666_QA_ZC026006_DAY:-$(date '+%Y-%m-%d')}"
readonly BASE_EPOCH="${ZOID_666_QA_ZC026006_BASE_EPOCH:-$(date -j -f '%Y-%m-%d %H:%M:%S' "$SOURCE_DAY 09:00:00" '+%s')}"
readonly END_EPOCH=$((BASE_EPOCH + 1500))
readonly PREFIX="qa-zc026006"
readonly PRIVATE_APP="$PREFIX-private-app"
readonly PRIVATE_TASK="$PREFIX-private-task"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <prepare|assert-before|assert-combined|assert-removed|assert-attached|assert-final|cleanup|snapshot|restore|self-test> [database] [backup-root]"
    exit 2
}
scalar() { sqlite3 -batch -noheader "$DATABASE" "$1"; }
assert_scalar() {
    local actual="$(scalar "$1")"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}
require_schema() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='behavior_records';" "1" "behavior_records schema"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='daily_review_corrections';" "1" "daily_review_corrections schema"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='daily_reviews';" "1" "daily_reviews schema"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('behavior_records') WHERE name='classification';" "1" "behavior classification column"
}
raw_filter() {
    print -- "source_day='$SOURCE_DAY' AND epoch >= $BASE_EPOCH AND epoch < $END_EPOCH AND app_name='$PRIVATE_APP'"
}
correction_filter() {
    print -- "source_day='$SOURCE_DAY' AND start_epoch=$BASE_EPOCH AND end_epoch=$END_EPOCH"
}
assert_raw_evidence() {
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(raw_filter);" "25" "owned raw observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(raw_filter) AND classification='gaming';" "25" "immutable raw gaming observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(raw_filter) AND window_title='$PREFIX-private-window-title' AND url='$PREFIX-private-url';" "25" "private raw sentinels"
}
assert_latest_correction() {
    local expected_classification="$1"
    local expected_task="$2"
    local actual
    actual="$(scalar "SELECT classification || '|' || COALESCE(task_id, '<nil>') FROM daily_review_corrections WHERE $(correction_filter) ORDER BY created_at_utc DESC, rowid DESC LIMIT 1;")"
    [[ "$actual" == "$expected_classification|$expected_task" ]] \
        || fail "latest correction: expected '$expected_classification|$expected_task', got '$actual'"
    assert_raw_evidence
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day='$SOURCE_DAY' AND hypothesis_state='pending' AND confirmed_at_utc IS NULL;" "1" "reopened review state"
}
cleanup_rows() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_review_corrections WHERE $(correction_filter);
DELETE FROM behavior_records WHERE $(raw_filter);
DELETE FROM daily_reviews WHERE source_day='$SOURCE_DAY';
COMMIT;
SQL
}
prepare() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day='$SOURCE_DAY';" "0" "foreign behavior rows on fixture day"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE source_day='$SOURCE_DAY';" "0" "foreign corrections on fixture day"
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day='$SOURCE_DAY';" "0" "foreign review state on fixture day"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
WITH RECURSIVE sequence(value) AS (
  VALUES(0)
  UNION ALL
  SELECT value + 1 FROM sequence WHERE value < 24
)
INSERT INTO behavior_records(
  source_day, epoch, time_label, app_name, window_title, url,
  has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
)
SELECT
  '$SOURCE_DAY', $BASE_EPOCH + (value * 60), printf('09:%02d', value),
  '$PRIVATE_APP', '$PREFIX-private-window-title', '$PREFIX-private-url',
  0, NULL, '2026-07-15T09:00:00Z', 'gaming', 1
FROM sequence;
COMMIT;
SQL
    assert_before
}
assert_before() {
    require_schema
    assert_raw_evidence
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE $(correction_filter);" "0" "before correction rows"
}
assert_combined() {
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE $(correction_filter);" "1" "combined correction count"
    assert_latest_correction "work" "$PRIVATE_TASK"
}
assert_removed() {
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE $(correction_filter);" "2" "removed-alignment correction count"
    assert_latest_correction "work" "<nil>"
}
assert_attached() {
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE $(correction_filter);" "3" "reattached-alignment correction count"
    assert_latest_correction "work" "$PRIVATE_TASK"
}
assert_final() {
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE $(correction_filter);" "4" "final correction count"
    assert_latest_correction "gaming" "$PRIVATE_TASK"
}
require_isolated_paths() {
    [[ -n "${ZOID_666_QA_ROOT:-}" ]] || fail "ZOID_666_QA_ROOT is required for byte snapshot and restore"
    local qa_root="${ZOID_666_QA_ROOT:A}"
    local database="${DATABASE:A}"
    local backup="${BACKUP_ROOT:A}"
    [[ "$qa_root" != "/" && "$qa_root" != "$HOME" && "$database" == "$qa_root/"* ]] \
        || fail "database is outside the explicit isolated QA root"
    [[ "$backup" == /private/tmp/* || "$backup" == "${TMPDIR:A}/"* ]] \
        || fail "byte backup must stay under a temporary root"
}
snapshot_bytes() {
    require_isolated_paths
    [[ -f "$DATABASE" ]] || fail "database is unavailable"
    [[ ! -e "$BACKUP_ROOT" ]] || fail "backup root already exists"
    mkdir -p "$BACKUP_ROOT/files"
    print -r -- "${DATABASE:A}" > "$BACKUP_ROOT/database-path"
    : > "$BACKUP_ROOT/manifest"
    local suffix source name sha size
    for suffix in "" "-wal" "-shm"; do
        source="$DATABASE$suffix"
        name="database${suffix:-main}"
        if [[ -f "$source" ]]; then
            cp -p "$source" "$BACKUP_ROOT/files/$name"
            sha="$(shasum -a 256 "$source" | awk '{print $1}')"
            size="$(stat -f '%z' "$source")"
            print -r -- "$suffix|present|$sha|$size" >> "$BACKUP_ROOT/manifest"
        else
            print -r -- "$suffix|absent|-|0" >> "$BACKUP_ROOT/manifest"
        fi
    done
    print -r -- "$PREFIX-byte-backup-v1" > "$BACKUP_ROOT/owner"
}
restore_bytes() {
    require_isolated_paths
    [[ "$(cat "$BACKUP_ROOT/owner" 2>/dev/null)" == "$PREFIX-byte-backup-v1" ]] || fail "backup ownership marker is invalid"
    [[ "$(cat "$BACKUP_ROOT/database-path" 2>/dev/null)" == "${DATABASE:A}" ]] || fail "backup database path mismatch"
    local suffix state sha size name target restored_sha restored_size
    while IFS='|' read -r suffix state sha size; do
        target="$DATABASE$suffix"
        name="database${suffix:-main}"
        rm -f -- "$target"
        if [[ "$state" == "present" ]]; then
            cp -p "$BACKUP_ROOT/files/$name" "$target"
            restored_sha="$(shasum -a 256 "$target" | awk '{print $1}')"
            restored_size="$(stat -f '%z' "$target")"
            [[ "$restored_sha" == "$sha" && "$restored_size" == "$size" ]] \
                || fail "byte restore mismatch for database$suffix"
        else
            [[ "$state" == "absent" && ! -e "$target" ]] || fail "absent sidecar was restored unexpectedly"
        fi
    done < "$BACKUP_ROOT/manifest"
    [[ -f "$DATABASE" ]] || fail "main database was not restored"
}
insert_test_correction() {
    local database="$1" source_day="$2" base_epoch="$3" end_epoch="$4"
    local id="$5" classification="$6" task_sql="$7" timestamp="$8"
    sqlite3 -batch "$database" <<SQL
INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc)
VALUES('$id', '$source_day', $base_epoch, $end_epoch, '$classification', $task_sql, '$timestamp');
INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc)
VALUES('$source_day', 'pending', NULL, '$timestamp')
ON CONFLICT(source_day) DO UPDATE SET hypothesis_state='pending', confirmed_at_utc=NULL, updated_at_utc=excluded.updated_at_utc;
SQL
}
self_test() {
    local root="$(mktemp -d /private/tmp/zc026006-fixture.XXXXXX)"
    local qa_root="$root/runtime"
    local database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    local backup="$root/backup"
    trap "rm -rf -- '$root'" EXIT
    mkdir -p "${database:h}"
    sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_review_corrections(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, start_epoch INTEGER NOT NULL, end_epoch INTEGER NOT NULL, classification TEXT NOT NULL, task_id TEXT, created_at_utc TEXT NOT NULL);
CREATE TABLE daily_reviews(source_day TEXT PRIMARY KEY, hypothesis_state TEXT NOT NULL, confirmed_at_utc TEXT, updated_at_utc TEXT NOT NULL);
SQL
    ZOID_666_QA_ROOT="$qa_root" "$SCRIPT_PATH" snapshot "$database" "$backup"
    ZOID_666_QA_ROOT="$qa_root" ZOID_666_QA_ZC026006_DAY=2026-07-15 ZOID_666_QA_ZC026006_BASE_EPOCH=1784106000 "$SCRIPT_PATH" prepare "$database"
    insert_test_correction "$database" 2026-07-15 1784106000 1784107500 combined work "'$PRIVATE_TASK'" 2026-07-15T09:30:01Z
    ZOID_666_QA_ZC026006_DAY=2026-07-15 ZOID_666_QA_ZC026006_BASE_EPOCH=1784106000 "$SCRIPT_PATH" assert-combined "$database"
    insert_test_correction "$database" 2026-07-15 1784106000 1784107500 removed work NULL 2026-07-15T09:30:02Z
    ZOID_666_QA_ZC026006_DAY=2026-07-15 ZOID_666_QA_ZC026006_BASE_EPOCH=1784106000 "$SCRIPT_PATH" assert-removed "$database"
    insert_test_correction "$database" 2026-07-15 1784106000 1784107500 attached work "'$PRIVATE_TASK'" 2026-07-15T09:30:03Z
    ZOID_666_QA_ZC026006_DAY=2026-07-15 ZOID_666_QA_ZC026006_BASE_EPOCH=1784106000 "$SCRIPT_PATH" assert-attached "$database"
    insert_test_correction "$database" 2026-07-15 1784106000 1784107500 final gaming "'$PRIVATE_TASK'" 2026-07-15T09:30:04Z
    ZOID_666_QA_ZC026006_DAY=2026-07-15 ZOID_666_QA_ZC026006_BASE_EPOCH=1784106000 "$SCRIPT_PATH" assert-final "$database"
    ZOID_666_QA_ROOT="$qa_root" "$SCRIPT_PATH" restore "$database" "$backup"
    [[ "$(sqlite3 -batch -noheader "$database" 'SELECT COUNT(*) FROM behavior_records;')" == "0" ]] || fail "byte restore retained fixture rows"
    print -- "PASS: ZC-026-006 correction fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then self_test; exit 0; fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null || fail "sqlite3 is required"
case "$COMMAND" in
    prepare) prepare ;;
    assert-before) assert_before ;;
    assert-combined) assert_combined ;;
    assert-removed) assert_removed ;;
    assert-attached) assert_attached ;;
    assert-final) assert_final ;;
    cleanup) require_schema; cleanup_rows ;;
    snapshot) [[ -n "$BACKUP_ROOT" ]] || usage; snapshot_bytes ;;
    restore) [[ -n "$BACKUP_ROOT" ]] || usage; restore_bytes ;;
    *) usage ;;
esac
