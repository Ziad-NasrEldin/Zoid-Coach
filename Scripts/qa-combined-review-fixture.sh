#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SOURCE_DAY="${ZOID_COACH_QA_REVIEW_SOURCE_DAY:-2026-07-13}"
readonly CATEGORY_SOURCE_DAY="${ZOID_COACH_QA_CATEGORY_SOURCE_DAY:-$(date '+%Y-%m-%d')}"
readonly PERSONAL_NOTE="qa-review-personal-note: Protect the first focused block tomorrow."
readonly PRIVATE_TITLE_PREFIX="qa-review-private-sentinel"
readonly PRIVATE_URL_PREFIX="https://private.invalid/qa-review"
readonly WEEKLY_ID_PREFIX="qa-review-weekly-"

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
[[ "$CATEGORY_SOURCE_DAY" == <->-<->-<-> ]] || fail "category source day must use YYYY-MM-DD"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
command -v date >/dev/null 2>&1 || fail "date is required"
[[ "$(date -j -u -f '%Y-%m-%d' "$SOURCE_DAY" '+%u' 2>/dev/null)" == "1" ]] \
    || fail "review source day must be a Monday so owned prior-week inputs stay inside every supported local calendar window"

readonly STARTED_AT="${SOURCE_DAY}T08:00:00Z"
readonly UPDATED_AT="${SOURCE_DAY}T09:00:00Z"
readonly BASE_EPOCH="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$STARTED_AT" '+%s' 2>/dev/null)"
[[ "$BASE_EPOCH" == <-> ]] || fail "could not derive fixture epoch"
readonly CATEGORY_STARTED_AT="${CATEGORY_SOURCE_DAY}T08:00:00Z"
readonly CATEGORY_BASE_EPOCH="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$CATEGORY_STARTED_AT" '+%s' 2>/dev/null)"
[[ "$CATEGORY_BASE_EPOCH" == <-> ]] || fail "could not derive category fixture epoch"
readonly WEEKLY_DAY_1="$(date -j -u -v-6d -f '%Y-%m-%d' "$SOURCE_DAY" '+%Y-%m-%d' 2>/dev/null)"
readonly WEEKLY_DAY_2="$(date -j -u -v-5d -f '%Y-%m-%d' "$SOURCE_DAY" '+%Y-%m-%d' 2>/dev/null)"
readonly WEEKLY_DAY_3="$(date -j -u -v-4d -f '%Y-%m-%d' "$SOURCE_DAY" '+%Y-%m-%d' 2>/dev/null)"
readonly WEEKLY_DAY_4="$(date -j -u -v-3d -f '%Y-%m-%d' "$SOURCE_DAY" '+%Y-%m-%d' 2>/dev/null)"
readonly WEEKLY_EPOCH_1="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${WEEKLY_DAY_1}T08:00:00Z" '+%s' 2>/dev/null)"
readonly WEEKLY_EPOCH_2="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${WEEKLY_DAY_2}T08:00:00Z" '+%s' 2>/dev/null)"
readonly WEEKLY_EPOCH_3="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${WEEKLY_DAY_3}T08:00:00Z" '+%s' 2>/dev/null)"
[[ "$WEEKLY_EPOCH_1" == <-> && "$WEEKLY_EPOCH_2" == <-> && "$WEEKLY_EPOCH_3" == <-> ]] \
    || fail "could not derive weekly fixture epochs"

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
    if [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations';")" == "1" ]]; then
        assert_scalar "SELECT MAX(version) FROM schema_migrations;" "47" "migrated schema version"
    else
        assert_scalar "PRAGMA user_version;" "46" "standalone fixture schema version"
    fi
    local table
    for table in behavior_records daily_reviews learning_samples weekly_review_experiments; do
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
    for column in id sample_type context_key estimated_value actual_value local_minute_of_day timezone_identifier evidence_id occurred_at_utc payload_json; do
        require_column learning_samples "$column"
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

expected_category_behavior_values() {
    cat <<SQL
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 0)),    '08:00', 'Xcode qa-review-category-deep', 'qa-review-private-sentinel-category-deep SECRET-REVIEW-CATEGORY-DEEP', 'https://private.invalid/qa-review/category-deep', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:00:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 300)),  '08:05', 'Figma qa-review-category-creative', 'qa-review-private-sentinel-category-creative SECRET-REVIEW-CATEGORY-CREATIVE', 'https://private.invalid/qa-review/category-creative', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:05:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 600)),  '08:10', 'Zotero qa-review-category-research', 'qa-review-private-sentinel-category-research SECRET-REVIEW-CATEGORY-RESEARCH', 'https://private.invalid/qa-review/category-research', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:10:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 900)),  '08:15', 'Slack qa-review-category-communication', 'qa-review-private-sentinel-category-communication SECRET-REVIEW-CATEGORY-COMMUNICATION', 'https://private.invalid/qa-review/category-communication', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:15:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 1200)), '08:20', 'Calendar qa-review-category-administration', 'qa-review-private-sentinel-category-administration SECRET-REVIEW-CATEGORY-ADMINISTRATION', 'https://private.invalid/qa-review/category-administration', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:20:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 1500)), '08:25', 'qa-review-category-uncategorized-tool', 'qa-review-private-sentinel-category-uncategorized SECRET-REVIEW-CATEGORY-UNCATEGORIZED', 'https://private.invalid/qa-review/category-uncategorized', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:25:00Z', 'work', 1),
('$CATEGORY_SOURCE_DAY', $((CATEGORY_BASE_EPOCH + 1800)), '08:30', 'qa-review-category-uncategorized-tool', 'qa-review-private-sentinel-category-close SECRET-REVIEW-CATEGORY-CLOSE', 'https://private.invalid/qa-review/category-close', 0, NULL, '${CATEGORY_SOURCE_DAY}T08:30:00Z', 'work', 1)
SQL
}

