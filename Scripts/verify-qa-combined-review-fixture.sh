#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly FIXTURE="$SCRIPT_DIR/qa-combined-review-fixture.sh"
readonly TEMP_ROOT="$(mktemp -d /private/tmp/zoid-666-combined-review-fixture.XXXXXX)"
readonly DATABASE="$TEMP_ROOT/zoid-coach.sqlite"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

[[ -x "$FIXTURE" ]] || fail "fixture script is not executable"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

sqlite3 -batch "$DATABASE" <<'SQL'
PRAGMA user_version = 46;
CREATE TABLE behavior_records (
    source_day TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    time_label TEXT NOT NULL,
    app_name TEXT NOT NULL,
    window_title TEXT NOT NULL,
    url TEXT NOT NULL,
    has_screenshot INTEGER NOT NULL,
    screenshot_path TEXT,
    ingested_at TEXT NOT NULL,
    classification TEXT,
    classification_policy_version INTEGER,
    PRIMARY KEY(source_day, epoch)
);
CREATE TABLE daily_reviews (
    source_day TEXT PRIMARY KEY,
    hypothesis_state TEXT NOT NULL,
    confirmed_at_utc TEXT,
    updated_at_utc TEXT NOT NULL,
    personal_note TEXT,
    skipped_at_utc TEXT,
    deferred_until_utc TEXT
);
CREATE TABLE learning_samples (
    id TEXT PRIMARY KEY,
    sample_type TEXT NOT NULL,
    context_key TEXT NOT NULL,
    estimated_value REAL,
    actual_value REAL NOT NULL,
    local_minute_of_day INTEGER,
    timezone_identifier TEXT NOT NULL,
    evidence_id TEXT NOT NULL,
    occurred_at_utc TEXT NOT NULL,
    payload_json TEXT
);
CREATE TABLE weekly_review_experiments (
    id TEXT PRIMARY KEY,
    review_week_start TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    instruction TEXT NOT NULL,
    measurement TEXT NOT NULL,
    state TEXT NOT NULL,
    tracking_week_start TEXT,
    updated_at_utc TEXT NOT NULL
);
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES (
    '2026-07-12', 1783843200, '08:00', 'foreign-app', 'foreign-title', '',
    0, NULL, '2026-07-12T08:00:00Z', 'work', 1
);
INSERT INTO daily_reviews(
    source_day, hypothesis_state, confirmed_at_utc, updated_at_utc,
    personal_note, skipped_at_utc, deferred_until_utc
) VALUES (
    '2026-07-12', 'accepted', '2026-07-12T09:00:00Z', '2026-07-12T09:00:00Z',
    'foreign note', NULL, NULL
);
INSERT INTO weekly_review_experiments(
    id, review_week_start, title, instruction, measurement,
    state, tracking_week_start, updated_at_utc
) VALUES (
    'foreign-experiment', '2026-07-06', 'Foreign', 'Keep it', 'Count it',
    'proposed', NULL, '2026-07-12T09:00:00Z'
);
INSERT INTO learning_samples(
    id, sample_type, context_key, estimated_value, actual_value,
    local_minute_of_day, timezone_identifier, evidence_id, occurred_at_utc, payload_json
) VALUES (
    'foreign-learning', 'estimate', 'foreign-context', 20, 20,
    NULL, 'UTC', 'foreign-evidence', '2026-07-12T08:30:00Z', NULL
);
SQL

export ZOID_COACH_QA_REVIEW_SOURCE_DAY=2026-07-13
export ZOID_COACH_QA_CATEGORY_SOURCE_DAY=2026-07-14

"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
"$FIXTURE" assert-relaunch "$DATABASE"

[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM behavior_records WHERE app_name = 'foreign-app';")" == "1" ]] \
    || fail "prepare changed foreign behavior evidence"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM daily_reviews WHERE personal_note = 'foreign note';")" == "1" ]] \
    || fail "prepare changed foreign daily review"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM weekly_review_experiments WHERE id = 'foreign-experiment';")" == "1" ]] \
    || fail "prepare changed foreign weekly experiment"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM learning_samples WHERE id = 'foreign-learning';")" == "1" ]] \
    || fail "prepare changed foreign learning evidence"

"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" cleanup "$DATABASE"

[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM behavior_records;")" == "1" ]] \
    || fail "cleanup removed unowned behavior evidence"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM daily_reviews;")" == "1" ]] \
    || fail "cleanup removed unowned daily review"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM weekly_review_experiments;")" == "1" ]] \
    || fail "cleanup changed weekly experiments"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM learning_samples;")" == "1" ]] \
    || fail "cleanup removed unowned learning evidence"

grep -Fq "WEEKLY INPUT READY:" "$FIXTURE" \
    || fail "weekly derivation-input boundary is not documented"
grep -Fq "no pattern or experiment output was inserted" "$FIXTURE" \
    || fail "weekly output non-fabrication boundary is not documented"
! grep -Eq "INSERT INTO weekly_review_experiments|DELETE FROM weekly_review_experiments" "$FIXTURE" \
    || fail "fixture must not write derived weekly experiment output"
grep -Fq "NON-DISPLAY EXPECTATION" "$FIXTURE" \
    || fail "private evidence non-display expectation is not documented"

print -- "PASS: combined review fixture schema, transactions, idempotency, relaunch, privacy, and cleanup are deterministic"
print -- "OWNED: 20 behavior rows, 4 daily review rows, and 4 estimate learning samples"
print -- "DERIVATION READY: product runtime may derive exactly one estimate-accuracy pattern from 3 covered days and 4 eligible samples"
print -- "OMITTED: direct weekly pattern and experiment output because both are product-derived"
