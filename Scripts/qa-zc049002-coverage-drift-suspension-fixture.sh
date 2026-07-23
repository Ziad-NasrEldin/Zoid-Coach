#!/bin/zsh
set -euo pipefail

readonly LIMITED_EXPLANATION='Limited coverage: the latest Screenwatch checkpoint is stale.'
readonly CURRENT_EXPLANATION='Screenwatch coverage is current.'
readonly LIMITED_SOURCE_DETAIL='No current Screenwatch observations are available.'
readonly CURRENT_SOURCE_DETAIL='Screenwatch observations are current.'

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "Usage: $0 self-test"
    print -u2 -- "       $0 snapshot|set-limited|set-current|assert-limited|assert-current|restore DATABASE BACKUP DAY"
    exit 64
}

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local actual
    actual="$(scalar "$1")" || fail "could not read $3"
    [[ "$actual" == "$2" ]] || fail "$3: expected '$2', got '$actual'"
}

require_inputs() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    [[ "$DAY" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] || fail "day must use YYYY-MM-DD"
    command -v sqlite3 >/dev/null || fail "sqlite3 is required"
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'today_snapshots';" 1 "today_snapshots table"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('today_snapshots') WHERE name IN ('day_key', 'payload', 'updated_at');" 3 "today_snapshots schema"
}

snapshot() {
    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key = '$DAY' AND json_valid(CAST(payload AS TEXT));" 1 "valid snapshot for $DAY"
    umask 077
    {
        print -r -- "ZC049002-V1"
        scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '$DAY';"
        scalar "SELECT hex(CAST(updated_at AS BLOB)) FROM today_snapshots WHERE day_key = '$DAY';"
    } > "$BACKUP"
    [[ "$(sed -n '2p' "$BACKUP")" =~ '^[0-9A-F]+$' ]] || fail "snapshot backup is invalid"
    print -- "PASS: saved exact $DAY snapshot"
}

set_state() {
    local limited_json explanation source_state source_detail
    if [[ "$1" == limited ]]; then
        limited_json=true
        explanation="$LIMITED_EXPLANATION"
        source_state=stale
        source_detail="$LIMITED_SOURCE_DETAIL"
    else
        limited_json=false
        explanation="$CURRENT_EXPLANATION"
        source_state=healthy
        source_detail="$CURRENT_SOURCE_DETAIL"
    fi

    assert_scalar "SELECT COUNT(*) FROM today_snapshots WHERE day_key = '$DAY';" 1 "snapshot for $DAY"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
UPDATE today_snapshots
SET payload = CAST(json_set(
        CAST(payload AS TEXT),
        '$.coverage', json_object(
            'isLimited', json('$limited_json'),
            'explanation', '$explanation',
            'lastObservationAt', json('null')
        ),
        '$.sourceFreshnessExplanation', '$explanation',
        '$.sources', json_array(json_object(
            'sourceID', 'screenwatch',
            'state', '$source_state',
            'detail', '$source_detail',
            'lastUpdatedAt', json('null')
        ))
    ) AS BLOB),
    updated_at = '2026-07-15T09:00:00Z'
WHERE day_key = '$DAY';
COMMIT;
SQL
    assert_state "$1"
}

assert_state() {
    local expected_limited expected_explanation expected_state
    if [[ "$1" == limited ]]; then
        expected_limited=1
        expected_explanation="$LIMITED_EXPLANATION"
        expected_state=stale
    else
        expected_limited=0
        expected_explanation="$CURRENT_EXPLANATION"
        expected_state=healthy
    fi
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.coverage.isLimited') FROM today_snapshots WHERE day_key = '$DAY';" "$expected_limited" "coverage limited flag"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.coverage.explanation') FROM today_snapshots WHERE day_key = '$DAY';" "$expected_explanation" "coverage explanation"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.sources[0].sourceID') FROM today_snapshots WHERE day_key = '$DAY';" screenwatch "coverage source"
    assert_scalar "SELECT json_extract(CAST(payload AS TEXT), '$.sources[0].state') FROM today_snapshots WHERE day_key = '$DAY';" "$expected_state" "coverage source state"
    print -- "PASS: $DAY has $1 Screenwatch coverage"
}

restore() {
    [[ -f "$BACKUP" ]] || fail "backup does not exist: $BACKUP"
    [[ "$(sed -n '1p' "$BACKUP")" == ZC049002-V1 ]] || fail "backup marker is invalid"
    local payload_hex updated_hex
    payload_hex="$(sed -n '2p' "$BACKUP")"
    updated_hex="$(sed -n '3p' "$BACKUP")"
    [[ "$payload_hex" =~ '^[0-9A-F]+$' && "$updated_hex" =~ '^[0-9A-F]+$' ]] || fail "backup content is invalid"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
UPDATE today_snapshots
SET payload = X'$payload_hex', updated_at = CAST(X'$updated_hex' AS TEXT)
WHERE day_key = '$DAY';
COMMIT;
SQL
    assert_scalar "SELECT hex(payload) FROM today_snapshots WHERE day_key = '$DAY';" "$payload_hex" "exact payload restoration"
    assert_scalar "SELECT hex(CAST(updated_at AS BLOB)) FROM today_snapshots WHERE day_key = '$DAY';" "$updated_hex" "exact timestamp restoration"
    print -- "PASS: restored exact $DAY snapshot"
}

self_test() {
    local root original_hex
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc049002-fixture.XXXXXX")"
    trap "rm -rf ${(q)root}" EXIT
    DATABASE="$root/qa.sqlite3"
    BACKUP="$root/snapshot.backup"
    DAY=2026-07-15
    sqlite3 -batch "$DATABASE" <<'SQL'
CREATE TABLE today_snapshots(day_key TEXT PRIMARY KEY, payload BLOB NOT NULL, updated_at TEXT NOT NULL);
INSERT INTO today_snapshots VALUES(
    '2026-07-15',
    CAST('{"coverage":{"isLimited":false,"explanation":"Original","lastObservationAt":null},"sourceFreshnessExplanation":"Original","sources":[]}' AS BLOB),
    'original-time'
);
SQL
    original_hex="$(sqlite3 -batch -noheader "$DATABASE" "SELECT hex(payload) || ':' || hex(CAST(updated_at AS BLOB)) FROM today_snapshots;")"
    require_inputs
    snapshot
    set_state limited
    set_state current
    restore
    [[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT hex(payload) || ':' || hex(CAST(updated_at AS BLOB)) FROM today_snapshots;")" == "$original_hex" ]] || fail "self-test did not restore exact bytes"
    print -- "PASS: ZC-049-002 fixture self-test"
}

COMMAND="${1:-}"
if [[ "$COMMAND" == self-test ]]; then
    self_test
    exit 0
fi
(( $# == 4 )) || usage
DATABASE="$2"
BACKUP="$3"
DAY="$4"
require_inputs
case "$COMMAND" in
    snapshot) snapshot ;;
    set-limited) set_state limited ;;
    set-current) set_state current ;;
    assert-limited) assert_state limited ;;
    assert-current) assert_state current ;;
    restore) restore ;;
    *) usage ;;
esac
