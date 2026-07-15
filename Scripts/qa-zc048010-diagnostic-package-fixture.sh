#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly PACKAGE="${3:-}"
readonly SCRIPT_PATH="${0:A}"
readonly SOURCE_DAY="${ZOID_666_QA_ZC048010_DAY:-$(date '+%Y-%m-%d')}"
readonly EPOCH="${ZOID_666_QA_ZC048010_EPOCH:-$(date -j -f '%Y-%m-%d %H:%M:%S' "$SOURCE_DAY 12:48:10" '+%s')}"
readonly PREFIX="qa-zc048010-private"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
usage() {
    print -u2 -- "usage: $0 <prepare|assert-prepared|assert-package|cleanup|self-test> [database] [package]"
    exit 2
}
scalar() { sqlite3 -batch -noheader "$DATABASE" "$1"; }
assert_scalar() {
    local actual="$(scalar "$1")"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}
require_schema() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'behavior_records';" "1" "behavior_records table"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'daily_reviews';" "1" "daily_reviews table"
}
cleanup_rows() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch = $EPOCH AND app_name = '$PREFIX-credential';
DELETE FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note = '$PREFIX-conversation-payload';
COMMIT;
SQL
}
assert_prepared() {
    require_schema
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch = $EPOCH AND app_name = '$PREFIX-credential' AND window_title = '$PREFIX-title' AND url = '$PREFIX-url' AND screenshot_path = '$PREFIX-path';" "1" "private behavior fixture"
    assert_scalar "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '$SOURCE_DAY' AND personal_note = '$PREFIX-conversation-payload';" "1" "private review fixture"
}
prepare() {
    require_schema
    cleanup_rows
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification)
VALUES('$SOURCE_DAY', $EPOCH, '12:48', '$PREFIX-credential', '$PREFIX-title', '$PREFIX-url', 1, '$PREFIX-path', '2026-07-15T12:48:10Z', 'unknown');
INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc, personal_note)
VALUES('$SOURCE_DAY', 'pending', NULL, '2026-07-15T12:48:10Z', '$PREFIX-conversation-payload')
ON CONFLICT(source_day) DO UPDATE SET personal_note = excluded.personal_note, updated_at_utc = excluded.updated_at_utc;
COMMIT;
SQL
    assert_prepared
}
assert_package() {
    [[ -d "$PACKAGE" ]] || fail "diagnostic package is unavailable: $PACKAGE"
    local names="$(find "$PACKAGE" -mindepth 1 -maxdepth 1 -print | sed 's#^.*/##' | LC_ALL=C sort | tr '\n' ' ')"
    [[ "$names" == "README.txt counts.json manifest.json " ]] || fail "package artifacts differ: $names"
    jq -e '.formatVersion == 1 and .files == ["README.txt", "manifest.json", "counts.json"]' "$PACKAGE/manifest.json" >/dev/null \
        || fail "manifest contract differs"
    jq -e 'has("schemaVersion") and has("actionCounts") and has("sourceCounts") and has("promptCounts") and has("meetingCounts")' "$PACKAGE/counts.json" >/dev/null \
        || fail "counts contract differs"
    grep -Fqx 'Screenshots are excluded.' "$PACKAGE/README.txt" || fail "screenshot exclusion is absent"
    grep -Fqx 'Credentials are excluded.' "$PACKAGE/README.txt" || fail "credential exclusion is absent"
    if rg -n "$PREFIX|private-title|private-url|private-path|conversation-payload|credential" "$PACKAGE" >/dev/null; then
        fail "private fixture content leaked into the package"
    fi
    print -- "PASS: ZC-048-010 package contents and privacy exclusions"
}
self_test() {
    local root="$(mktemp -d "${TMPDIR:-/tmp}/zc048010-fixture.XXXXXX")"
    local database="$root/fixture.sqlite"
    local package="$root/Fixture.zoiddiagnostics"
    trap "rm -rf -- '$root'" EXIT
    sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_reviews(source_day TEXT PRIMARY KEY, hypothesis_state TEXT NOT NULL, confirmed_at_utc TEXT, updated_at_utc TEXT NOT NULL, personal_note TEXT);
SQL
    ZOID_666_QA_ZC048010_DAY=2026-07-15 ZOID_666_QA_ZC048010_EPOCH=1784112490 "$SCRIPT_PATH" prepare "$database"
    ZOID_666_QA_ZC048010_DAY=2026-07-15 ZOID_666_QA_ZC048010_EPOCH=1784112490 "$SCRIPT_PATH" assert-prepared "$database"
    mkdir "$package"
    cat >"$package/README.txt" <<'TEXT'
Zoid 666 redacted diagnostic package
Screenshots are excluded.
Credentials are excluded.
TEXT
    print -r -- '{"formatVersion":1,"files":["README.txt","manifest.json","counts.json"]}' >"$package/manifest.json"
    print -r -- '{"schemaVersion":1,"actionCounts":{},"sourceCounts":{},"promptCounts":{},"meetingCounts":{}}' >"$package/counts.json"
    ZOID_666_QA_ZC048010_DAY=2026-07-15 ZOID_666_QA_ZC048010_EPOCH=1784112490 "$SCRIPT_PATH" assert-package "$database" "$package"
    ZOID_666_QA_ZC048010_DAY=2026-07-15 ZOID_666_QA_ZC048010_EPOCH=1784112490 "$SCRIPT_PATH" cleanup "$database"
    print -- "PASS: ZC-048-010 fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == self-test ]]; then self_test; exit 0; fi
[[ -n "$DATABASE" && -f "$DATABASE" ]] || usage
command -v sqlite3 >/dev/null || fail "sqlite3 is required"
case "$COMMAND" in
    prepare) prepare ;;
    assert-prepared) assert_prepared ;;
    assert-package) [[ -n "$PACKAGE" ]] || usage; assert_prepared; assert_package ;;
    cleanup) require_schema; cleanup_rows; assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$SOURCE_DAY' AND epoch = $EPOCH AND app_name = '$PREFIX-credential';" "0" "private behavior cleanup" ;;
    *) usage ;;
esac
