#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly ARGUMENT_ONE="${2:-}"
readonly ARGUMENT_TWO="${3:-}"
readonly SCRIPT_PATH="${0:A}"
readonly TASK_ID="qa-zc011007-invalid-estimate"
readonly TASK_TITLE="QA invalid estimate matrix"
readonly PRIVATE_NOTE="qa-zc011007-private-estimate-note"
readonly DAY_KEY="${ZOID_666_QA_ZC011007_DAY:-$(date '+%Y-%m-%d')}"
readonly DATABASE_SUFFIX="/Application Support/Zoid 666/zoid-coach.sqlite"
readonly ROOT_MARKER_SUFFIX="/QA Control/zc011007-fixture-root"
typeset -g CANONICAL_DATABASE=""
typeset -g CANONICAL_DATABASE_ID=""

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

require_qa_database() {
    local lexical_database="${ARGUMENT_ONE:a}"
    local resolved_database="${ARGUMENT_ONE:A}"
    [[ "$lexical_database" == "$resolved_database" && ! -L "$ARGUMENT_ONE" ]] \
        || fail "database path must be canonical and must not be a symlink"
    [[ "$resolved_database" == /private/tmp/zoid-666-zc011007-*"$DATABASE_SUFFIX" ]] \
        || fail "database must be the canonical file inside a ZC-011-007 isolated QA root"
    local qa_root="${resolved_database%$DATABASE_SUFFIX}"
    [[ "$qa_root" == "${qa_root:A}" ]] || fail "QA root must not traverse a symlink"
    local marker="$qa_root$ROOT_MARKER_SUFFIX"
    [[ -f "$marker" && ! -L "$marker" && "$(<"$marker")" == "$qa_root" ]] \
        || fail "database root is not claimed by this ZC-011-007 fixture"
    CANONICAL_DATABASE="$resolved_database"
    CANONICAL_DATABASE_ID="$(stat -f '%d:%i' "$CANONICAL_DATABASE")"
}

assert_database_identity() {
    [[ -n "$CANONICAL_DATABASE" && -f "$CANONICAL_DATABASE" && ! -L "$CANONICAL_DATABASE" ]] \
        || fail "canonical database disappeared or became a symlink"
    [[ "${CANONICAL_DATABASE:A}" == "$CANONICAL_DATABASE" ]] \
        || fail "canonical database resolved outside its owned root"
    [[ "$(stat -f '%d:%i' "$CANONICAL_DATABASE")" == "$CANONICAL_DATABASE_ID" ]] \
        || fail "canonical database identity changed during fixture operation"
}

usage() {
    print -u2 -- "usage: $0 <prepare|assert-unmutated|assert-valid|cleanup|snapshot-root|restore-root|assert-root-restored|self-test> [database-or-root] [snapshot]"
    exit 2
}

scalar() {
    assert_database_identity
    sqlite3 -batch -noheader "$CANONICAL_DATABASE" "$1"
}

assert_scalar() {
    local sql="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(scalar "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

require_table() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$1';" "1" "$1 table"
}

require_column() {
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('$1') WHERE name = '$2';" "1" "$1.$2 column"
}

validate_schema() {
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals; do
        require_table "$table"
    done
    require_column source_tasks source_kind
    require_column daily_plan_entries estimate_minutes
    require_column daily_plan_entries estimate_is_uncertain
    require_column task_execution_states state
}

assert_owned_task() {
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND title = '$TASK_TITLE' AND source_kind = 'local' AND is_completed = 0;" "1" "owned local task"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID' AND rank = 1 AND is_main_objective = 1;" "1" "owned agent-writable planned main objective"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'ready';" "1" "owned ready execution state"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "owned interval absence"
}

assert_unmutated() {
    validate_schema
    assert_owned_task
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID' AND estimate_minutes IS NULL AND estimate_is_uncertain = 0;" "1" "invalid input did not mutate estimate"
}

assert_valid() {
    validate_schema
    assert_owned_task
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$DAY_KEY' AND reminder_id = '$TASK_ID' AND estimate_minutes = 25 AND estimate_is_uncertain = 0;" "1" "valid recovery persisted 25 minutes"
}

