#!/bin/zsh
set -euo pipefail

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

assert_scalar() {
    local database="$1"
    local sql="$2"
    local expected="$3"
    local description="$4"
    local actual
    actual="$(sqlite3 "$database" "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$description: expected $expected, got $actual"
}

prepare() {
    local database="$1"
    sqlite3 "$database" <<'SQL'
INSERT INTO source_tasks
    (source_id, title, priority, is_completed, updated_at, source_kind, declared_context)
VALUES
    ('qa-zc061001-technical', 'QA ZC-061-001 technical task', 0, 0, datetime('now'), 'local', 'technical'),
    ('qa-zc061001-general', 'QA ZC-061-001 general boundary', 0, 0, datetime('now'), 'local', NULL)
ON CONFLICT(source_id) DO UPDATE SET
    title = excluded.title,
    is_completed = 0,
    updated_at = excluded.updated_at,
    source_kind = excluded.source_kind,
    declared_context = excluded.declared_context;
SQL
}

assert_prepared() {
    local database="$1"
    assert_scalar "$database" "SELECT COUNT(*) FROM pragma_table_info('source_tasks') WHERE name = 'declared_context';" "1" "nullable migration column"
    assert_scalar "$database" "SELECT declared_context FROM source_tasks WHERE source_id = 'qa-zc061001-technical';" "technical" "technical declaration"
    assert_scalar "$database" "SELECT declared_context IS NULL FROM source_tasks WHERE source_id = 'qa-zc061001-general';" "1" "legacy general boundary"
}

assert_created() {
    local database="$1"
    assert_scalar "$database" "SELECT COUNT(*) FROM source_tasks WHERE title = 'QA ZC-061-001 signed user technical task' AND source_kind = 'local' AND declared_context = 'technical' AND is_completed = 0;" "1" "user-created technical task"
}

cleanup() {
    local database="$1"
    sqlite3 "$database" "DELETE FROM source_tasks WHERE source_id LIKE 'qa-zc061001-%' OR title = 'QA ZC-061-001 signed user technical task';"
}

self_test() {
    local root database
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc061001-fixture.XXXXXX")"
    database="$root/fixture.sqlite"
    trap "rm -rf -- ${root:q}" EXIT
    sqlite3 "$database" <<'SQL'
CREATE TABLE source_tasks (
    source_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    priority INTEGER NOT NULL,
    is_completed INTEGER NOT NULL,
    updated_at TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    declared_context TEXT
);
SQL
    prepare "$database"
    assert_prepared "$database"
    cleanup "$database"
    assert_scalar "$database" "SELECT COUNT(*) FROM source_tasks;" "0" "fixture cleanup"
    print -- "PASS: ZC-061-001 technical-task fixture self-test"
}

case "${1:-}" in
    --self-test)
        self_test
        ;;
    prepare|assert-prepared|assert-created|cleanup)
        (( $# == 2 )) || fail "usage: $0 ${1:-command} <database>"
        [[ -f "$2" ]] || fail "database does not exist: $2"
        case "$1" in
            prepare) prepare "$2" ;;
            assert-prepared) assert_prepared "$2" ;;
            assert-created) assert_created "$2" ;;
            cleanup) cleanup "$2" ;;
        esac
        ;;
    *)
        fail "usage: $0 --self-test | <prepare|assert-prepared|assert-created|cleanup> <database>"
        ;;
esac
