#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SOURCE_DAY="${ZOID_COACH_QA_REVIEW_SOURCE_DAY:-2026-07-13}"
readonly PERSONAL_NOTE="qa-review-personal-note: Protect the first focused block tomorrow."
readonly PRIVATE_TITLE_PREFIX="qa-review-private-sentinel"
readonly PRIVATE_URL_PREFIX="https://private.invalid/qa-review"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|assert-prepared|assert-relaunch|cleanup> <database>"
    exit 2
}

[[ -n "$COMMAND" && -n "$DATABASE" ]] || usage
[[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
[[ "$SOURCE_DAY" == <->-<->-<-> ]] || fail "review source day must use YYYY-MM-DD"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
command -v date >/dev/null 2>&1 || fail "date is required"

readonly STARTED_AT="${SOURCE_DAY}T08:00:00Z"
readonly UPDATED_AT="${SOURCE_DAY}T09:00:00Z"
readonly BASE_EPOCH="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$STARTED_AT" '+%s' 2>/dev/null)"
[[ "$BASE_EPOCH" == <-> ]] || fail "could not derive fixture epoch"

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

require_column() {
    local table="$1"
    local column="$2"
    assert_scalar \
        "SELECT COUNT(*) FROM pragma_table_info('$table') WHERE name = '$column';" \
        "1" \
        "$table.$column column"
}

validate_schema() {
    assert_scalar "PRAGMA user_version;" "46" "schema version"
    local table
    for table in behavior_records daily_reviews weekly_review_experiments; do
        assert_scalar \
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" \
            "1" \
            "$table table"
    done
    local column
    for column in source_day epoch time_label app_name window_title url has_screenshot screenshot_path ingested_at classification classification_policy_version; do
        require_column behavior_records "$column"
    done
    for column in source_day hypothesis_state confirmed_at_utc updated_at_utc personal_note skipped_at_utc deferred_until_utc; do
        require_column daily_reviews "$column"
    done
    for column in id review_week_start title instruction measurement state tracking_week_start updated_at_utc; do
        require_column weekly_review_experiments "$column"
    done
}

expected_behavior_values() {
    cat <<SQL
('$SOURCE_DAY', $((BASE_EPOCH + 0)),    '08:00', 'Xcode qa-review-deep', 'qa-review-private-sentinel-deep SECRET-REVIEW-DEEP', 'https://private.invalid/qa-review/deep', 0, NULL, '${SOURCE_DAY}T08:00:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 300)),  '08:05', 'Figma qa-review-creative', 'qa-review-private-sentinel-creative SECRET-REVIEW-CREATIVE', 'https://private.invalid/qa-review/creative', 0, NULL, '${SOURCE_DAY}T08:05:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 600)),  '08:10', 'Zotero qa-review-research', 'qa-review-private-sentinel-research SECRET-REVIEW-RESEARCH', 'https://private.invalid/qa-review/research', 0, NULL, '${SOURCE_DAY}T08:10:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 900)),  '08:15', 'Slack qa-review-communication', 'qa-review-private-sentinel-communication SECRET-REVIEW-COMMUNICATION', 'https://private.invalid/qa-review/communication', 0, NULL, '${SOURCE_DAY}T08:15:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 1200)), '08:20', 'Calendar qa-review-administration', 'qa-review-private-sentinel-administration SECRET-REVIEW-ADMINISTRATION', 'https://private.invalid/qa-review/administration', 0, NULL, '${SOURCE_DAY}T08:20:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 1500)), '08:25', 'qa-review-uncategorized-tool', 'qa-review-private-sentinel-uncategorized SECRET-REVIEW-UNCATEGORIZED', 'https://private.invalid/qa-review/uncategorized', 0, NULL, '${SOURCE_DAY}T08:25:00Z', 'work', 1),
('$SOURCE_DAY', $((BASE_EPOCH + 1800)), '08:30', 'qa-review-uncategorized-tool', 'qa-review-private-sentinel-close SECRET-REVIEW-CLOSE', 'https://private.invalid/qa-review/close', 0, NULL, '${SOURCE_DAY}T08:30:00Z', 'work', 1)
SQL
}

assert_prepared() {
    validate_schema
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-%';" \
        "7" \
        "owned behavior row count"
    assert_scalar \
        "WITH expected(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) AS (VALUES $(expected_behavior_values)) SELECT COUNT(*) FROM expected e JOIN behavior_records b ON b.source_day = e.source_day AND b.epoch = e.epoch AND b.time_label = e.time_label AND b.app_name = e.app_name AND b.window_title = e.window_title AND b.url = e.url AND b.has_screenshot = e.has_screenshot AND b.screenshot_path IS e.screenshot_path AND b.ingested_at = e.ingested_at AND b.classification = e.classification AND b.classification_policy_version = e.classification_policy_version;" \
        "7" \
        "raw behavior evidence unchanged"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND window_title LIKE '$PRIVATE_TITLE_PREFIX%' AND url LIKE '$PRIVATE_URL_PREFIX%';" \
        "7" \
        "private raw sentinel count"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND ingested_at GLOB '????-??-??T??:??:??Z';" \
        "7" \
        "RFC3339 behavior timestamps"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND hypothesis_state = 'pending' AND confirmed_at_utc IS NULL AND skipped_at_utc IS NULL AND deferred_until_utc IS NULL AND updated_at_utc = '$UPDATED_AT' AND personal_note = '$PERSONAL_NOTE';" \
        "1" \
        "pending daily review"
    assert_scalar \
        "SELECT COUNT(*) FROM weekly_review_experiments WHERE id LIKE 'qa-review-%' OR review_week_start LIKE 'qa-review-%';" \
        "0" \
        "unowned weekly experiment rows"
}

prepare() {
    validate_schema
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch IN ($BASE_EPOCH, $((BASE_EPOCH + 300)), $((BASE_EPOCH + 600)), $((BASE_EPOCH + 900)), $((BASE_EPOCH + 1200)), $((BASE_EPOCH + 1500)), $((BASE_EPOCH + 1800))) AND app_name NOT LIKE '%qa-review-%';" \
        "0" \
        "behavior ownership collision"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND COALESCE(personal_note, '') NOT LIKE 'qa-review-personal-note:%';" \
        "0" \
        "daily review ownership collision"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES
$(expected_behavior_values)
ON CONFLICT(source_day, epoch) DO UPDATE SET
    time_label = excluded.time_label,
    app_name = excluded.app_name,
    window_title = excluded.window_title,
    url = excluded.url,
    has_screenshot = excluded.has_screenshot,
    screenshot_path = excluded.screenshot_path,
    ingested_at = excluded.ingested_at,
    classification = excluded.classification,
    classification_policy_version = excluded.classification_policy_version;
INSERT INTO daily_reviews(
    source_day, hypothesis_state, confirmed_at_utc, updated_at_utc,
    personal_note, skipped_at_utc, deferred_until_utc
) VALUES (
    '$SOURCE_DAY', 'pending', NULL, '$UPDATED_AT', '$PERSONAL_NOTE', NULL, NULL
)
ON CONFLICT(source_day) DO UPDATE SET
    hypothesis_state = excluded.hypothesis_state,
    confirmed_at_utc = excluded.confirmed_at_utc,
    updated_at_utc = excluded.updated_at_utc,
    personal_note = excluded.personal_note,
    skipped_at_utc = excluded.skipped_at_utc,
    deferred_until_utc = excluded.deferred_until_utc;
COMMIT;
SQL
    assert_prepared
    print -- "PASS: combined review fixture prepared for $SOURCE_DAY"
    print -- "NON-DISPLAY EXPECTATION: UI must not expose '$PRIVATE_TITLE_PREFIX', 'SECRET-REVIEW-', or '$PRIVATE_URL_PREFIX'."
    print -- "WEEKLY GAP: patterns are derived by WeeklyReviewStore; no direct NOT LEARNED pattern row was fabricated."
}

cleanup() {
    validate_schema
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM daily_reviews
WHERE source_day = '$SOURCE_DAY'
  AND personal_note LIKE 'qa-review-personal-note:%';
DELETE FROM behavior_records
WHERE source_day = '$SOURCE_DAY'
  AND epoch IN ($BASE_EPOCH, $((BASE_EPOCH + 300)), $((BASE_EPOCH + 600)), $((BASE_EPOCH + 900)), $((BASE_EPOCH + 1200)), $((BASE_EPOCH + 1500)), $((BASE_EPOCH + 1800)))
  AND app_name LIKE '%qa-review-%';
COMMIT;
SQL
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-%';" \
        "0" \
        "cleaned behavior rows"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note LIKE 'qa-review-personal-note:%';" \
        "0" \
        "cleaned daily review rows"
    print -- "PASS: combined review fixture cleaned"
}

case "$COMMAND" in
    prepare)
        prepare
        ;;
    assert-prepared)
        assert_prepared
        print -- "PASS: combined review fixture remains prepared"
        ;;
    assert-relaunch)
        assert_prepared
        print -- "PASS: combined review fixture survived relaunch unchanged"
        print -- "NON-DISPLAY EXPECTATION: private raw window titles and URLs remain forbidden in combined-review UI copy."
        ;;
    cleanup)
        cleanup
        ;;
    *)
        usage
        ;;
esac