expected_weekly_behavior_values() {
    cat <<SQL
('$WEEKLY_DAY_1', $WEEKLY_EPOCH_1,          '08:00', 'qa-review-weekly-observation-1', '${PRIVATE_TITLE_PREFIX}-weekly-1 SECRET-REVIEW-WEEKLY-1', '${PRIVATE_URL_PREFIX}/weekly-1', 0, NULL, '${WEEKLY_DAY_1}T08:00:00Z', 'work', 1),
('$WEEKLY_DAY_1', $((WEEKLY_EPOCH_1 + 1800)), '08:30', 'qa-review-weekly-observation-1', '${PRIVATE_TITLE_PREFIX}-weekly-1-close SECRET-REVIEW-WEEKLY-1-CLOSE', '${PRIVATE_URL_PREFIX}/weekly-1-close', 0, NULL, '${WEEKLY_DAY_1}T08:30:00Z', 'work', 1),
('$WEEKLY_DAY_2', $WEEKLY_EPOCH_2,          '08:00', 'qa-review-weekly-observation-2', '${PRIVATE_TITLE_PREFIX}-weekly-2 SECRET-REVIEW-WEEKLY-2', '${PRIVATE_URL_PREFIX}/weekly-2', 0, NULL, '${WEEKLY_DAY_2}T08:00:00Z', 'work', 1),
('$WEEKLY_DAY_2', $((WEEKLY_EPOCH_2 + 1800)), '08:30', 'qa-review-weekly-observation-2', '${PRIVATE_TITLE_PREFIX}-weekly-2-close SECRET-REVIEW-WEEKLY-2-CLOSE', '${PRIVATE_URL_PREFIX}/weekly-2-close', 0, NULL, '${WEEKLY_DAY_2}T08:30:00Z', 'work', 1),
('$WEEKLY_DAY_3', $WEEKLY_EPOCH_3,          '08:00', 'qa-review-weekly-observation-3', '${PRIVATE_TITLE_PREFIX}-weekly-3 SECRET-REVIEW-WEEKLY-3', '${PRIVATE_URL_PREFIX}/weekly-3', 0, NULL, '${WEEKLY_DAY_3}T08:00:00Z', 'work', 1),
('$WEEKLY_DAY_3', $((WEEKLY_EPOCH_3 + 1800)), '08:30', 'qa-review-weekly-observation-3', '${PRIVATE_TITLE_PREFIX}-weekly-3-close SECRET-REVIEW-WEEKLY-3-CLOSE', '${PRIVATE_URL_PREFIX}/weekly-3-close', 0, NULL, '${WEEKLY_DAY_3}T08:30:00Z', 'work', 1)
SQL
}

