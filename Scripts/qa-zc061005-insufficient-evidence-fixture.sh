#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc061005"
readonly TASK_ID="$PREFIX-technical-task"
readonly TASK_TITLE="QA ZC-061-005 technical task"
readonly STRONG_PROMPT_ID="$PREFIX-strong-gaming-drift"
readonly PRIVATE_TITLE="$PREFIX-private-tutorial-secret"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"
readonly TIME_LABEL_PREFIX="$PREFIX-"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|assert-result|self-test> ..."
    exit 2
}

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

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc061005-* ]] \
        || fail "refusing non-ZC-061-005 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / ]] \
        || fail "refusing unsafe root: $root"
}

root_manifest() {
    local root="$1"
    [[ -d "$root" ]] || fail "root does not exist: $root"
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
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    assert_safe_root "$qa_root"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$snapshot" == /private/tmp/zoid-666-zc061005-* ]] \
        || fail "snapshot must use the ZC-061-005 namespace"
    [[ ! -e "$snapshot" ]] || fail "snapshot already exists: $snapshot"
    [[ ! -e "$snapshot.zc061005-target" ]] || fail "snapshot marker already exists"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc061005-target"
    root_manifest "$snapshot" > "$snapshot.zc061005-manifest"
    [[ -s "$snapshot.zc061005-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc061005-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc061005-target")" == "$qa_root" ]] \
        || fail "snapshot target does not match the requested QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc061005-restored-manifest"
    cmp -s "$snapshot.zc061005-manifest" "$snapshot.zc061005-restored-manifest" \
        || fail "restored QA root differs from the byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    local current
    assert_safe_root "$qa_root"
    [[ -f "$snapshot.zc061005-manifest" ]] || fail "snapshot manifest is missing"
    current="$(mktemp /private/tmp/zoid-666-zc061005-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc061005-manifest" "$current" \
        || fail "current QA root differs from the byte manifest"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated QA root matches the byte-exact baseline"
}

require_database() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    local table
    for table in source_tasks daily_plan_entries task_execution_states task_activity_intervals behavior_records prompt_episodes baseline_observation_days; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table production table"
    done
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('source_tasks') WHERE name = 'declared_context';" "1" "source_tasks.declared_context"
    assert_scalar "SELECT COUNT(*) FROM pragma_table_info('prompt_episodes') WHERE name IN ('resolution_origin', 'resolution_reason');" "2" "prompt resolution metadata"
}

require_os_state() {
    [[ -f "$OS_STATE" && ! -L "$OS_STATE" ]] || fail "OS fixture state is unavailable or unsafe: $OS_STATE"
    jq -e '.notifications | type == "array"' "$OS_STATE" >/dev/null \
        || fail "OS fixture state does not expose a notification array"
}

complete_baseline() {
    local recorded_at
    recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
WITH RECURSIVE day(n) AS (
    VALUES(0)
    UNION ALL SELECT n + 1 FROM day WHERE n < 6
)
INSERT INTO baseline_observation_days(
    local_day, observed_minutes, work_minutes, gaming_minutes,
    distracting_minutes, unknown_minutes, eligible_drift_count,
    coverage, recorded_at_utc
)
SELECT date('2020-01-01', '+' || n || ' days'), 60, 45, 0, 0, 15, 0,
       'complete', '$recorded_at'
FROM day
WHERE true
ON CONFLICT(local_day) DO UPDATE SET
    observed_minutes = excluded.observed_minutes,
    work_minutes = excluded.work_minutes,
    gaming_minutes = excluded.gaming_minutes,
    distracting_minutes = excluded.distracting_minutes,
    unknown_minutes = excluded.unknown_minutes,
    eligible_drift_count = excluded.eligible_drift_count,
    coverage = excluded.coverage,
    recorded_at_utc = excluded.recorded_at_utc;
SQL
}

clear_owned_state() {
    local temporary="$OS_STATE.$$.tmp"
    sqlite3 -batch "$DATABASE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM prompt_episodes
WHERE id = '$STRONG_PROMPT_ID'
   OR decision_key LIKE 'ambiguous-activity:%:$TASK_ID';
DELETE FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM daily_plan_entries WHERE reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
PRAGMA foreign_keys = ON;
SQL
    jq --arg prompt "$STRONG_PROMPT_ID" \
        '.notifications |= map(select(.id != $prompt and .desired.promptID != $prompt))' \
        "$OS_STATE" > "$temporary"
    mv "$temporary" "$OS_STATE"
}

