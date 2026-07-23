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
readonly ROOT_CONTROL_SUFFIX="/.zc011007-fixture-control"
readonly ROOT_MARKER_SUFFIX="$ROOT_CONTROL_SUFFIX/owner"
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
    [[ "$(stat -f '%Lp' "$qa_root")" == "700" && "$(stat -f '%u' "$qa_root")" == "$(id -u)" ]] \
        || fail "QA root must be fixture-exclusive mode 700 and owned by the current user"
    local control="$qa_root$ROOT_CONTROL_SUFFIX"
    [[ -d "$control" && ! -L "$control" && "${control:a}" == "${control:A}" ]] \
        || fail "fixture control directory is missing or traverses a symlink"
    [[ "$(stat -f '%Lp' "$control")" == "700" && "$(stat -f '%u' "$control")" == "$(id -u)" ]] \
        || fail "fixture control directory must be mode 700 and owned by the current user"
    local marker="$qa_root$ROOT_MARKER_SUFFIX"
    [[ -f "$marker" && ! -L "$marker" && "$(<"$marker")" == "$qa_root" ]] \
        || fail "database root is not claimed by this ZC-011-007 fixture"
    [[ "$(stat -f '%l' "$marker")" == "1" && "$(stat -f '%Lp' "$marker")" == "600" ]] \
        || fail "fixture owner marker must be a private single-link file"
    [[ "$(stat -f '%l' "$resolved_database")" == "1" ]] \
        || fail "canonical database must be a single-link file"
    CANONICAL_DATABASE="$resolved_database"
    CANONICAL_DATABASE_ID="$(stat -f '%d:%i' "$CANONICAL_DATABASE")"
}

assert_qa_processes_stopped() {
    local qa_root="$1"
    local executable pid
    for executable in ZoidCoachQA ZoidCoachAgentQA; do
        for pid in ${(f)"$(pgrep -x "$executable" 2>/dev/null || true)"}; do
            [[ -n "$pid" ]] || continue
            fail "all exact signed QA processes must be stopped before mutating the fixture root: executable=$executable pid=$pid"
        done
    done
    ! /usr/sbin/lsof "$qa_root$DATABASE_SUFFIX" >/dev/null 2>&1 || fail "fixture database has open file handles"
}

assert_database_identity() {
    [[ -n "$CANONICAL_DATABASE" && -f "$CANONICAL_DATABASE" && ! -L "$CANONICAL_DATABASE" ]] \
        || fail "canonical database disappeared or became a symlink"
    [[ "${CANONICAL_DATABASE:A}" == "$CANONICAL_DATABASE" ]] \
        || fail "canonical database resolved outside its owned root"
    [[ "$(stat -f '%d:%i' "$CANONICAL_DATABASE")" == "$CANONICAL_DATABASE_ID" ]] \
        || fail "canonical database identity changed during fixture operation"
    [[ "$(stat -f '%l' "$CANONICAL_DATABASE")" == "1" ]] \
        || fail "canonical database acquired another hard link"
}

usage() {
    print -u2 -- "usage: $0 <prepare|assert-unmutated|assert-valid|checkpoint|snapshot-root|restore-root|assert-root-restored|self-test> [database-or-root] [snapshot]"
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
    local qa_root="${CANONICAL_DATABASE%$DATABASE_SUFFIX}"
    assert_qa_processes_stopped "$qa_root"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    assert_database_identity
    local staged_database
    staged_database="$(mktemp "${CANONICAL_DATABASE:h}/.zc011007-seed.XXXXXX")"
    trap 'rm -f -- "${staged_database:-}"' EXIT
    chmod 600 "$staged_database"
    cp -p "$CANONICAL_DATABASE" "$staged_database"
    [[ ! -L "$staged_database" && "$(stat -f '%l' "$staged_database")" == "1" ]] \
        || fail "staged database must be a private single-link file"
    sqlite3 -batch "$staged_database" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(source_id, title, due_at, priority, is_completed, updated_at, notes, list_id, list_name, modified_at, source_hash, source_kind)
VALUES('$TASK_ID', '$TASK_TITLE', '$DAY_KEY' || 'T12:00:00Z', 1, 0, '$timestamp', '$PRIVATE_NOTE', NULL, 'Zoid 666 QA', '$timestamp', '$TASK_ID', 'local');
INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, estimate_is_uncertain)
VALUES('$DAY_KEY', '$TASK_ID', 1, 1, NULL, '$timestamp', 'ZC-011-007 invalid estimate fixture', 100, 0, NULL, NULL, 0);
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES('$TASK_ID', 'ready', '$timestamp');
COMMIT;
SQL
    [[ "$(sqlite3 -batch -noheader "$staged_database" 'PRAGMA integrity_check;')" == "ok" ]] \
        || fail "staged fixture database failed integrity check"
    assert_database_identity
    mv -f "$staged_database" "$CANONICAL_DATABASE"
    staged_database=""
    CANONICAL_DATABASE_ID="$(stat -f '%d:%i' "$CANONICAL_DATABASE")"
    trap - EXIT
    assert_unmutated
}