expected_weekly_learning_values() {
    cat <<SQL
('${WEEKLY_ID_PREFIX}estimate-1', 'estimate', '${WEEKLY_ID_PREFIX}context', 30, 45, NULL, 'UTC', '${WEEKLY_ID_PREFIX}evidence-1', '${WEEKLY_DAY_1}T08:45:00Z', '{"sample":{"id":"${WEEKLY_ID_PREFIX}estimate-1","context":{"taskType":"qa-review-weekly-focus","project":"qa-review-weekly-project"},"estimatedMinutes":30,"actualAlignedMinutes":45,"trackingCoverage":0.9,"completedAt":"${WEEKLY_DAY_1}T08:45:00Z","isEligible":true}}'),
('${WEEKLY_ID_PREFIX}estimate-2', 'estimate', '${WEEKLY_ID_PREFIX}context', 30, 45, NULL, 'UTC', '${WEEKLY_ID_PREFIX}evidence-2', '${WEEKLY_DAY_2}T08:45:00Z', '{"sample":{"id":"${WEEKLY_ID_PREFIX}estimate-2","context":{"taskType":"qa-review-weekly-focus","project":"qa-review-weekly-project"},"estimatedMinutes":30,"actualAlignedMinutes":45,"trackingCoverage":0.9,"completedAt":"${WEEKLY_DAY_2}T08:45:00Z","isEligible":true}}'),
('${WEEKLY_ID_PREFIX}estimate-3', 'estimate', '${WEEKLY_ID_PREFIX}context', 30, 45, NULL, 'UTC', '${WEEKLY_ID_PREFIX}evidence-3', '${WEEKLY_DAY_3}T08:45:00Z', '{"sample":{"id":"${WEEKLY_ID_PREFIX}estimate-3","context":{"taskType":"qa-review-weekly-focus","project":"qa-review-weekly-project"},"estimatedMinutes":30,"actualAlignedMinutes":45,"trackingCoverage":0.9,"completedAt":"${WEEKLY_DAY_3}T08:45:00Z","isEligible":true}}'),
('${WEEKLY_ID_PREFIX}estimate-4', 'estimate', '${WEEKLY_ID_PREFIX}context', 30, 45, NULL, 'UTC', '${WEEKLY_ID_PREFIX}evidence-4', '${WEEKLY_DAY_4}T08:45:00Z', '{"sample":{"id":"${WEEKLY_ID_PREFIX}estimate-4","context":{"taskType":"qa-review-weekly-focus","project":"qa-review-weekly-project"},"estimatedMinutes":30,"actualAlignedMinutes":45,"trackingCoverage":0.9,"completedAt":"${WEEKLY_DAY_4}T08:45:00Z","isEligible":true}}')
SQL
}

