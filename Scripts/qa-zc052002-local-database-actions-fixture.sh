#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SCRIPT_DIR="${SCRIPT_PATH:h}"
readonly MANIFEST="$SCRIPT_DIR/fixtures/zc-052-002-local-database-actions.json"
readonly COMMAND="${1:-}"
readonly EXPECTED_SCHEMA_VERSION="$(jq -r '.expectedSchemaVersion' "$MANIFEST")"
readonly OUTDATED_SCHEMA_VERSION="$(jq -r '.outdatedSchemaVersion' "$MANIFEST")"
readonly PRIVATE_SENTINEL="$(jq -r '.privateDatabaseSentinel' "$MANIFEST")"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: ${0:t} <capture|set-read-only|set-missing|set-unverified|assert-healthy|assert-read-only|assert-missing|assert-unverified|restore|cleanup> <database> [backup-root] | --self-test"
    exit 2
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

assert_isolated_database() {
    local database="$1"
    [[ "$database" == /private/tmp/* ]] || fail "database must be under /private/tmp"
    [[ "$database" == */Application\ Support/Zoid\ 666/zoid-coach.sqlite ]] \
        || fail "database must use the isolated Zoid 666 QA layout"
    [[ ! -L "$database" && ! -L "${database:h}" ]] || fail "database path must not traverse a symlink"
}

assert_not_in_use() {
    local database="$1"
    local path
    for path in "$database" "$database-wal" "$database-shm"; do
        [[ ! -e "$path" ]] && continue
        ! lsof "$path" >/dev/null 2>&1 || fail "database bundle is still open: $path"
    done
}

remove_live_bundle() {
    local database="$1"
    rm -f -- "$database" "$database-wal" "$database-shm"
}

backup_name() {
    case "$1" in
        main) print -- "database" ;;
        wal) print -- "database-wal" ;;
        shm) print -- "database-shm" ;;
        *) fail "unknown backup component: $1" ;;
    esac
}

live_path() {
    local database="$1"
    case "$2" in
        main) print -- "$database" ;;
        wal) print -- "$database-wal" ;;
        shm) print -- "$database-shm" ;;
        *) fail "unknown live component: $2" ;;
    esac
}

assert_healthy() {
    local database="$1"
    [[ -f "$database" ]] || fail "healthy database is missing"
    [[ "$(sqlite3 -batch -noheader "$database" 'PRAGMA quick_check(1);')" == "ok" ]] \
        || fail "healthy database failed quick_check"
    [[ "$(sqlite3 -batch -noheader "$database" 'SELECT COALESCE(MAX(version), 0) FROM schema_migrations;')" == "$EXPECTED_SCHEMA_VERSION" ]] \
        || fail "healthy database is not on schema $EXPECTED_SCHEMA_VERSION"
    print -- "PASS: healthy current-schema database is present"
}

capture() {
    local database="$1"
    local backup_root="$2"
    [[ ! -e "$backup_root" ]] || fail "backup namespace already exists: $backup_root"
    assert_not_in_use "$database"
    assert_healthy "$database" >/dev/null
    mkdir -p "$backup_root"
    sqlite3 -batch "$database" ".backup '$backup_root/logical-current.sqlite'"
    [[ "$(sqlite3 -batch -noheader "$backup_root/logical-current.sqlite" 'PRAGMA quick_check(1);')" == "ok" ]] \
        || fail "logical fixture source failed quick_check"
    local component source destination presence digest
    : > "$backup_root/manifest.tsv"
    for component in main wal shm; do
        source="$(live_path "$database" "$component")"
        destination="$backup_root/$(backup_name "$component")"
        if [[ -e "$source" ]]; then
            cp -p "$source" "$destination"
            presence="present"
            digest="$(sha256 "$destination")"
        else
            presence="absent"
            digest="-"
        fi
        print -- "$component\t$presence\t$digest" >> "$backup_root/manifest.tsv"
    done
    print -- "PASS: captured exact database, WAL, and SHM presence and bytes"
}

verify_backup() {
    local backup_root="$1"
    [[ -f "$backup_root/manifest.tsv" ]] || fail "backup manifest is unavailable"
    [[ -f "$backup_root/logical-current.sqlite" ]] || fail "logical fixture source is unavailable"
    [[ "$(sqlite3 -batch -noheader "$backup_root/logical-current.sqlite" 'SELECT COALESCE(MAX(version), 0) FROM schema_migrations;')" == "$EXPECTED_SCHEMA_VERSION" ]] \
        || fail "logical fixture source is not on the expected schema"
    local component presence expected_digest destination
    while IFS=$'\t' read -r component presence expected_digest; do
        destination="$backup_root/$(backup_name "$component")"
        case "$presence" in
            present)
                [[ -f "$destination" ]] || fail "backup component is missing: $component"
                [[ "$(sha256 "$destination")" == "$expected_digest" ]] \
                    || fail "backup component changed: $component"
                ;;
            absent)
                [[ ! -e "$destination" ]] || fail "originally absent backup component appeared: $component"
                ;;
            *) fail "invalid backup presence for $component" ;;
        esac
    done < "$backup_root/manifest.tsv"
}

