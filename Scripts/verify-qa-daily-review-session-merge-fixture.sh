#!/bin/bash
set -euo pipefail

root="$(mktemp -d "${TMPDIR:-/tmp}/zoid-session-merge-fixture.XXXXXX")"
trap 'rm -rf "$root"' EXIT
database="$root/coach.sqlite"
fixture="$(cd "$(dirname "$0")" && pwd)/qa-daily-review-session-merge-fixture.sh"
export ZOID_COACH_QA_MERGE_DAY="2026-07-14"
export ZOID_COACH_QA_MERGE_BASE_EPOCH="1784030400"

sqlite3 -batch "$database" <<'SQL'
CREATE TABLE behavior_records (
    source_day TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    time_label TEXT NOT NULL,
    app_name TEXT NOT NULL,
    window_title TEXT,
    url TEXT,
    has_screenshot INTEGER NOT NULL,
    screenshot_path TEXT,
    ingested_at TEXT NOT NULL,
    classification TEXT,
    classification_policy_version INTEGER
);
CREATE TABLE daily_review_session_merges (
    id TEXT PRIMARY KEY,
    source_day TEXT NOT NULL,
    left_start_epoch INTEGER NOT NULL,
    right_start_epoch INTEGER NOT NULL,
    created_at_utc TEXT NOT NULL,
    UNIQUE(source_day, left_start_epoch, right_start_epoch)
);
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
) VALUES ('2026-07-14', 1, '00:00', 'Foreign App', 'preserve', '', 0, NULL, '2026-07-14T00:00:00Z', 'unknown', 1);
SQL

"$fixture" prepare "$database"
"$fixture" verify-before "$database"
sqlite3 -batch "$database" <<'SQL'
INSERT INTO daily_review_session_merges(
    id, source_day, left_start_epoch, right_start_epoch, created_at_utc
) VALUES ('qa-ui-result', '2026-07-14', 1784030400, 1784030460, '2026-07-14T12:02:00Z');
SQL
"$fixture" verify-after "$database"
"$fixture" cleanup "$database"

[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM behavior_records WHERE app_name = 'Foreign App' AND window_title = 'preserve';")" == "1" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM behavior_records;")" == "1" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM daily_review_session_merges;")" == "0" ]]
echo "Daily Review session merge fixture verified."