assert_prepared() {
    validate_schema
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-%';" \
        "7" \
        "owned behavior row count"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$CATEGORY_SOURCE_DAY' AND epoch BETWEEN $CATEGORY_BASE_EPOCH AND $((CATEGORY_BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-category-%';" \
        "7" \
        "owned current-day category row count"
    assert_scalar \
        "WITH expected(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) AS (VALUES $(expected_behavior_values)) SELECT COUNT(*) FROM expected e JOIN behavior_records b ON b.source_day = e.source_day AND b.epoch = e.epoch AND b.time_label = e.time_label AND b.app_name = e.app_name AND b.window_title = e.window_title AND b.url = e.url AND b.has_screenshot = e.has_screenshot AND b.screenshot_path IS e.screenshot_path AND b.ingested_at = e.ingested_at AND b.classification = e.classification AND b.classification_policy_version = e.classification_policy_version;" \
        "7" \
        "raw behavior evidence unchanged"
    assert_scalar \
        "WITH expected(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) AS (VALUES $(expected_category_behavior_values)) SELECT COUNT(*) FROM expected e JOIN behavior_records b ON b.source_day = e.source_day AND b.epoch = e.epoch AND b.time_label = e.time_label AND b.app_name = e.app_name AND b.window_title = e.window_title AND b.url = e.url AND b.has_screenshot = e.has_screenshot AND b.screenshot_path IS e.screenshot_path AND b.ingested_at = e.ingested_at AND b.classification = e.classification AND b.classification_policy_version = e.classification_policy_version;" \
        "7" \
        "current-day category evidence unchanged"
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
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3') AND hypothesis_state = 'pending' AND confirmed_at_utc GLOB '????-??-??T??:??:??Z' AND updated_at_utc = confirmed_at_utc AND personal_note LIKE '${WEEKLY_ID_PREFIX}note-%' AND skipped_at_utc IS NULL AND deferred_until_utc IS NULL;" \
        "3" \
        "confirmed pending weekly reviews"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews r WHERE r.source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3') AND r.confirmed_at_utc IS NOT NULL AND (SELECT COALESCE(MAX(b.epoch) - MIN(b.epoch), 0) FROM behavior_records b WHERE b.source_day = r.source_day) >= 1800;" \
        "3" \
        "adequately covered weekly review days"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3') AND app_name LIKE '${WEEKLY_ID_PREFIX}observation-%' AND window_title LIKE '${PRIVATE_TITLE_PREFIX}-weekly-%' AND url LIKE '${PRIVATE_URL_PREFIX}/weekly-%' AND ingested_at GLOB '????-??-??T??:??:??Z';" \
        "6" \
        "owned weekly behavior evidence"
    assert_scalar \
        "WITH expected(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) AS (VALUES $(expected_weekly_behavior_values)) SELECT COUNT(*) FROM expected e JOIN behavior_records b ON b.source_day = e.source_day AND b.epoch = e.epoch AND b.time_label = e.time_label AND b.app_name = e.app_name AND b.window_title = e.window_title AND b.url = e.url AND b.has_screenshot = e.has_screenshot AND b.screenshot_path IS e.screenshot_path AND b.ingested_at = e.ingested_at AND b.classification = e.classification AND b.classification_policy_version = e.classification_policy_version;" \
        "6" \
        "weekly raw behavior evidence unchanged"
    assert_scalar \
        "SELECT COUNT(*) FROM learning_samples WHERE id LIKE '${WEEKLY_ID_PREFIX}estimate-%' AND sample_type = 'estimate' AND context_key = '${WEEKLY_ID_PREFIX}context' AND estimated_value = 30 AND actual_value = 45 AND timezone_identifier = 'UTC' AND evidence_id LIKE '${WEEKLY_ID_PREFIX}evidence-%' AND occurred_at_utc GLOB '????-??-??T??:??:??Z' AND json_valid(payload_json) AND json_extract(payload_json, '$.sample.isEligible') = 1 AND json_extract(payload_json, '$.sample.trackingCoverage') >= 0.75 AND json_extract(payload_json, '$.sample.estimatedMinutes') = 30 AND json_extract(payload_json, '$.sample.actualAlignedMinutes') = 45;" \
        "4" \
        "eligible weekly estimate learning samples"
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
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$CATEGORY_SOURCE_DAY' AND epoch IN ($CATEGORY_BASE_EPOCH, $((CATEGORY_BASE_EPOCH + 300)), $((CATEGORY_BASE_EPOCH + 600)), $((CATEGORY_BASE_EPOCH + 900)), $((CATEGORY_BASE_EPOCH + 1200)), $((CATEGORY_BASE_EPOCH + 1500)), $((CATEGORY_BASE_EPOCH + 1800))) AND app_name NOT LIKE '%qa-review-category-%';" \
        "0" \
        "current-day category ownership collision"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE ((source_day = '$WEEKLY_DAY_1' AND epoch IN ($WEEKLY_EPOCH_1, $((WEEKLY_EPOCH_1 + 1800)))) OR (source_day = '$WEEKLY_DAY_2' AND epoch IN ($WEEKLY_EPOCH_2, $((WEEKLY_EPOCH_2 + 1800)))) OR (source_day = '$WEEKLY_DAY_3' AND epoch IN ($WEEKLY_EPOCH_3, $((WEEKLY_EPOCH_3 + 1800))))) AND app_name NOT LIKE '${WEEKLY_ID_PREFIX}observation-%';" \
        "0" \
        "weekly behavior ownership collision"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3') AND COALESCE(personal_note, '') NOT LIKE '${WEEKLY_ID_PREFIX}note-%';" \
        "0" \
        "weekly daily review ownership collision"
    assert_scalar \
        "SELECT COUNT(*) FROM learning_samples WHERE id LIKE '${WEEKLY_ID_PREFIX}%' AND (sample_type != 'estimate' OR evidence_id NOT LIKE '${WEEKLY_ID_PREFIX}%');" \
        "0" \
        "weekly learning ownership collision"
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
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES
$(expected_category_behavior_values)
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
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES
$(expected_weekly_behavior_values)
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
INSERT INTO daily_reviews(
    source_day, hypothesis_state, confirmed_at_utc, updated_at_utc,
    personal_note, skipped_at_utc, deferred_until_utc
) VALUES
    ('$WEEKLY_DAY_1', 'pending', '${WEEKLY_DAY_1}T09:00:00Z', '${WEEKLY_DAY_1}T09:00:00Z', '${WEEKLY_ID_PREFIX}note-1', NULL, NULL),
    ('$WEEKLY_DAY_2', 'pending', '${WEEKLY_DAY_2}T09:00:00Z', '${WEEKLY_DAY_2}T09:00:00Z', '${WEEKLY_ID_PREFIX}note-2', NULL, NULL),
    ('$WEEKLY_DAY_3', 'pending', '${WEEKLY_DAY_3}T09:00:00Z', '${WEEKLY_DAY_3}T09:00:00Z', '${WEEKLY_ID_PREFIX}note-3', NULL, NULL)
ON CONFLICT(source_day) DO UPDATE SET
    hypothesis_state = excluded.hypothesis_state,
    confirmed_at_utc = excluded.confirmed_at_utc,
    updated_at_utc = excluded.updated_at_utc,
    personal_note = excluded.personal_note,
    skipped_at_utc = excluded.skipped_at_utc,
    deferred_until_utc = excluded.deferred_until_utc;
INSERT INTO learning_samples(
    id, sample_type, context_key, estimated_value, actual_value,
    local_minute_of_day, timezone_identifier, evidence_id, occurred_at_utc, payload_json
) VALUES
$(expected_weekly_learning_values)
ON CONFLICT(id) DO UPDATE SET
    sample_type = excluded.sample_type,
    context_key = excluded.context_key,
    estimated_value = excluded.estimated_value,
    actual_value = excluded.actual_value,
    local_minute_of_day = excluded.local_minute_of_day,
    timezone_identifier = excluded.timezone_identifier,
    evidence_id = excluded.evidence_id,
    occurred_at_utc = excluded.occurred_at_utc,
    payload_json = excluded.payload_json;
COMMIT;
SQL
    assert_prepared
    print -- "PASS: combined review fixture prepared for review day $SOURCE_DAY and category day $CATEGORY_SOURCE_DAY"
    print -- "NON-DISPLAY EXPECTATION: UI must not expose '$PRIVATE_TITLE_PREFIX', 'SECRET-REVIEW-', or '$PRIVATE_URL_PREFIX'."
    print -- "WEEKLY INPUT READY: 3 adequately covered confirmed days and 4 eligible estimate samples allow WeeklyReviewStore to derive one pattern; no pattern or experiment output was inserted."
}