prepare() {
    validate_schema
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "unused source-task namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';" "0" "unused plan namespace"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;" "0" "clean active-session baseline"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    assert_database_identity
    sqlite3 -batch "$CANONICAL_DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(source_id, title, due_at, priority, is_completed, updated_at, notes, list_id, list_name, modified_at, source_hash, source_kind)
VALUES('$TASK_ID', '$TASK_TITLE', '$DAY_KEY' || 'T12:00:00Z', 1, 0, '$timestamp', '$PRIVATE_NOTE', NULL, 'Zoid 666 QA', '$timestamp', '$TASK_ID', 'local');
INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, estimate_is_uncertain)
VALUES('$DAY_KEY', '$TASK_ID', 1, 1, NULL, '$timestamp', 'ZC-011-007 invalid estimate fixture', 100, 0, NULL, NULL, 0);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES('$TASK_ID', 'ready', '$timestamp');
COMMIT;
SQL
    assert_unmutated
}

cleanup() {
    validate_schema
    assert_database_identity
    sqlite3 -batch "$CANONICAL_DATABASE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
PRAGMA foreign_keys = ON;
SQL
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "owned source cleanup"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';" "0" "owned plan cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID';" "0" "owned state cleanup"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID';" "0" "owned interval cleanup"
}

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc011007-* ]] || fail "refusing non-ZC-011-007 isolated root: $root"
    [[ "$root" != "/private/tmp" && "$root" != "/" ]] || fail "refusing unsafe root: $root"
}

root_manifest() {
    local root="${1:A}"
    (
        cd "$root"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r entry; do
            /usr/bin/shasum -a 256 "$entry"
        done
        find . -type l -print | LC_ALL=C sort | while IFS= read -r entry; do
            print -r -- "SYMLINK $entry -> $(readlink "$entry")"
        done
    )
}

snapshot_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$snapshot" == /private/tmp/zoid-666-zc011007-* ]] || fail "snapshot must use isolated ZC-011-007 namespace"
    [[ ! -e "$snapshot" && ! -e "$snapshot.zc011007-target" ]] || fail "snapshot already exists"
    local marker="$qa_root$ROOT_MARKER_SUFFIX"
    mkdir -p "${marker:h}"
    [[ ! -L "$marker" ]] || fail "fixture root marker must not be a symlink"
    print -r -- "$qa_root" > "$marker"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc011007-target"
    root_manifest "$snapshot" > "$snapshot.zc011007-manifest"
    [[ -s "$snapshot.zc011007-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated ZC-011-007 QA root"
}

restore_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc011007-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc011007-target")" == "$qa_root" ]] || fail "snapshot target does not match QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc011007-restored-manifest"
    cmp -s "$snapshot.zc011007-manifest" "$snapshot.zc011007-restored-manifest" || fail "restored QA root differs from baseline"
    print -- "PASS: restored isolated ZC-011-007 QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -f "$snapshot.zc011007-manifest" ]] || fail "snapshot manifest is missing"
    local current
    current="$(mktemp /private/tmp/zoid-666-zc011007-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc011007-manifest" "$current" || fail "current QA root differs from byte baseline"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated ZC-011-007 QA root matches byte baseline"
}

