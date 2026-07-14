#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SCRIPT_PATH="${0:A}"
readonly SOURCE_DAY="${ZOID_666_QA_ZC041005_DAY:-$(date '+%Y-%m-%d')}"
readonly BASE_EPOCH="${ZOID_666_QA_ZC041005_BASE_EPOCH:-$(date -j -f '%Y-%m-%d %H:%M:%S' "$SOURCE_DAY 08:00:00" '+%s')}"
readonly PREFIX="qa-zc041005"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|prepare-empty|assert-prepared|assert-empty|assert-relaunch|cleanup|self-test> [database]"
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

require_schema() {
    local table
    for table in behavior_records daily_review_corrections daily_review_session_merges; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table table"
    done
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('behavior_records') WHERE name = 'classification';" "1" "behavior_records.classification column"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('daily_review_corrections') WHERE name = 'classification';" "1" "daily_review_corrections.classification column"
}

owned_record_filter() {
    print -- "source_day = '$SOURCE_DAY' AND window_title LIKE '$PREFIX-private-%' AND epoch >= $BASE_EPOCH AND epoch < $((BASE_EPOCH + 7000))"
}

cleanup_rows() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';
DELETE FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';
DELETE FROM behavior_records WHERE $(owned_record_filter);
COMMIT;
SQL
}

assert_prepared() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter);" "33" "owned behavior observations"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';" "10" "persisted classification corrections"
    assert_scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';" "4" "persisted chosen-left merges"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter) AND classification = 'work';" "0" "raw observations remain unclassified as work"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter) AND classification = 'gaming';" "5" "owned non-work observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter) AND (window_title NOT LIKE '$PREFIX-private-%' OR url != '$PREFIX-private-url');" "0" "private sentinel ownership"
}

assert_empty() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter);" "3" "owned non-work observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter) AND classification = 'gaming';" "3" "empty-state non-work truth"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';" "0" "empty-state corrections"
    assert_scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';" "0" "empty-state merges"
}

prepare() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter);" "0" "unused observation namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';" "0" "unused correction namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';" "0" "unused merge namespace"
    local t="$BASE_EPOCH"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES
('$SOURCE_DAY',$((t+0)),'08:00','Xcode','$PREFIX-private-deep-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:00:00Z','unknown',1),
('$SOURCE_DAY',$((t+60)),'08:01','Xcode','$PREFIX-private-deep-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:01:00Z','unknown',1),
('$SOURCE_DAY',$((t+600)),'08:10','Figma','$PREFIX-private-creative-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:10:00Z','unknown',1),
('$SOURCE_DAY',$((t+660)),'08:11','Figma','$PREFIX-private-creative-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:11:00Z','unknown',1),
('$SOURCE_DAY',$((t+720)),'08:12','Figma','$PREFIX-private-creative-3','$PREFIX-private-url',0,NULL,'2026-07-14T05:12:00Z','unknown',1),
('$SOURCE_DAY',$((t+1200)),'08:20','Zotero','$PREFIX-private-research-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:20:00Z','unknown',1),
('$SOURCE_DAY',$((t+1260)),'08:21','Zotero','$PREFIX-private-research-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:21:00Z','unknown',1),
('$SOURCE_DAY',$((t+1320)),'08:22','Zotero','$PREFIX-private-research-3','$PREFIX-private-url',0,NULL,'2026-07-14T05:22:00Z','unknown',1),
('$SOURCE_DAY',$((t+1380)),'08:23','Zotero','$PREFIX-private-research-4','$PREFIX-private-url',0,NULL,'2026-07-14T05:23:00Z','unknown',1),
('$SOURCE_DAY',$((t+1800)),'08:30','Slack','$PREFIX-private-communication-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:30:00Z','unknown',1),
('$SOURCE_DAY',$((t+1860)),'08:31','Slack','$PREFIX-private-communication-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:31:00Z','unknown',1),
('$SOURCE_DAY',$((t+1920)),'08:32','Slack','$PREFIX-private-communication-3','$PREFIX-private-url',0,NULL,'2026-07-14T05:32:00Z','unknown',1),
('$SOURCE_DAY',$((t+1980)),'08:33','Slack','$PREFIX-private-communication-4','$PREFIX-private-url',0,NULL,'2026-07-14T05:33:00Z','unknown',1),
('$SOURCE_DAY',$((t+2040)),'08:34','Slack','$PREFIX-private-communication-5','$PREFIX-private-url',0,NULL,'2026-07-14T05:34:00Z','unknown',1),
('$SOURCE_DAY',$((t+2400)),'08:40','Calendar','$PREFIX-private-administration-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:40:00Z','unknown',1),
('$SOURCE_DAY',$((t+2460)),'08:41','Calendar','$PREFIX-private-administration-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:41:00Z','unknown',1),
('$SOURCE_DAY',$((t+2520)),'08:42','Calendar','$PREFIX-private-administration-3','$PREFIX-private-url',0,NULL,'2026-07-14T05:42:00Z','unknown',1),
('$SOURCE_DAY',$((t+2580)),'08:43','Calendar','$PREFIX-private-administration-4','$PREFIX-private-url',0,NULL,'2026-07-14T05:43:00Z','unknown',1),
('$SOURCE_DAY',$((t+2640)),'08:44','Calendar','$PREFIX-private-administration-5','$PREFIX-private-url',0,NULL,'2026-07-14T05:44:00Z','unknown',1),
('$SOURCE_DAY',$((t+2700)),'08:45','Calendar','$PREFIX-private-administration-6','$PREFIX-private-url',0,NULL,'2026-07-14T05:45:00Z','unknown',1),
('$SOURCE_DAY',$((t+3300)),'08:55','Safari','$PREFIX-private-unknown-1','$PREFIX-private-url',0,NULL,'2026-07-14T05:55:00Z','unknown',1),
('$SOURCE_DAY',$((t+3360)),'08:56','Safari','$PREFIX-private-unknown-2','$PREFIX-private-url',0,NULL,'2026-07-14T05:56:00Z','unknown',1),
('$SOURCE_DAY',$((t+3900)),'09:05','Xcode','$PREFIX-private-mixed-1','$PREFIX-private-url',0,NULL,'2026-07-14T06:05:00Z','unknown',1),
('$SOURCE_DAY',$((t+3960)),'09:06','Slack','$PREFIX-private-mixed-2','$PREFIX-private-url',0,NULL,'2026-07-14T06:06:00Z','unknown',1),
('$SOURCE_DAY',$((t+4500)),'09:15','Xcode','$PREFIX-private-partial-1','$PREFIX-private-url',0,NULL,'2026-07-14T06:15:00Z','unknown',1),
('$SOURCE_DAY',$((t+4560)),'09:16','Safari','$PREFIX-private-partial-2','$PREFIX-private-url',0,NULL,'2026-07-14T06:16:00Z','unknown',1),
('$SOURCE_DAY',$((t+5100)),'09:25','Xcode','$PREFIX-private-work-left-1','$PREFIX-private-url',0,NULL,'2026-07-14T06:25:00Z','unknown',1),
('$SOURCE_DAY',$((t+5160)),'09:26','Steam','$PREFIX-private-work-left-2','$PREFIX-private-url',0,NULL,'2026-07-14T06:26:00Z','gaming',1),
('$SOURCE_DAY',$((t+5700)),'09:35','Steam','$PREFIX-private-nonwork-left-1','$PREFIX-private-url',0,NULL,'2026-07-14T06:35:00Z','gaming',1),
('$SOURCE_DAY',$((t+5760)),'09:36','Xcode','$PREFIX-private-nonwork-left-2','$PREFIX-private-url',0,NULL,'2026-07-14T06:36:00Z','unknown',1),
('$SOURCE_DAY',$((t+6300)),'09:45','Steam','$PREFIX-private-gaming-1','$PREFIX-private-url',0,NULL,'2026-07-14T06:45:00Z','gaming',1),
('$SOURCE_DAY',$((t+6360)),'09:46','Steam','$PREFIX-private-gaming-2','$PREFIX-private-url',0,NULL,'2026-07-14T06:46:00Z','gaming',1),
('$SOURCE_DAY',$((t+6420)),'09:47','Steam','$PREFIX-private-gaming-3','$PREFIX-private-url',0,NULL,'2026-07-14T06:47:00Z','gaming',1);

INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc) VALUES
('$PREFIX-correction-deep','$SOURCE_DAY',$((t+0)),$((t+120)),'work',NULL,'2026-07-14T07:00:00Z'),
('$PREFIX-correction-creative','$SOURCE_DAY',$((t+600)),$((t+780)),'work',NULL,'2026-07-14T07:00:01Z'),
('$PREFIX-correction-research','$SOURCE_DAY',$((t+1200)),$((t+1440)),'work',NULL,'2026-07-14T07:00:02Z'),
('$PREFIX-correction-communication','$SOURCE_DAY',$((t+1800)),$((t+2100)),'work',NULL,'2026-07-14T07:00:03Z'),
('$PREFIX-correction-administration','$SOURCE_DAY',$((t+2400)),$((t+2760)),'work',NULL,'2026-07-14T07:00:04Z'),
('$PREFIX-correction-unknown','$SOURCE_DAY',$((t+3300)),$((t+3420)),'work',NULL,'2026-07-14T07:00:05Z'),
('$PREFIX-correction-mixed','$SOURCE_DAY',$((t+3900)),$((t+4020)),'work',NULL,'2026-07-14T07:00:06Z'),
('$PREFIX-correction-partial','$SOURCE_DAY',$((t+4500)),$((t+4620)),'work',NULL,'2026-07-14T07:00:07Z'),
('$PREFIX-correction-work-left','$SOURCE_DAY',$((t+5100)),$((t+5160)),'work',NULL,'2026-07-14T07:00:08Z'),
('$PREFIX-correction-nonwork-right','$SOURCE_DAY',$((t+5760)),$((t+5820)),'work',NULL,'2026-07-14T07:00:09Z');

INSERT INTO daily_review_session_merges(id, source_day, left_start_epoch, right_start_epoch, created_at_utc) VALUES
('$PREFIX-merge-mixed','$SOURCE_DAY',$((t+3900)),$((t+3960)),'2026-07-14T07:01:00Z'),
('$PREFIX-merge-partial','$SOURCE_DAY',$((t+4500)),$((t+4560)),'2026-07-14T07:01:01Z'),
('$PREFIX-merge-work-left','$SOURCE_DAY',$((t+5100)),$((t+5160)),'2026-07-14T07:01:02Z'),
('$PREFIX-merge-nonwork-left','$SOURCE_DAY',$((t+5700)),$((t+5760)),'2026-07-14T07:01:03Z');
COMMIT;
SQL
    assert_prepared
}

prepare_empty() {
    prepare
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';
DELETE FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';
DELETE FROM behavior_records
WHERE $(owned_record_filter)
  AND epoch NOT IN ($((BASE_EPOCH + 6300)), $((BASE_EPOCH + 6360)), $((BASE_EPOCH + 6420)));
COMMIT;
SQL
    assert_empty
}

self_test() {
    local root database
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc041005-fixture.XXXXXX")"
    database="$root/fixture.sqlite"
    trap 'rm -rf -- "$root"' EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_review_corrections(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, start_epoch INTEGER NOT NULL, end_epoch INTEGER NOT NULL, classification TEXT NOT NULL, task_id TEXT, created_at_utc TEXT NOT NULL);
CREATE TABLE daily_review_session_merges(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, left_start_epoch INTEGER NOT NULL, right_start_epoch INTEGER NOT NULL, created_at_utc TEXT NOT NULL, UNIQUE(source_day, left_start_epoch, right_start_epoch));
SQL
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" prepare "$database"
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" assert-relaunch "$database"
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" cleanup "$database"
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" prepare-empty "$database"
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" assert-empty "$database"
    ZOID_666_QA_ZC041005_DAY="2026-07-14" ZOID_666_QA_ZC041005_BASE_EPOCH="1784005200" "$SCRIPT_PATH" cleanup "$database"
    rm -rf -- "$root"
    trap - EXIT
    print -- "PASS: ZC-041-005 fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then
    self_test
    exit 0
fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

case "$COMMAND" in
    prepare) prepare ;;
    prepare-empty) prepare_empty ;;
    assert-prepared|assert-relaunch) assert_prepared ;;
    assert-empty) assert_empty ;;
    cleanup)
        require_schema
        cleanup_rows
        assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE $(owned_record_filter);" "0" "owned observation cleanup"
        assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id LIKE '$PREFIX-%';" "0" "owned correction cleanup"
        assert_scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE id LIKE '$PREFIX-%';" "0" "owned merge cleanup"
        ;;
    *) usage ;;
esac