checkpoint() {
    local qa_root="${CANONICAL_DATABASE%$DATABASE_SUFFIX}"
    assert_qa_processes_stopped "$qa_root"
    assert_database_identity
    sqlite3 -batch "$CANONICAL_DATABASE" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null
    assert_database_identity
}

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc011007-* ]] || fail "refusing non-ZC-011-007 isolated root: $root"
    [[ "$root" != "/private/tmp" && "$root" != "/" ]] || fail "refusing unsafe root: $root"
}

assert_owned_root_structure() {
    local actual_root="${1:a}"
    local claimed_root="${2:a}"
    local label="$3"
    assert_safe_root "$actual_root"
    assert_safe_root "$claimed_root"
    [[ "$actual_root" == "${1:A}" && -d "$actual_root" && ! -L "$actual_root" ]] \
        || fail "$label root is missing or traverses a symlink"
    [[ "$(stat -f '%Lp' "$actual_root")" == "700" && "$(stat -f '%u' "$actual_root")" == "$(id -u)" ]] \
        || fail "$label root must be mode 700 and owned by the current user"

    local control="$actual_root$ROOT_CONTROL_SUFFIX"
    [[ -d "$control" && ! -L "$control" && "${control:a}" == "${control:A}" ]] \
        || fail "$label control directory is missing or traverses a symlink"
    [[ "$(stat -f '%Lp' "$control")" == "700" && "$(stat -f '%u' "$control")" == "$(id -u)" ]] \
        || fail "$label control directory must be mode 700 and owned by the current user"

    local marker="$actual_root$ROOT_MARKER_SUFFIX"
    [[ -f "$marker" && ! -L "$marker" && "${marker:a}" == "${marker:A}" ]] \
        || fail "$label owner marker is missing or traverses a symlink"
    [[ "$(<"$marker")" == "$claimed_root" ]] || fail "$label owner marker does not claim the exact live QA root"
    [[ "$(stat -f '%Lp' "$marker")" == "600" && "$(stat -f '%u' "$marker")" == "$(id -u)" && "$(stat -f '%l' "$marker")" == "1" ]] \
        || fail "$label owner marker must be a private single-link file"

    local database="$actual_root$DATABASE_SUFFIX"
    [[ -f "$database" && ! -L "$database" && "${database:a}" == "${database:A}" ]] \
        || fail "$label canonical database is missing or traverses a symlink"
    [[ "$(stat -f '%u' "$database")" == "$(id -u)" && "$(stat -f '%l' "$database")" == "1" ]] \
        || fail "$label canonical database must be owned by the current user and have one link"
}

assert_private_snapshot_metadata() {
    local metadata="${1:a}"
    local label="$2"
    [[ "$metadata" == "${1:A}" && -f "$metadata" && ! -L "$metadata" ]] \
        || fail "$label is missing or traverses a symlink"
    [[ "$(stat -f '%Lp' "$metadata")" == "600" && "$(stat -f '%u' "$metadata")" == "$(id -u)" && "$(stat -f '%l' "$metadata")" == "1" ]] \
        || fail "$label must be a private single-link file"
}