cleanup() {
    validate_schema
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM learning_samples
WHERE id LIKE '${WEEKLY_ID_PREFIX}%'
  AND evidence_id LIKE '${WEEKLY_ID_PREFIX}%';
DELETE FROM daily_reviews
WHERE source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3')
  AND personal_note LIKE '${WEEKLY_ID_PREFIX}note-%';
DELETE FROM behavior_records
WHERE source_day IN ('$WEEKLY_DAY_1', '$WEEKLY_DAY_2', '$WEEKLY_DAY_3')
  AND app_name LIKE '${WEEKLY_ID_PREFIX}observation-%';
DELETE FROM daily_reviews
WHERE source_day = '$SOURCE_DAY'
  AND personal_note LIKE 'qa-review-personal-note:%';
DELETE FROM behavior_records
WHERE source_day = '$SOURCE_DAY'
  AND epoch IN ($BASE_EPOCH, $((BASE_EPOCH + 300)), $((BASE_EPOCH + 600)), $((BASE_EPOCH + 900)), $((BASE_EPOCH + 1200)), $((BASE_EPOCH + 1500)), $((BASE_EPOCH + 1800)))
  AND app_name LIKE '%qa-review-%';
DELETE FROM behavior_records
WHERE source_day = '$CATEGORY_SOURCE_DAY'
  AND epoch IN ($CATEGORY_BASE_EPOCH, $((CATEGORY_BASE_EPOCH + 300)), $((CATEGORY_BASE_EPOCH + 600)), $((CATEGORY_BASE_EPOCH + 900)), $((CATEGORY_BASE_EPOCH + 1200)), $((CATEGORY_BASE_EPOCH + 1500)), $((CATEGORY_BASE_EPOCH + 1800)))
  AND app_name LIKE '%qa-review-category-%';
COMMIT;
SQL
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch BETWEEN $BASE_EPOCH AND $((BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-%';" \
        "0" \
        "cleaned behavior rows"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$CATEGORY_SOURCE_DAY' AND epoch BETWEEN $CATEGORY_BASE_EPOCH AND $((CATEGORY_BASE_EPOCH + 1800)) AND app_name LIKE '%qa-review-category-%';" \
        "0" \
        "cleaned current-day category rows"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note LIKE 'qa-review-personal-note:%';" \
        "0" \
        "cleaned daily review rows"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE app_name LIKE '${WEEKLY_ID_PREFIX}observation-%';" \
        "0" \
        "cleaned weekly behavior rows"
    assert_scalar \
        "SELECT COUNT(*) FROM daily_reviews WHERE personal_note LIKE '${WEEKLY_ID_PREFIX}note-%';" \
        "0" \
        "cleaned weekly daily reviews"
    assert_scalar \
        "SELECT COUNT(*) FROM learning_samples WHERE id LIKE '${WEEKLY_ID_PREFIX}%';" \
        "0" \
        "cleaned weekly learning samples"
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