find_free_latest_epoch() {
    local candidate="$1"
    local shift occupied
    for shift in {0..120}; do
        occupied="$(scalar "SELECT COUNT(*) FROM behavior_records WHERE epoch BETWEEN $((candidate - 12 * 60)) AND $candidate;")"
        if [[ "$occupied" == "0" ]]; then
            print -- "$candidate"
            return 0
        fi
        candidate=$((candidate - 1))
    done
    fail "could not reserve a current observation range"
}

seed_strong_notification() {
    local notification_state="$1"
    local temporary="$OS_STATE.$$.tmp"
    local delivered_at="null"
    if [[ "$notification_state" == "delivered" ]]; then
        delivered_at=$(( $(date '+%s') - 978307200 ))
    fi
    jq \
        --arg id "$STRONG_PROMPT_ID" \
        --arg status "$notification_state" \
        --argjson deliveredAt "$delivered_at" \
        '.notifications += [{
            id: $id,
            desired: {
                category: "GAMING_DRIFT",
                title: "Is this gaming intentional?",
                body: "Strong drift fixture notification",
                promptID: $id
            },
            status: $status,
            deliveredAt: $deliveredAt,
            actionIdentifier: null,
            respondedAt: null
        }]' "$OS_STATE" > "$temporary"
    mv "$temporary" "$OS_STATE"
}

prepare_phase() {
    local phase="$1"
    case "$phase" in
        qualifying-scheduled|qualifying-delivered|below-threshold|stale|no-active-task|already-handled) ;;
        *) fail "unsupported fixture phase: $phase" ;;
    esac
    require_database
    require_os_state
    clear_owned_state
    complete_baseline

    local latest count first task_start source_day timestamp notification_status
    latest=$(( $(date '+%s') - 30 ))
    count=10
    task_start=$((latest - 11 * 60))
    notification_status="scheduled"
    case "$phase" in
        qualifying-delivered) notification_status="delivered" ;;
        below-threshold) count=9 ;;
        stale) latest=$(( $(date '+%s') - 4 * 60 )) ;;
        *) ;;
    esac
    latest="$(find_free_latest_epoch "$latest")"
    first=$((latest - (count - 1) * 60))
    source_day="$(date '+%Y-%m-%d')"
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE ended_at IS NULL AND task_id != '$TASK_ID';" "0" "no foreign open task interval"
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE state = 'active' AND task_id != '$TASK_ID';" "0" "no foreign active task"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'GAMING_DRIFT' AND state IN ('detected', 'queued', 'presented') AND id != '$STRONG_PROMPT_ID';" "0" "no foreign unresolved strong prompt"
    jq -e --arg id "$STRONG_PROMPT_ID" '
        [.notifications[] | select(.desired.category == "GAMING_DRIFT" and .id != $id)]
        | length == 0
    ' "$OS_STATE" >/dev/null || fail "foreign strong notification contaminates the isolated fixture"

    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(
    source_id, title, priority, is_completed, updated_at, source_kind, declared_context
) VALUES (
    '$TASK_ID', '$TASK_TITLE', 9, 0, '$timestamp', 'local', 'technical'
);
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes,
    estimate_is_uncertain, selection_reason, selection_score, is_optional,
    blocked_reason, deferred_until_utc, updated_at
) VALUES (
    '$source_day', '$TASK_ID', 0, 1, 30, 0,
    'ZC-061-005 insufficient-evidence proof', 100, 0, NULL, NULL, '$timestamp'
);
WITH RECURSIVE minute(n) AS (
    VALUES(0)
    UNION ALL SELECT n + 1 FROM minute WHERE n + 1 < $count
)
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
)
SELECT '$source_day', $first + (n * 60), '$TIME_LABEL_PREFIX' || n,
       'Safari', '$PRIVATE_TITLE', '$PRIVATE_URL', 0, NULL,
       '$timestamp', 'unknown', 1