set_read_only_state() {
    local database="$1"
    local backup_root="$2"
    local temporary="$database.zc052002-outdated.tmp"
    remove_live_bundle "$database"
    rm -f -- "$temporary"
    cp "$backup_root/logical-current.sqlite" "$temporary"
    sqlite3 -batch "$temporary" <<SQL
PRAGMA journal_mode=DELETE;
DELETE FROM schema_migrations WHERE version = $EXPECTED_SCHEMA_VERSION;
CREATE TABLE private_fixture(value TEXT NOT NULL);
INSERT INTO private_fixture(value) VALUES ('$PRIVATE_SENTINEL');
SQL
    mv "$temporary" "$database"
    assert_read_only "$database" >/dev/null
    print -- "PASS: presented a readable but outdated isolated database"
}

assert_read_only() {
    local database="$1"
    [[ -f "$database" ]] || fail "read-only fixture database is missing"
    [[ "$(sqlite3 -batch -noheader "$database" 'PRAGMA quick_check(1);')" == "ok" ]] \
        || fail "read-only fixture database failed quick_check"
    [[ "$(sqlite3 -batch -noheader "$database" 'SELECT COALESCE(MAX(version), 0) FROM schema_migrations;')" == "$OUTDATED_SCHEMA_VERSION" ]] \
        || fail "read-only fixture did not preserve the outdated schema"
    [[ "$(sqlite3 -batch -noheader "$database" 'SELECT value FROM private_fixture;')" == "$PRIVATE_SENTINEL" ]] \
        || fail "read-only fixture private sentinel is unavailable"
    print -- "PASS: readable outdated database state is intact"
}

set_missing_state() {
    local database="$1"
    remove_live_bundle "$database"
    assert_missing "$database" >/dev/null
    print -- "PASS: presented a missing isolated database path"
}

assert_missing() {
    local database="$1"
    [[ ! -e "$database" && ! -e "$database-wal" && ! -e "$database-shm" ]] \
        || fail "missing state still contains a database bundle component"
    print -- "PASS: database bundle is missing"
}

set_unverified_state() {
    local database="$1"
    local temporary="$database.zc052002-unverified.tmp"
    remove_live_bundle "$database"
    print -rn -- "$PRIVATE_SENTINEL" > "$temporary"
    mv "$temporary" "$database"
    assert_unverified "$database" >/dev/null
    print -- "PASS: presented an unverified non-SQLite database without exposing its content"
}

assert_unverified() {
    local database="$1"
    [[ -f "$database" ]] || fail "unverified fixture database is missing"
    [[ "$(<"$database")" == "$PRIVATE_SENTINEL" ]] || fail "unverified fixture bytes changed"
    if sqlite3 -batch "$database" 'PRAGMA quick_check(1);' >/dev/null 2>&1; then
        fail "unverified fixture was accepted as a SQLite database"
    fi
    print -- "PASS: unverified database bytes remain intentionally unreadable"
}

restore() {
    local database="$1"
    local backup_root="$2"
    assert_not_in_use "$database"
    verify_backup "$backup_root"
    remove_live_bundle "$database"
    local component presence expected_digest source destination
    while IFS=$'\t' read -r component presence expected_digest; do
        [[ "$presence" == "present" ]] || continue
        source="$backup_root/$(backup_name "$component")"
        destination="$(live_path "$database" "$component")"
        cp -p "$source" "$destination"
        [[ "$(sha256 "$destination")" == "$expected_digest" ]] \
            || fail "restored component does not match captured bytes: $component"
    done < "$backup_root/manifest.tsv"
    assert_healthy "$database" >/dev/null
    print -- "PASS: restored exact original database bundle bytes"
}

assert_restored() {
    local database="$1"
    local backup_root="$2"
    verify_backup "$backup_root"
    local component presence expected_digest destination
    while IFS=$'\t' read -r component presence expected_digest; do
        destination="$(live_path "$database" "$component")"
        if [[ "$presence" == "present" ]]; then
            [[ -f "$destination" && "$(sha256 "$destination")" == "$expected_digest" ]] \
                || fail "live component differs from captured bytes: $component"
        else
            [[ ! -e "$destination" ]] || fail "originally absent component exists after restore: $component"
        fi
    done < "$backup_root/manifest.tsv"
    print -- "PASS: live database bundle is byte-identical to the captured original"
}