assert_snapshot_contract() {
    local snapshot="${1:a}"
    local qa_root="${2:a}"
    assert_owned_root_structure "$snapshot" "$qa_root" "snapshot"
    assert_private_snapshot_metadata "$snapshot.zc011007-target" "snapshot target marker"
    assert_private_snapshot_metadata "$snapshot.zc011007-manifest" "snapshot manifest"
    [[ "$(<"$snapshot.zc011007-target")" == "$qa_root" ]] || fail "snapshot target does not match QA root"
    [[ -s "$snapshot.zc011007-manifest" ]] || fail "snapshot manifest is empty"
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
    local qa_root="${ARGUMENT_ONE:a}"
    local snapshot="${ARGUMENT_TWO:a}"
    assert_safe_root "$qa_root"
    [[ "$qa_root" == "${ARGUMENT_ONE:A}" ]] || fail "QA root must not contain symlinked ancestors"
    [[ "$snapshot" == "${ARGUMENT_TWO:A}" ]] || fail "snapshot path must not contain symlinked ancestors"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$(stat -f '%Lp' "$qa_root")" == "700" && "$(stat -f '%u' "$qa_root")" == "$(id -u)" ]] \
        || fail "fresh QA root must be mode 700 and owned by the current user"
    [[ "$snapshot" == /private/tmp/zoid-666-zc011007-* ]] || fail "snapshot must use isolated ZC-011-007 namespace"
    [[ ! -e "$snapshot" && ! -L "$snapshot" && ! -e "$snapshot.zc011007-target" && ! -L "$snapshot.zc011007-target" \
        && ! -e "$snapshot.zc011007-manifest" && ! -L "$snapshot.zc011007-manifest" ]] || fail "snapshot or metadata already exists"
    local control="$qa_root$ROOT_CONTROL_SUFFIX"
    mkdir -m 700 "$control" || fail "fixture control directory already exists"
    local marker="$qa_root$ROOT_MARKER_SUFFIX"
    set -o noclobber
    print -r -- "$qa_root" > "$marker"
    set +o noclobber
    chmod 600 "$marker"
    [[ "$(stat -f '%l' "$marker")" == "1" ]] || fail "fixture marker must have one link"
    local database="$qa_root$DATABASE_SUFFIX"
    [[ -f "$database" && ! -L "$database" && "${database:a}" == "${database:A}" ]] \
        || fail "canonical fixture database is missing or traverses a symlink"
    [[ "$(stat -f '%l' "$database")" == "1" ]] || fail "canonical fixture database must have one link"
    assert_qa_processes_stopped "$qa_root"
    "$SCRIPT_PATH" checkpoint "$database"
    /usr/bin/ditto "$qa_root" "$snapshot"
    chmod 700 "$snapshot"
    set -o noclobber
    print -r -- "$qa_root" > "$snapshot.zc011007-target"
    root_manifest "$snapshot" > "$snapshot.zc011007-manifest"
    set +o noclobber
    chmod 600 "$snapshot.zc011007-target" "$snapshot.zc011007-manifest"
    assert_snapshot_contract "$snapshot" "$qa_root"
    print -- "PASS: snapshotted isolated ZC-011-007 QA root"
}