FROM minute;
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc
) VALUES (
    '$STRONG_PROMPT_ID', 'gaming-drift:$source_day:$first', 'GAMING_DRIFT',
    'queued', 'Is this gaming intentional?',
    'Strong coaching must be withdrawn when evidence is uncertain.',
    '$PREFIX-strong-action-token',
    '{"actions":[{"kind":"return_to_active_task","title":"Return to task","role":"primary","requiresConfirmation":false}],"payload":{"allowsDismissal":"false"}}',
    '$timestamp', '2999-01-01T00:00:00Z'
);
COMMIT;
SQL
    if [[ "$phase" != "no-active-task" ]]; then
        sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', 'active', '$(date -u -r "$task_start" '+%Y-%m-%dT%H:%M:%SZ')');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$(date -u -r "$task_start" '+%Y-%m-%dT%H:%M:%SZ')', NULL);
COMMIT;
SQL
    fi
    if [[ "$phase" == "already-handled" ]]; then
        sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc
) VALUES (
    '$PREFIX-existing-ambiguity', 'ambiguous-activity:$source_day:$first:$TASK_ID',
    'AMBIGUOUS_ACTIVITY', 'queued', 'Did this support $TASK_TITLE?',
    'Zoid 666 observed about 10 minutes in Safari while $TASK_TITLE was active. Application and duration alone cannot show your intent.',
    '$PREFIX-existing-action-token',
    '{"actions":[{"kind":"classify_as_supporting_work","title":"It supported $TASK_TITLE","role":"primary","requiresConfirmation":false},{"kind":"classify_as_gaming","title":"It was gaming","role":"secondary","requiresConfirmation":false},{"kind":"keep_activity_unknown","title":"Keep it unknown","role":"secondary","requiresConfirmation":false}],"payload":{"sourceDay":"$source_day","sessionStartEpoch":"$first","sessionEndEpoch":"$((latest + 60))","observationCount":"10","application":"Safari","taskID":"$TASK_ID","taskTitle":"$TASK_TITLE","allowsDismissal":"true"}}',
    '$timestamp', '2999-01-01T00:00:00Z'
);
SQL
    fi
    seed_strong_notification "$notification_status"
    verify_prepared "$phase" "$count"
    print -- "PASS: prepared $phase insufficient-evidence fixture"
}

verify_prepared() {
    local phase="$1"
    local count="$2"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND title = '$TASK_TITLE' AND declared_context = 'technical';" "1" "technical source task"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%' AND app_name = 'Safari' AND classification = 'unknown';" "$count" "unknown Safari observations"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%' AND lower(classification) = 'research';" "0" "no Research classification"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$STRONG_PROMPT_ID' AND prompt_type = 'GAMING_DRIFT' AND state = 'queued';" "1" "queued strong prompt"
    local active_count=1
    [[ "$phase" == "no-active-task" ]] && active_count=0
    assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "$active_count" "active task boundary"
    jq -e --arg id "$STRONG_PROMPT_ID" --arg expected "${phase#qualifying-}" '
        [.notifications[] | select(.id == $id and .desired.promptID == $id and .desired.category == "GAMING_DRIFT")] as $matching
        | ($matching | length) == 1
        and ($matching[0].status == (if ($expected == "delivered") then "delivered" else "scheduled" end))
    ' "$OS_STATE" >/dev/null || fail "exact strong notification fixture is missing"
}

