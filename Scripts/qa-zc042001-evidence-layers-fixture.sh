#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SCRIPT_PATH="${0:A}"
readonly SOURCE_DAY="${ZOID_666_QA_ZC042001_DAY:-$(date '+%Y-%m-%d')}"
readonly BASE_EPOCH="${ZOID_666_QA_ZC042001_BASE_EPOCH:-$(date -j -f '%Y-%m-%d %H:%M:%S' "$SOURCE_DAY 09:00:00" '+%s')}"
readonly PREFIX="qa-zc042001"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <prepare-positive|prepare-empty|prepare-limited|assert-positive|assert-empty|assert-limited|cleanup|self-test> [database]"
    exit 2
}
scalar() { sqlite3 -batch -noheader "$DATABASE" "$1"; }
assert_scalar() {
    local actual="$(scalar "$1")"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}
owned_filter() {
    print -- "source_day = '$SOURCE_DAY' AND window_title LIKE '$PREFIX-private-%' AND epoch >= $BASE_EPOCH AND epoch < $((BASE_EPOCH + 1200))"
}
require_schema() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'behavior_records';" "1" "behavior_records table"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'daily_reviews';" "1" "daily_reviews table"
}
cleanup_rows() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE $(owned_filter);
DELETE FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note LIKE '$PREFIX-private-note-%';
COMMIT;
SQL
}
prepare_review_note() {
    local note="$1"
    sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc, personal_note)
VALUES('$SOURCE_DAY', 'pending', NULL, '2026-07-14T09:30:00Z', '$note')
ON CONFLICT(source_day) DO UPDATE SET
  hypothesis_state = 'pending', confirmed_at_utc = NULL,
  updated_at_utc = excluded.updated_at_utc, personal_note = excluded.personal_note;
SQL
}
assert_positive() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "3" "positive observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND classification = 'work';" "2" "positive work evidence"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND classification = 'unknown';" "1" "positive context limit"
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note = '$PREFIX-private-note-positive';" "1" "positive private note"
}
assert_limited() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "2" "limited observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND classification = 'unknown';" "2" "limited Unknown truth"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter) AND classification != 'unknown';" "0" "limited positive evidence absence"
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note = '$PREFIX-private-note-limited';" "1" "limited private note"
}
assert_empty() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_filter);" "0" "empty observations"
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note LIKE '$PREFIX-private-note-%';" "0" "empty private note"
}
prepare_positive() {
    require_schema
    cleanup_rows
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES
('$SOURCE_DAY',$BASE_EPOCH,'09:00','$PREFIX-private-work-app','$PREFIX-private-work-1','$PREFIX-private-url',0,NULL,'2026-07-14T09:00:00Z','work',1),
('$SOURCE_DAY',$((BASE_EPOCH+60)),'09:01','$PREFIX-private-work-app','$PREFIX-private-work-2','$PREFIX-private-url',0,NULL,'2026-07-14T09:01:00Z','work',1),
('$SOURCE_DAY',$((BASE_EPOCH+600)),'09:10','$PREFIX-private-unknown-app','$PREFIX-private-unknown-1','$PREFIX-private-url',0,NULL,'2026-07-14T09:10:00Z','unknown',1);
COMMIT;
SQL
    prepare_review_note "$PREFIX-private-note-positive"
    assert_positive
}
prepare_limited() {
    require_schema
    cleanup_rows
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES
('$SOURCE_DAY',$BASE_EPOCH,'09:00','$PREFIX-private-limited-app','$PREFIX-private-limited-1','$PREFIX-private-url',0,NULL,'2026-07-14T09:00:00Z','unknown',1),
('$SOURCE_DAY',$((BASE_EPOCH+60)),'09:01','$PREFIX-private-limited-app','$PREFIX-private-limited-2','$PREFIX-private-url',0,NULL,'2026-07-14T09:01:00Z','unknown',1);
COMMIT;
SQL
    prepare_review_note "$PREFIX-private-note-limited"
    assert_limited
}
self_test() {
    local root="$(mktemp -d "${TMPDIR:-/tmp}/zc042001-fixture.XXXXXX")"
    local database="$root/fixture.sqlite"
    trap "rm -rf -- '$root'" EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_reviews(source_day TEXT PRIMARY KEY, hypothesis_state TEXT NOT NULL DEFAULT 'pending', confirmed_at_utc TEXT, updated_at_utc TEXT NOT NULL, personal_note TEXT);
SQL
    ZOID_666_QA_ZC042001_DAY=2026-07-14 ZOID_666_QA_ZC042001_BASE_EPOCH=1784012400 "$SCRIPT_PATH" prepare-positive "$database"
    ZOID_666_QA_ZC042001_DAY=2026-07-14 ZOID_666_QA_ZC042001_BASE_EPOCH=1784012400 "$SCRIPT_PATH" prepare-limited "$database"
    ZOID_666_QA_ZC042001_DAY=2026-07-14 ZOID_666_QA_ZC042001_BASE_EPOCH=1784012400 "$SCRIPT_PATH" prepare-empty "$database"
    print -- "PASS: ZC-042-001 evidence fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == self-test ]]; then self_test; exit 0; fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null || fail "sqlite3 is required"
case "$COMMAND" in
    prepare-positive) prepare_positive ;;
    prepare-limited) prepare_limited ;;
    prepare-empty) require_schema; cleanup_rows; assert_empty ;;
    assert-positive) assert_positive ;;
    assert-limited) assert_limited ;;
    assert-empty) assert_empty ;;
    cleanup) require_schema; cleanup_rows; assert_empty ;;
    *) usage ;;
esac