self_test() {
    typeset -g SELF_TEST_ROOT
    SELF_TEST_ROOT="$(mktemp -d "/private/tmp/zoid-666-zc011007-fixture-self-test.XXXXXX")"
    local database="$SELF_TEST_ROOT$DATABASE_SUFFIX"
    local unrelated_database="$SELF_TEST_ROOT/unrelated.sqlite"
    local non_qa_database="/private/tmp/zc011007-non-qa-${SELF_TEST_ROOT:t}.sqlite"
    local timestamp="2026-07-15T06:00:00Z"
    local self_test_suffix="${SELF_TEST_ROOT:t}"
    local qa_root="/private/tmp/zoid-666-zc011007-fixture-self-test-root-$self_test_suffix"
    local database_snapshot="/private/tmp/zoid-666-zc011007-fixture-db-snapshot-$self_test_suffix"
    local root_snapshot="/private/tmp/zoid-666-zc011007-fixture-root-snapshot-$self_test_suffix"
    trap 'rm -rf -- "${SELF_TEST_ROOT:-}" "$qa_root" "$database_snapshot" "$database_snapshot".zc011007-*(N) "$root_snapshot" "$root_snapshot".zc011007-*(N) "$non_qa_database"' EXIT
    mkdir -p "${database:h}"
    sqlite3 -batch "$database" <<SQL
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, due_at TEXT, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, modified_at TEXT, source_hash TEXT, source_kind TEXT NOT NULL DEFAULT 'reminders');
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, updated_at TEXT NOT NULL, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
SQL
    "$SCRIPT_PATH" snapshot-root "$SELF_TEST_ROOT" "$database_snapshot"
    cp "$database" "$unrelated_database"
    local unrelated_hash_before="$(shasum -a 256 "$unrelated_database" | awk '{print $1}')"
    if "$SCRIPT_PATH" prepare "$unrelated_database" >/dev/null 2>&1; then
        fail "fixture accepted an unrelated database inside the isolated QA namespace"
    fi
    [[ "$(shasum -a 256 "$unrelated_database" | awk '{print $1}')" == "$unrelated_hash_before" ]] \
        || fail "rejected in-namespace unrelated database was mutated"
    cp "$database" "$non_qa_database"
    local non_qa_hash_before="$(shasum -a 256 "$non_qa_database" | awk '{print $1}')"
    if "$SCRIPT_PATH" prepare "$non_qa_database" >/dev/null 2>&1; then
        fail "fixture accepted a database outside the isolated QA namespace"
    fi
    [[ "$(shasum -a 256 "$non_qa_database" | awk '{print $1}')" == "$non_qa_hash_before" ]] \
        || fail "rejected non-QA database was mutated"
    local original_database="$database.original"
    mv "$database" "$original_database"
    ln -s "$non_qa_database" "$database"
    if "$SCRIPT_PATH" prepare "$database" >/dev/null 2>&1; then
        fail "fixture accepted a symlink swap at the canonical database path"
    fi
    [[ "$(shasum -a 256 "$non_qa_database" | awk '{print $1}')" == "$non_qa_hash_before" ]] \
        || fail "rejected symlink target was mutated"
    rm "$database"
    mv "$original_database" "$database"
    "$SCRIPT_PATH" prepare "$database"
    "$SCRIPT_PATH" assert-unmutated "$database"
    sqlite3 -batch "$database" "UPDATE daily_plan_entries SET estimate_minutes = 25, updated_at = '$timestamp' WHERE reminder_id = '$TASK_ID';"
    "$SCRIPT_PATH" assert-valid "$database"
    "$SCRIPT_PATH" cleanup "$database"
    rm -rf -- "$qa_root" "$root_snapshot" "$root_snapshot".zc011007-*(N)
    mkdir -p "$qa_root"
    print -r -- "baseline" > "$qa_root/state"
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$root_snapshot"
    print -r -- "changed" > "$qa_root/state"
    "$SCRIPT_PATH" restore-root "$qa_root" "$root_snapshot"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$root_snapshot"
    [[ "$(<"$qa_root/state")" == "baseline" ]] || fail "root restore did not recover original bytes"
    rm -rf -- "$SELF_TEST_ROOT" "$qa_root" "$database_snapshot" "$database_snapshot".zc011007-*(N) "$root_snapshot" "$root_snapshot".zc011007-*(N) "$non_qa_database"
    SELF_TEST_ROOT=""
    trap - EXIT
    print -- "PASS: ZC-011-007 invalid-estimate fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
if [[ "$COMMAND" == "self-test" ]]; then
    self_test
    exit 0
fi

case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        [[ -n "$ARGUMENT_ONE" && -n "$ARGUMENT_TWO" ]] || usage
        ;;
    *)
        [[ -n "$ARGUMENT_ONE" && -f "$ARGUMENT_ONE" ]] || usage
        require_qa_database
        command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
        ;;
esac

case "$COMMAND" in
    prepare) prepare ;;
    assert-unmutated) assert_unmutated ;;
    assert-valid) assert_valid ;;
    cleanup) cleanup ;;
    snapshot-root) snapshot_root ;;
    restore-root) restore_root ;;
    assert-root-restored) assert_root_restored ;;
    *) usage ;;
esac