assert_result() {
    local phase="$1"
    require_database
    require_os_state
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$STRONG_PROMPT_ID' AND state = 'dismissed' AND resolution_origin = 'system' AND resolution_reason = 'screenwatch_evidence_invalid';" "1" "exact system withdrawal"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'GAMING_DRIFT' AND state IN ('detected', 'queued', 'presented');" "0" "no unresolved strong prompt"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%' AND lower(classification) = 'research';" "0" "no Research classification"
    jq -e --arg id "$STRONG_PROMPT_ID" '
        [.notifications[] | select(.id == $id or .desired.promptID == $id or .desired.category == "GAMING_DRIFT")]
        | length == 0
    ' "$OS_STATE" >/dev/null || fail "strong scheduled or delivered notification remains"

    local expected_ambiguity=0
    case "$phase" in
        qualifying-scheduled|qualifying-delivered|already-handled) expected_ambiguity=1 ;;
        below-threshold|stale|no-active-task) expected_ambiguity=0 ;;
        *) fail "unsupported result phase: $phase" ;;
    esac
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "$expected_ambiguity" "ambiguity prompt count"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND (title LIKE '%Research%' OR summary LIKE '%Research%' OR payload_json LIKE '%Research%');" "0" "no invented Research claim"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND (summary LIKE '%$PRIVATE_TITLE%' OR summary LIKE '%$PRIVATE_URL%' OR payload_json LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_URL%');" "0" "private evidence exclusion"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND (title LIKE '%Is this gaming intentional?%' OR title LIKE '%Ready for an easy return?%' OR title LIKE '%Your five minutes are up%');" "0" "no strong wording in ambiguity prompt"
    if (( expected_ambiguity == 1 )); then
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND state IN ('queued', 'presented') AND title = 'Did this support $TASK_TITLE?' AND summary LIKE '%about 10 minutes in Safari%' AND summary LIKE '%cannot show your intent%';" "1" "one scoped ambiguity confirmation"
    fi
    print -- "PASS: $phase withdrew strong drift and left at most one privacy-safe ambiguity confirmation"
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "validator accepted $label"
    fi
}

