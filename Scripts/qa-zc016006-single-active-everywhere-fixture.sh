#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly SCRIPT_DIR="${0:A:h}"
readonly TEMPLATE="${ZC016006_TEMPLATE:-$SCRIPT_DIR/fixtures/zc-006-001-planning-invitation-ready-state.json}"
readonly JQ="/usr/bin/jq"
readonly SQLITE3="/usr/bin/sqlite3"
readonly FIRST_TASK_ID="qa-zc016006-first"
readonly SECOND_TASK_ID="qa-zc016006-second"
readonly PRIVATE_SENTINEL="zc016006-private-window-title"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <materialize|assert-manifest|assert-database|self-test> ..."
    exit 2
}

assert_manifest() {
    local manifest="$1"
    [[ -f "$manifest" && ! -L "$manifest" ]] || fail "manifest is unavailable or unsafe"
    "$JQ" -e \
        --arg first "$FIRST_TASK_ID" \
        --arg second "$SECOND_TASK_ID" \
        --arg sentinel "$PRIVATE_SENTINEL" '
        .schemaVersion == 1
        and .osFixture.permissions.reminders == "granted"
        and .onboarding.remindersAccess == "granted"
        and (.osFixture.reminders | length) == 2
        and [.osFixture.reminders[].id] == [$first, $second]
        and ([.osFixture.reminders[].title] | length == (unique | length))
        and ([.osFixture.reminders[].title] | all(contains($sentinel) | not))
        and ([.screenwatch.days[].records[].window] | any(. == $sentinel))
    ' "$manifest" >/dev/null || fail "manifest does not satisfy ZC-016-006"
    print -- "PASS: ZC-016-006 two-task privacy-safe manifest is valid"
}

materialize() {
    local output="$1" parent temporary
    [[ -f "$TEMPLATE" && ! -L "$TEMPLATE" ]] || fail "template is unavailable or unsafe"
    parent="${output:h}"
    /bin/mkdir -p "$parent"
    [[ ! -L "$parent" && ! -L "$output" ]] || fail "output path cannot use symbolic links"
    temporary="$output.tmp.$$"
    if ! "$JQ" \
        --arg first "$FIRST_TASK_ID" \
        --arg second "$SECOND_TASK_ID" \
        --arg sentinel "$PRIVATE_SENTINEL" '
        .osFixture.reminders = .osFixture.reminders[:2]
        | .osFixture.reminders[0].id = $first
        | .osFixture.reminders[0].title = "Write the first focus brief"
        | .osFixture.reminders[1].id = $second
        | .osFixture.reminders[1].title = "Prepare the second focus review"
        | .screenwatch.days[0].records[0].window = $sentinel
        | .screenwatch.days[0].records[0].url = "https://zc016006-private.invalid/client"
    ' "$TEMPLATE" > "$temporary"; then
        /bin/rm -f -- "$temporary"
        fail "could not materialize fixture"
    fi
    /bin/chmod 600 "$temporary"
    /bin/mv -f -- "$temporary" "$output"
    assert_manifest "$output" >/dev/null
    print -- "FIRST_TASK_ID=$FIRST_TASK_ID"
    print -- "SECOND_TASK_ID=$SECOND_TASK_ID"
    print -- "PASS: ZC-016-006 ready state materialized"
}

assert_database() {
    local database="$1" active_task_id="$2" paused_task_id="${3:-}"
    [[ -f "$database" && ! -L "$database" && "$database" != *"'"* ]] \
        || fail "isolated database is unavailable or unsafe"
    [[ "$active_task_id" == "$FIRST_TASK_ID" || "$active_task_id" == "$SECOND_TASK_ID" ]] \
        || fail "unexpected active task"
    if [[ -n "$paused_task_id" ]]; then
        [[ "$paused_task_id" == "$FIRST_TASK_ID" || "$paused_task_id" == "$SECOND_TASK_ID" ]] \
            || fail "unexpected paused task"
        [[ "$paused_task_id" != "$active_task_id" ]] || fail "active and paused task must differ"
    fi
    local active_rows open_rows paused_rows
    active_rows="$($SQLITE3 -batch -noheader "$database" \
        "SELECT COUNT(*) FROM task_execution_states WHERE state='active' AND task_id='$active_task_id';")"
    open_rows="$($SQLITE3 -batch -noheader "$database" \
        "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id='$active_task_id';")"
    paused_rows=1
    if [[ -n "$paused_task_id" ]]; then
        paused_rows="$($SQLITE3 -batch -noheader "$database" \
            "SELECT COUNT(*) FROM task_execution_states WHERE state='paused' AND task_id='$paused_task_id';")"
    fi
    local all_active all_open
    all_active="$($SQLITE3 -batch -noheader "$database" \
        "SELECT COUNT(*) FROM task_execution_states WHERE state='active';")"
    all_open="$($SQLITE3 -batch -noheader "$database" \
        "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL;")"
    [[ "$active_rows" == 1 && "$open_rows" == 1 && "$paused_rows" == 1 \
       && "$all_active" == 1 && "$all_open" == 1 ]] \
        || fail "database does not contain exactly one matching active task"
    print -- "PASS: ZC-016-006 exactly one active task is persisted as $active_task_id"
}

self_test() (
    local root="${TMPDIR:-/private/tmp}/zc016006-fixture-self-test.$$"
    /bin/mkdir -m 700 "$root"
    trap '/bin/rm -rf -- "$root"' EXIT
    local manifest="$root/manifest.json" database="$root/state.sqlite"
    materialize "$manifest" >/dev/null
    assert_manifest "$manifest" >/dev/null
    "$SQLITE3" "$database" <<'SQL'
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL);
CREATE TABLE task_activity_intervals(task_id TEXT NOT NULL, ended_at TEXT);
INSERT INTO task_execution_states(task_id, state) VALUES
  ('qa-zc016006-first', 'paused'),
  ('qa-zc016006-second', 'active');
INSERT INTO task_activity_intervals(task_id, ended_at) VALUES
  ('qa-zc016006-first', '2026-07-15T06:00:00Z'),
  ('qa-zc016006-second', NULL);
SQL
    assert_database "$database" "$SECOND_TASK_ID" "$FIRST_TASK_ID" >/dev/null
    "$SQLITE3" "$database" \
        "INSERT INTO task_execution_states(task_id, state) VALUES ('duplicate', 'active');"
    if "$0" assert-database "$database" "$SECOND_TASK_ID" "$FIRST_TASK_ID" >/dev/null 2>&1; then
        fail "duplicate active state was accepted"
    fi
    print -- "PASS: ZC-016-006 fixture self-test covers switch persistence and duplicate rejection"
)

case "$COMMAND" in
    materialize) (( $# == 2 )) || usage; materialize "$2" ;;
    assert-manifest) (( $# == 2 )) || usage; assert_manifest "$2" ;;
    assert-database) (( $# == 3 || $# == 4 )) || usage; assert_database "$2" "$3" "${4:-}" ;;
    self-test) (( $# == 1 )) || usage; self_test ;;
    *) usage ;;
esac