cleanup() {
    local database="$1"
    local backup_root="$2"
    assert_not_in_use "$database"
    assert_restored "$database" "$backup_root" >/dev/null
    rm -rf -- "$backup_root"
    [[ ! -e "$backup_root" ]] || fail "backup root remains after cleanup"
    print -- "PASS: removed fixture backup after byte-exact restoration"
}

run_self_test() {
    local root="/private/tmp/zoid-666-zc052002-fixture-self-test-$$"
    local database="$root/Application Support/Zoid 666/zoid-coach.sqlite"
    local backup_root="$root/original-bytes"
    trap "rm -rf -- '$root'" EXIT
    mkdir -p "${database:h}"
    sqlite3 -batch "$database" <<SQL
CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
WITH RECURSIVE versions(value) AS (
    SELECT 1
    UNION ALL
    SELECT value + 1 FROM versions WHERE value < $EXPECTED_SCHEMA_VERSION
)
INSERT INTO schema_migrations(version, applied_at)
SELECT value, '2026-07-15T00:00:00Z' FROM versions;
CREATE TABLE original_fixture(value TEXT NOT NULL);
INSERT INTO original_fixture(value) VALUES ('original-private-bytes');
SQL
    assert_isolated_database "$database"
    capture "$database" "$backup_root" >/dev/null
    set_read_only_state "$database" "$backup_root" >/dev/null
    assert_read_only "$database" >/dev/null
    set_missing_state "$database" >/dev/null
    assert_missing "$database" >/dev/null
    set_unverified_state "$database" >/dev/null
    assert_unverified "$database" >/dev/null
    restore "$database" "$backup_root" >/dev/null
    assert_restored "$database" "$backup_root" >/dev/null
    cleanup "$database" "$backup_root" >/dev/null
    [[ "$(sqlite3 -batch -noheader "$database" 'SELECT value FROM original_fixture;')" == "original-private-bytes" ]] \
        || fail "self-test did not restore original private content"
    print -- "PASS: ZC-052-002 fixture state, safety, and byte-restoration self-test"
}

[[ -f "$MANIFEST" ]] || fail "fixture manifest is unavailable"
[[ "$EXPECTED_SCHEMA_VERSION" == <-> && "$OUTDATED_SCHEMA_VERSION" == <-> ]] \
    || fail "fixture schema versions must be numeric"
(( OUTDATED_SCHEMA_VERSION < EXPECTED_SCHEMA_VERSION )) \
    || fail "outdated schema version must precede expected schema version"

if [[ "$COMMAND" == "--self-test" || "$COMMAND" == "self-test" ]]; then
    run_self_test
    exit 0
fi

(( $# >= 2 && $# <= 3 )) || usage
readonly DATABASE="$2"
readonly QA_ROOT="${DATABASE:h:h:h}"
readonly BACKUP_ROOT="${3:-$QA_ROOT/.zc052002-original-bytes}"
assert_isolated_database "$DATABASE"
[[ "$BACKUP_ROOT" == "$QA_ROOT"/* ]] || fail "backup root must remain inside the isolated QA root"
[[ ! -L "$BACKUP_ROOT" ]] || fail "backup root must not be a symlink"

case "$COMMAND" in
    capture) capture "$DATABASE" "$BACKUP_ROOT" ;;
    set-read-only) [[ -d "$BACKUP_ROOT" ]] || fail "capture original bytes first"; set_read_only_state "$DATABASE" "$BACKUP_ROOT" ;;
    set-missing) [[ -d "$BACKUP_ROOT" ]] || fail "capture original bytes first"; set_missing_state "$DATABASE" ;;
    set-unverified) [[ -d "$BACKUP_ROOT" ]] || fail "capture original bytes first"; set_unverified_state "$DATABASE" ;;
    assert-healthy) assert_healthy "$DATABASE" ;;
    assert-read-only) assert_read_only "$DATABASE" ;;
    assert-missing) assert_missing "$DATABASE" ;;
    assert-unverified) assert_unverified "$DATABASE" ;;
    restore) restore "$DATABASE" "$BACKUP_ROOT" ;;
    assert-restored) assert_restored "$DATABASE" "$BACKUP_ROOT" ;;
    cleanup) cleanup "$DATABASE" "$BACKUP_ROOT" ;;
    *) usage ;;
esac