self_test() (
    local root qa_root snapshot database os_state source_day now first latest timestamp
    root="$(mktemp -d /private/tmp/zoid-666-zc061005-self-test.XXXXXX)"
    qa_root="$root-runtime"
    snapshot="$root-snapshot"
    mkdir -p "$qa_root/Application Support/Zoid 666" "$qa_root/OS Fixtures"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    os_state="$qa_root/OS Fixtures/state.json"
    trap 'rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc061005-target" "$snapshot.zc061005-manifest" "$snapshot.zc061005-restored-manifest"' EXIT
    sqlite3 -batch "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, priority INTEGER NOT NULL, is_completed INTEGER NOT NULL, updated_at TEXT NOT NULL, source_kind TEXT NOT NULL, declared_context TEXT);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, estimate_is_uncertain INTEGER NOT NULL, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL, blocked_reason TEXT, deferred_until_utc TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY, decision_key TEXT NOT NULL UNIQUE, prompt_type TEXT NOT NULL, state TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, action_token TEXT NOT NULL UNIQUE, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, expires_at_utc TEXT, presented_at_utc TEXT, resolved_at_utc TEXT, resolution_origin TEXT, resolution_reason TEXT);
CREATE TABLE baseline_observation_days(local_day TEXT PRIMARY KEY, observed_minutes INTEGER NOT NULL, work_minutes INTEGER NOT NULL, gaming_minutes INTEGER NOT NULL, distracting_minutes INTEGER NOT NULL, unknown_minutes INTEGER NOT NULL, eligible_drift_count INTEGER NOT NULL, coverage TEXT NOT NULL, recorded_at_utc TEXT NOT NULL);
INSERT INTO source_tasks VALUES('foreign-task', 'Preserve foreign task', 0, 0, '2026-07-15T00:00:00Z', 'local', NULL);
SQL
    jq -n '{schemaVersion:1, permissions:{notifications:"granted"}, reminderLists:[], reminders:[], calendarCommitments:[], notifications:[], notificationSchedulingFailure:null, audit:[], counters:{}, generatedIdentifiers:[], controlReceipts:[]}' > "$os_state"
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot" >/dev/null

    local phase expected_count
    for phase in qualifying-scheduled qualifying-delivered below-threshold stale no-active-task already-handled; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        "$SCRIPT_PATH" prepare "$phase" "$database" "$os_state" >/dev/null
        expected_count=10
        [[ "$phase" == "below-threshold" ]] && expected_count=9
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';")" == "$expected_count" ]] \
            || fail "$phase behavior count"
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';")" == "$([[ "$phase" == "already-handled" ]] && print 1 || print 0)" ]] \
            || fail "$phase preexisting ambiguity count"
    done

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" prepare qualifying-scheduled "$database" "$os_state" >/dev/null
    source_day="$(date '+%Y-%m-%d')"
    first="$(sqlite3 "$database" "SELECT MIN(epoch) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';")"
    latest="$(sqlite3 "$database" "SELECT MAX(epoch) FROM behavior_records WHERE time_label LIKE '$TIME_LABEL_PREFIX%';")"
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$database" <<SQL
UPDATE prompt_episodes
SET state = 'dismissed', resolved_at_utc = '$timestamp',
    resolution_origin = 'system', resolution_reason = 'screenwatch_evidence_invalid'
WHERE id = '$STRONG_PROMPT_ID';
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc
) VALUES (
    '$PREFIX-self-test-ambiguity', 'ambiguous-activity:$source_day:$first:$TASK_ID',
    'AMBIGUOUS_ACTIVITY', 'queued', 'Did this support $TASK_TITLE?',
    'Zoid 666 observed about 10 minutes in Safari while $TASK_TITLE was active. Application and duration alone cannot show your intent.',
    '$PREFIX-self-test-token',
    '{"actions":[],"payload":{"sessionStartEpoch":"$first","sessionEndEpoch":"$((latest + 60))"}}',
    '$timestamp', '2999-01-01T00:00:00Z'
);
SQL
    jq --arg id "$STRONG_PROMPT_ID" '.notifications |= map(select(.id != $id))' "$os_state" > "$os_state.tmp"
    mv "$os_state.tmp" "$os_state"
    "$SCRIPT_PATH" assert-result qualifying-scheduled "$database" "$os_state" >/dev/null

    sqlite3 "$database" "UPDATE prompt_episodes SET summary = '$PRIVATE_TITLE' WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';"
    expect_failure "privacy leakage" "$SCRIPT_PATH" assert-result qualifying-scheduled "$database" "$os_state"
    sqlite3 "$database" "UPDATE prompt_episodes SET summary = 'about 10 minutes in Safari; cannot show your intent' WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';"
    sqlite3 "$database" "INSERT INTO prompt_episodes(id, decision_key, prompt_type, state, title, summary, action_token, payload_json, created_at_utc) VALUES ('$PREFIX-duplicate', 'duplicate-ambiguity', 'AMBIGUOUS_ACTIVITY', 'queued', 'Did this support duplicate?', 'cannot show your intent', '$PREFIX-duplicate-token', '{\"actions\":[],\"payload\":{}}', '$timestamp');"
    expect_failure "duplicate ambiguity" "$SCRIPT_PATH" assert-result qualifying-scheduled "$database" "$os_state"
    sqlite3 "$database" "DELETE FROM prompt_episodes WHERE id = '$PREFIX-duplicate'; DROP TABLE behavior_records;"
    expect_failure "SQL/schema failure" "$SCRIPT_PATH" assert-result qualifying-scheduled "$database" "$os_state"

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    jq '.notifications += [{id:"foreign-gaming",desired:{category:"GAMING_DRIFT",title:"Foreign",body:"Preserve",promptID:"foreign-gaming"},status:"scheduled",deliveredAt:null,actionIdentifier:null,respondedAt:null}]' "$os_state" > "$os_state.tmp"
    mv "$os_state.tmp" "$os_state"
    expect_failure "foreign strong notification contamination" "$SCRIPT_PATH" prepare qualifying-scheduled "$database" "$os_state"

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    [[ "$(sqlite3 "$database" "SELECT title FROM source_tasks WHERE source_id = 'foreign-task';")" == "Preserve foreign task" ]] \
        || fail "foreign task was not restored"
    print -- "PASS: ZC-061-005 fixture self-test covers boundaries, duplication, SQL failure, privacy leakage, and byte-exact restoration"
)

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
readonly COMMAND="${1:-}"
shift || true
case "$COMMAND" in
    snapshot-root)
        (( $# == 2 )) || usage
        snapshot_root "$1" "$2"
        ;;
    restore-root)
        (( $# == 2 )) || usage
        restore_root "$1" "$2"
        ;;
    assert-root-restored)
        (( $# == 2 )) || usage
        assert_root_restored "$1" "$2"
        ;;
    prepare|assert-result)
        (( $# == 3 )) || usage
        readonly PHASE="$1"
        readonly DATABASE="${2:A}"
        readonly OS_STATE="${3:A}"
        if [[ "$COMMAND" == "prepare" ]]; then
            prepare_phase "$PHASE"
        else
            assert_result "$PHASE"
        fi
        ;;
    self-test)
        (( $# == 0 )) || usage
        self_test
        ;;
    *) usage ;;
esac
