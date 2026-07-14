#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <prepare|verify-before|verify-after|cleanup> <database>" >&2
    exit 64
}

[[ $# -eq 2 ]] || usage
command_name="$1"
database="$2"
[[ -f "$database" ]] || { echo "Database not found: $database" >&2; exit 66; }
command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 is required." >&2; exit 69; }

local_day="${ZOID_COACH_QA_MERGE_DAY:-$(date +%F)}"
base_epoch="${ZOID_COACH_QA_MERGE_BASE_EPOCH:-$(date -j -f '%Y-%m-%d %H:%M:%S' "$local_day 12:00:00" +%s)}"
right_epoch="$((base_epoch + 60))"
left_app="QA Merge Xcode"
right_app="QA Merge Safari"

scalar() {
    sqlite3 -batch -noheader "$database" "$1"
}

require_schema() {
    [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'behavior_records';")" == "1" ]] \
        || { echo "behavior_records is unavailable." >&2; exit 65; }
    [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'daily_review_session_merges';")" == "1" ]] \
        || { echo "daily_review_session_merges is unavailable." >&2; exit 65; }
}

cleanup() {
    sqlite3 -batch "$database" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_review_session_merges
WHERE source_day = '$local_day'
  AND left_start_epoch = $base_epoch
  AND right_start_epoch = $right_epoch;
DELETE FROM behavior_records
WHERE source_day = '$local_day'
  AND app_name IN ('$left_app', '$right_app');
COMMIT;
SQL
}

verify_observations() {
    [[ "$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$local_day' AND app_name IN ('$left_app', '$right_app');")" == "2" ]] \
        || { echo "Expected exactly two namespaced QA observations." >&2; exit 1; }
    [[ "$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$local_day' AND classification = 'work' AND ((app_name = '$left_app' AND epoch = $base_epoch) OR (app_name = '$right_app' AND epoch = $right_epoch));")" == "2" ]] \
        || { echo "QA observation truth does not match the expected adjacent work sessions." >&2; exit 1; }
}

require_schema
case "$command_name" in
    prepare)
        cleanup
        sqlite3 -batch "$database" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
) VALUES
    ('$local_day', $base_epoch, '12:00', '$left_app', 'qa-private-left', '', 0, NULL, '2026-07-14T12:00:00Z', 'work', 1),
    ('$local_day', $right_epoch, '12:01', '$right_app', 'qa-private-right', '', 0, NULL, '2026-07-14T12:01:00Z', 'work', 1);
COMMIT;
SQL
        verify_observations
        [[ "$(scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE source_day = '$local_day' AND left_start_epoch = $base_epoch AND right_start_epoch = $right_epoch;")" == "0" ]]
        echo "Prepared adjacent review sessions for $local_day at $base_epoch and $right_epoch."
        ;;
    verify-before)
        verify_observations
        [[ "$(scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE source_day = '$local_day' AND left_start_epoch = $base_epoch AND right_start_epoch = $right_epoch;")" == "0" ]] \
            || { echo "The QA sessions were already merged." >&2; exit 1; }
        ;;
    verify-after)
        verify_observations
        [[ "$(scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE source_day = '$local_day' AND left_start_epoch = $base_epoch AND right_start_epoch = $right_epoch;")" == "1" ]] \
            || { echo "Expected one durable QA session merge." >&2; exit 1; }
        ;;
    cleanup)
        cleanup
        [[ "$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$local_day' AND app_name IN ('$left_app', '$right_app');")" == "0" ]]
        [[ "$(scalar "SELECT COUNT(*) FROM daily_review_session_merges WHERE source_day = '$local_day' AND left_start_epoch = $base_epoch AND right_start_epoch = $right_epoch;")" == "0" ]]
        ;;
    *) usage ;;
esac