restore_root() {
    local qa_root="${ARGUMENT_ONE:a}"
    local snapshot="${ARGUMENT_TWO:a}"
    assert_safe_root "$qa_root"
    [[ "$qa_root" == "${ARGUMENT_ONE:A}" ]] || fail "restore target must not contain symlinked ancestors"
    [[ "$snapshot" == "${ARGUMENT_TWO:A}" ]] || fail "snapshot path must not contain symlinked ancestors"
    assert_snapshot_contract "$snapshot" "$qa_root"
    assert_owned_root_structure "$qa_root" "$qa_root" "live QA"
    assert_qa_processes_stopped "$qa_root"
    assert_owned_root_structure "$qa_root" "$qa_root" "live QA"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    local restored_manifest
    restored_manifest="$(mktemp /private/tmp/zoid-666-zc011007-restored-manifest.XXXXXX)"
    trap 'rm -f -- "${restored_manifest:-}"' EXIT
    root_manifest "$qa_root" > "$restored_manifest"
    cmp -s "$snapshot.zc011007-manifest" "$restored_manifest" || fail "restored QA root differs from baseline"
    rm -f -- "$restored_manifest"
    restored_manifest=""
    trap - EXIT
    print -- "PASS: restored isolated ZC-011-007 QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${ARGUMENT_ONE:a}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ "$qa_root" == "${ARGUMENT_ONE:A}" ]] || fail "restored target must not contain symlinked ancestors"
    [[ "$snapshot" == "${ARGUMENT_TWO:A}" ]] || fail "snapshot path must not contain symlinked ancestors"
    assert_snapshot_contract "$snapshot" "$qa_root"
    assert_owned_root_structure "$qa_root" "$qa_root" "restored QA"
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
    typeset -g non_qa_database="/private/tmp/zc011007-non-qa-${SELF_TEST_ROOT:t}.sqlite"
    local timestamp="2026-07-15T06:00:00Z"
    local self_test_suffix="${SELF_TEST_ROOT:t}"
    typeset -g qa_root="/private/tmp/zoid-666-zc011007-fixture-self-test-root-$self_test_suffix"
    typeset -g alias_root="/private/tmp/zoid-666-zc011007-fixture-alias-$self_test_suffix"
    typeset -g database_snapshot="/private/tmp/zoid-666-zc011007-fixture-db-snapshot-$self_test_suffix"
    typeset -g root_snapshot="/private/tmp/zoid-666-zc011007-fixture-root-snapshot-$self_test_suffix"
    typeset -g qa_process_pid=""
    typeset -g database_holder_pid=""
    trap '[[ -z "${qa_process_pid:-}" ]] || kill "$qa_process_pid" 2>/dev/null || true; [[ -z "${database_holder_pid:-}" ]] || kill "$database_holder_pid" 2>/dev/null || true; [[ -z "${SELF_TEST_ROOT:-}" ]] || rm -rf -- "$SELF_TEST_ROOT"; [[ -z "${qa_root:-}" ]] || rm -rf -- "$qa_root"; [[ -z "${alias_root:-}" ]] || rm -rf -- "$alias_root"; [[ -z "${database_snapshot:-}" ]] || rm -rf -- "$database_snapshot" "$database_snapshot.zc011007-target" "$database_snapshot.zc011007-manifest" "$database_snapshot.zc011007-restored-manifest"; [[ -z "${root_snapshot:-}" ]] || rm -rf -- "$root_snapshot" "$root_snapshot.zc011007-target" "$root_snapshot.zc011007-manifest" "$root_snapshot.zc011007-restored-manifest"; [[ -z "${non_qa_database:-}" ]] || rm -rf -- "$non_qa_database"' EXIT
    mkdir -p "${database:h}"
    sqlite3 -batch "$database" <<SQL
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, due_at TEXT, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, notes TEXT, list_id TEXT, list_name TEXT, modified_at TEXT, source_hash TEXT, source_kind TEXT NOT NULL DEFAULT 'reminders');
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, updated_at TEXT NOT NULL, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, estimate_is_uncertain INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
SQL
    "$SCRIPT_PATH" snapshot-root "$SELF_TEST_ROOT" "$database_snapshot"
    local live_database_hash="$(shasum -a 256 "$database" | awk '{print $1}')"
    local snapshot_target="$database_snapshot.zc011007-target"
    local snapshot_manifest="$database_snapshot.zc011007-manifest"
    local snapshot_owner="$database_snapshot$ROOT_MARKER_SUFFIX"
    local rejection_link="$SELF_TEST_ROOT/.restore-rejection-hardlink"

    ln "$snapshot_target" "$rejection_link"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a hard-linked snapshot target marker"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "linked snapshot target rejection deleted or mutated the live root"
    rm "$rejection_link"

    ln "$snapshot_manifest" "$rejection_link"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a hard-linked snapshot manifest"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "linked snapshot manifest rejection deleted or mutated the live root"
    rm "$rejection_link"

    ln "$snapshot_owner" "$rejection_link"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a hard-linked snapshot owner marker"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "linked snapshot owner rejection deleted or mutated the live root"
    rm "$rejection_link"

    print -r -- "/private/tmp/zoid-666-zc011007-forged-target" > "$snapshot_target"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a forged snapshot target marker"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "forged snapshot target rejection deleted or mutated the live root"
    print -r -- "$SELF_TEST_ROOT" > "$snapshot_target"

    print -r -- "/private/tmp/zoid-666-zc011007-forged-owner" > "$snapshot_owner"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a forged snapshot owner marker"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "forged snapshot owner rejection deleted or mutated the live root"
    print -r -- "$SELF_TEST_ROOT" > "$snapshot_owner"

    local marker="$SELF_TEST_ROOT$ROOT_MARKER_SUFFIX"
    print -r -- "/private/tmp/zoid-666-zc011007-stolen-root" > "$marker"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted changed live-root ownership"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "changed live-root ownership rejection deleted or mutated the live root"
    print -r -- "$SELF_TEST_ROOT" > "$marker"

    chmod 755 "$SELF_TEST_ROOT"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted changed live-root permissions"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "changed live-root permission rejection deleted or mutated the live root"
    chmod 700 "$SELF_TEST_ROOT"

    local qa_process="$SELF_TEST_ROOT/ZoidCoachQA"
    cp /bin/sleep "$qa_process"
    codesign --force --sign - "$qa_process" >/dev/null 2>&1
    chmod 700 "$qa_process"
    env ZOID_COACH_QA_RUN_ROOT="$SELF_TEST_ROOT" "$qa_process" 30 &
    qa_process_pid=$!
    local attempt
    for attempt in {1..50}; do
        pgrep -x ZoidCoachQA 2>/dev/null | grep -qx "$qa_process_pid" && break
        sleep 0.02
    done
    pgrep -x ZoidCoachQA 2>/dev/null | grep -qx "$qa_process_pid" || fail "restarted QA process self-test did not acquire its expected process name"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted a restarted QA process"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "restarted QA process rejection deleted or mutated the live root"
    kill "$qa_process_pid"
    wait "$qa_process_pid" 2>/dev/null || true
    qa_process_pid=""
    rm "$qa_process"

    tail -f "$database" >/dev/null &
    database_holder_pid=$!
    for attempt in {1..50}; do
        /usr/sbin/lsof -a -p "$database_holder_pid" "$database" >/dev/null 2>&1 && break
        sleep 0.02
    done
    /usr/sbin/lsof -a -p "$database_holder_pid" "$database" >/dev/null 2>&1 || fail "open-database self-test did not acquire a file handle"
    if "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot" >/dev/null 2>&1; then
        fail "restore accepted an open canonical database handle"
    fi
    [[ -d "$SELF_TEST_ROOT" && "$(shasum -a 256 "$database" | awk '{print $1}')" == "$live_database_hash" ]] \
        || fail "open database rejection deleted or mutated the live root"
    kill "$database_holder_pid"
    wait "$database_holder_pid" 2>/dev/null || true
    database_holder_pid=""

    local marker_hardlink="$SELF_TEST_ROOT/.marker-hardlink"
    ln "$marker" "$marker_hardlink"
    if "$SCRIPT_PATH" prepare "$database" >/dev/null 2>&1; then
        fail "fixture accepted a hard-linked ownership marker"
    fi
    rm "$marker_hardlink"
    local database_hardlink="$SELF_TEST_ROOT/.database-hardlink"
    ln "$database" "$database_hardlink"
    if "$SCRIPT_PATH" prepare "$database" >/dev/null 2>&1; then
        fail "fixture accepted a hard-linked canonical database"
    fi
    rm "$database_hardlink"
    ln -s "$SELF_TEST_ROOT" "$alias_root"
    local canonical_hash_before="$(shasum -a 256 "$database" | awk '{print $1}')"
    if "$SCRIPT_PATH" prepare "$alias_root$DATABASE_SUFFIX" >/dev/null 2>&1; then
        fail "fixture accepted a symlinked QA-root ancestor"
    fi
    [[ "$(shasum -a 256 "$database" | awk '{print $1}')" == "$canonical_hash_before" ]] \
        || fail "symlinked-parent rejection mutated the canonical database"
    rm "$alias_root"
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
    sqlite3 -batch "$database" "INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind) VALUES('$TASK_ID', 'collision', 0, 0, '$timestamp', 'local');"
    local collision_hash_before="$(shasum -a 256 "$database" | awk '{print $1}')"
    if "$SCRIPT_PATH" prepare "$database" >/dev/null 2>&1; then
        fail "fixture accepted a colliding owned task ID"
    fi
    [[ "$(shasum -a 256 "$database" | awk '{print $1}')" == "$collision_hash_before" ]] \
        || fail "collision rejection mutated the database"
    sqlite3 -batch "$database" "DELETE FROM source_tasks WHERE source_id = '$TASK_ID';"
    "$SCRIPT_PATH" prepare "$database"
    "$SCRIPT_PATH" assert-unmutated "$database"
    sqlite3 -batch "$database" "UPDATE daily_plan_entries SET estimate_minutes = 25, updated_at = '$timestamp' WHERE reminder_id = '$TASK_ID';"
    "$SCRIPT_PATH" assert-valid "$database"
    "$SCRIPT_PATH" checkpoint "$database"
    "$SCRIPT_PATH" restore-root "$SELF_TEST_ROOT" "$database_snapshot"
    "$SCRIPT_PATH" assert-root-restored "$SELF_TEST_ROOT" "$database_snapshot"
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
    checkpoint) checkpoint ;;
    snapshot-root) snapshot_root ;;
    restore-root) restore_root ;;
    assert-root-restored) assert_root_restored ;;
    *) usage ;;
esac
