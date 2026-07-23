#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly ARGUMENT_ONE="${2:-}"
readonly ARGUMENT_TWO="${3:-}"
readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc025006"
readonly TASK_ID="$PREFIX-task"
readonly TASK_TITLE="QA focus task"
readonly PRIVATE_TITLE="$PREFIX-private-window-secret"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/secret"
case "$COMMAND" in
    prepare|assert-effect) readonly DATABASE="$ARGUMENT_TWO" ;;
    assert-prompt|assert-absent|assert-no-reprompt|cleanup-owned) readonly DATABASE="$ARGUMENT_ONE" ;;
    *) readonly DATABASE="" ;;
esac

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <snapshot-root|restore-root|assert-root-restored|prepare|assert-prompt|assert-absent|assert-effect|assert-no-reprompt|cleanup-owned|self-test> ..."
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

sql_quote() {
    print -r -- "$1" | sed "s/'/''/g"
}

require_database() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
    local table
    for table in source_tasks task_execution_states task_activity_intervals behavior_records prompt_episodes prompt_responses prompt_response_effects daily_review_corrections baseline_observation_days; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table table"
    done
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

assert_safe_root() {
    local root="${1:A}"
    [[ "$root" == /private/tmp/zoid-666-zc025006-* ]] \
        || fail "refusing non-ZC-025-006 isolated root: $root"
    [[ "$root" != "/private/tmp" && "$root" != "/" ]] \
        || fail "refusing unsafe root: $root"
}

snapshot_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$qa_root" ]] || fail "QA root does not exist: $qa_root"
    [[ "$snapshot" == /private/tmp/zoid-666-zc025006-* ]] \
        || fail "snapshot must use the isolated ZC-025-006 namespace"
    [[ ! -e "$snapshot" ]] || fail "snapshot already exists: $snapshot"
    [[ ! -e "$snapshot.zc025006-target" ]] || fail "snapshot target marker already exists"
    mkdir -p "${snapshot:h}"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc025006-target"
    root_manifest "$snapshot" > "$snapshot.zc025006-manifest"
    [[ -s "$snapshot.zc025006-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc025006-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc025006-target")" == "$qa_root" ]] \
        || fail "snapshot target does not match requested QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc025006-restored-manifest"
    cmp -s "$snapshot.zc025006-manifest" "$snapshot.zc025006-restored-manifest" \
        || fail "restored QA root differs from the byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${ARGUMENT_ONE:A}"
    local snapshot="${ARGUMENT_TWO:A}"
    assert_safe_root "$qa_root"
    [[ -f "$snapshot.zc025006-manifest" ]] || fail "snapshot manifest is missing"
    local current
    current="$(mktemp /private/tmp/zoid-666-zc025006-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc025006-manifest" "$current" \
        || fail "current QA root differs from the byte manifest"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated QA root matches the byte-exact baseline"
}

clear_branch_state() {
    sqlite3 -batch "$DATABASE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM prompt_response_effects;
DELETE FROM prompt_responses;
DELETE FROM prompt_episodes;
DELETE FROM daily_review_corrections;
DELETE FROM behavior_records WHERE window_title LIKE '$PREFIX-%' OR url LIKE '%$PREFIX%';
UPDATE task_activity_intervals SET ended_at = COALESCE(ended_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')) WHERE ended_at IS NULL;
UPDATE task_execution_states SET state = 'paused', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE state = 'active';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
PRAGMA foreign_keys = ON;
SQL
}

complete_behavior_prompt_baseline() {
    local recorded_at
    recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
WITH RECURSIVE baseline_day(n) AS (
    VALUES(0)
    UNION ALL SELECT n + 1 FROM baseline_day WHERE n < 6
)
INSERT INTO baseline_observation_days(
    local_day, observed_minutes, work_minutes, gaming_minutes,
    distracting_minutes, unknown_minutes, eligible_drift_count,
    coverage, recorded_at_utc
)
SELECT date('2020-01-01', '+' || n || ' days'), 1, 1, 0, 0, 0, 0,
       'complete', '$recorded_at'
FROM baseline_day
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
COMMIT;
SQL
    assert_scalar "SELECT COUNT(*) FROM baseline_observation_days WHERE coverage = 'complete';" "7" "complete behavior-prompt baseline"
}

prepare_phase() {
    local phase="$ARGUMENT_ONE"
    require_database
    case "$phase" in
        qualifying|short|no-task|late-task|stale|certain) ;;
        *) fail "unsupported fixture phase: $phase" ;;
    esac
    clear_branch_state
    complete_behavior_prompt_baseline

    local now latest count classification task_start source_day ingested_at first
    now="$(date '+%s')"
    latest=$((now + 30))
    count=10
    classification="unknown"
    task_start=$((now - 11 * 60))
    source_day="$(date '+%Y-%m-%d')"
    ingested_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    case "$phase" in
        short) count=9 ;;
        no-task) ;;
        late-task) task_start=$((now - 5 * 60)) ;;
        stale) latest=$((now - 4 * 60)) ;;
        certain) classification="work" ;;
    esac
    first=$((latest - (count - 1) * 60))

    local start_iso
    start_iso="$(date -u -r "$task_start" '+%Y-%m-%dT%H:%M:%SZ')"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind)
VALUES ('$TASK_ID', '$TASK_TITLE', 9, 0, '$ingested_at', 'local');
WITH RECURSIVE minute(n) AS (
    VALUES(0)
    UNION ALL SELECT n + 1 FROM minute WHERE n + 1 < $count
)
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version
)
SELECT '$source_day', $first + (n * 60), 'QA', 'Safari', '$PRIVATE_TITLE', '$PRIVATE_URL',
       0, NULL, '$ingested_at', '$classification', 1
FROM minute;
COMMIT;
SQL
    if [[ "$phase" != "no-task" ]]; then
        sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO task_execution_states(task_id, state, updated_at)
VALUES ('$TASK_ID', 'active', '$start_iso');
INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
VALUES ('$TASK_ID', '$start_iso', NULL);
COMMIT;
SQL
    fi
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE window_title = '$PRIVATE_TITLE' AND url = '$PRIVATE_URL';" "$count" "owned behavior rows"
    print -- "PASS: prepared $phase ambiguity fixture"
}

assert_prompt() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "1" "ambiguity prompt count"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND state IN ('queued','presented');" "1" "waiting ambiguity prompt"
    assert_scalar "SELECT title FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "Did this support $TASK_TITLE?" "prompt title"
    local summary
    summary="$(scalar "SELECT summary FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';")"
    [[ "$summary" == *"about 10 minutes in Safari"* ]] || fail "prompt summary omits duration and application"
    [[ "$summary" == *"cannot show your intent"* ]] || fail "prompt summary omits uncertainty disclosure"
    [[ "$summary" != *"$PRIVATE_TITLE"* && "$summary" != *"$PRIVATE_URL"* ]] || fail "prompt summary exposes private evidence"
    assert_scalar "SELECT json_extract(payload_json, '$.actions[0].kind') FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "classify_as_supporting_work" "first action"
    assert_scalar "SELECT json_extract(payload_json, '$.actions[1].kind') FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "classify_as_gaming" "second action"
    assert_scalar "SELECT json_extract(payload_json, '$.actions[2].kind') FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "keep_activity_unknown" "third action"
    assert_scalar "SELECT json_array_length(json_extract(payload_json, '$.actions')) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "3" "public action count"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE payload_json LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_URL%';" "0" "private payload exclusion"
    print -- "PASS: one privacy-safe ambiguity prompt is durably waiting"
}

assert_absent() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "0" "boundary prompt absence"
    print -- "PASS: ambiguity prompt is absent"
}

assert_effect() {
    local effect="$ARGUMENT_ONE"
    require_database
    local response classification correction_count expected_task
    case "$effect" in
        work)
            response="classify_as_supporting_work"
            classification="work"
            correction_count=1
            expected_task="$TASK_ID"
            ;;
        gaming)
            response="classify_as_gaming"
            classification="gaming"
            correction_count=1
            expected_task=""
            ;;
        unknown)
            response="keep_activity_unknown"
            classification=""
            correction_count=0
            expected_task=""
            ;;
        *) fail "unsupported effect: $effect" ;;
    esac
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND state = 'responded';" "1" "responded prompt"
    assert_scalar "SELECT COUNT(*) FROM prompt_responses response JOIN prompt_episodes episode ON episode.id = response.prompt_id WHERE episode.prompt_type = 'AMBIGUOUS_ACTIVITY' AND response.response = '$response' AND response.surface = 'dashboard';" "1" "exact dashboard response"
    assert_scalar "SELECT COUNT(*) FROM prompt_response_effects effect JOIN prompt_episodes episode ON episode.id = effect.prompt_id WHERE episode.prompt_type = 'AMBIGUOUS_ACTIVITY' AND effect.state = 'applied';" "1" "applied response effect"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE source_day = (SELECT json_extract(payload_json, '$.payload.sourceDay') FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY');" "$correction_count" "correction count"
    if [[ "$correction_count" == "1" ]]; then
        assert_scalar "SELECT classification FROM daily_review_corrections LIMIT 1;" "$classification" "persisted classification"
        assert_scalar "SELECT COALESCE(task_id, '') FROM daily_review_corrections LIMIT 1;" "$expected_task" "persisted task attachment"
        assert_scalar "SELECT start_epoch || '|' || end_epoch FROM daily_review_corrections LIMIT 1;" "$(scalar "SELECT json_extract(payload_json, '$.payload.sessionStartEpoch') || '|' || json_extract(payload_json, '$.payload.sessionEndEpoch') FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';")" "exact corrected session range"
    fi
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE window_title = '$PRIVATE_TITLE' AND classification = 'unknown';" "10" "raw evidence remains unknown"
    print -- "PASS: $effect response has the exact durable effect"
}

assert_no_reprompt() {
    require_database
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';" "1" "single handled prompt"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY' AND state IN ('detected','queued','presented');" "0" "unresolved ambiguity prompts"
    assert_scalar "SELECT COUNT(*) FROM prompt_responses response JOIN prompt_episodes episode ON episode.id = response.prompt_id WHERE episode.prompt_type = 'AMBIGUOUS_ACTIVITY';" "1" "single durable response"
    print -- "PASS: handled session did not prompt again"
}

cleanup_owned() {
    require_database
    sqlite3 -batch "$DATABASE" <<SQL
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DELETE FROM prompt_response_effects WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY');
DELETE FROM prompt_responses WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY');
DELETE FROM prompt_episodes WHERE prompt_type = 'AMBIGUOUS_ACTIVITY';
DELETE FROM daily_review_corrections WHERE source_day IN (SELECT DISTINCT source_day FROM behavior_records WHERE window_title = '$PRIVATE_TITLE');
DELETE FROM behavior_records WHERE window_title = '$PRIVATE_TITLE' AND url = '$PRIVATE_URL';
DELETE FROM task_activity_intervals WHERE task_id = '$TASK_ID';
DELETE FROM task_execution_states WHERE task_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
COMMIT;
PRAGMA foreign_keys = ON;
SQL
    print -- "PASS: removed ZC-025-006 namespaced rows"
}

self_test() {
    local root database qa_root snapshot
    root="$(mktemp -d /private/tmp/zoid-666-zc025006-self-test.XXXXXX)"
    qa_root="$root-runtime"
    snapshot="$root-snapshot"
    mkdir -p "$qa_root/Application Support/Zoid 666"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    trap 'rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc025006-target" "$snapshot.zc025006-manifest" "$snapshot.zc025006-restored-manifest"' EXIT
    sqlite3 "$database" <<'SQL'
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, source_kind TEXT);
CREATE TABLE task_execution_states(task_id TEXT PRIMARY KEY, state TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE task_activity_intervals(id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT);
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY, decision_key TEXT NOT NULL, prompt_type TEXT NOT NULL, state TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, action_token TEXT NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, expires_at_utc TEXT);
CREATE TABLE prompt_responses(id TEXT PRIMARY KEY, prompt_id TEXT NOT NULL, action_token TEXT NOT NULL, response TEXT NOT NULL, surface TEXT NOT NULL, responded_at_utc TEXT NOT NULL);
CREATE TABLE prompt_response_effects(response_id TEXT PRIMARY KEY, prompt_id TEXT NOT NULL, effect_type TEXT NOT NULL, state TEXT NOT NULL, created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE daily_review_corrections(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, start_epoch INTEGER NOT NULL, end_epoch INTEGER NOT NULL, classification TEXT NOT NULL, task_id TEXT, created_at_utc TEXT NOT NULL);
CREATE TABLE baseline_observation_days(local_day TEXT PRIMARY KEY, observed_minutes INTEGER NOT NULL, work_minutes INTEGER NOT NULL, gaming_minutes INTEGER NOT NULL, distracting_minutes INTEGER NOT NULL, unknown_minutes INTEGER NOT NULL, eligible_drift_count INTEGER NOT NULL, coverage TEXT NOT NULL, recorded_at_utc TEXT NOT NULL);
SQL
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot"
    local fixture expected_rows expected_active expected_work
    for fixture in qualifying short no-task late-task stale certain; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot"
        "$SCRIPT_PATH" prepare "$fixture" "$database"
        expected_rows=10
        expected_active=1
        expected_work=0
        [[ "$fixture" == "short" ]] && expected_rows=9
        [[ "$fixture" == "no-task" ]] && expected_active=0
        [[ "$fixture" == "certain" ]] && expected_work=10
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM behavior_records;")" == "$expected_rows" ]] \
            || fail "$fixture self-test row count"
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM task_execution_states WHERE state = 'active';")" == "$expected_active" ]] \
            || fail "$fixture self-test active-task state"
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM behavior_records WHERE classification = 'work';")" == "$expected_work" ]] \
            || fail "$fixture self-test certainty state"
        [[ "$(sqlite3 "$database" "SELECT COUNT(*) FROM baseline_observation_days WHERE coverage = 'complete';")" == "7" ]] \
            || fail "$fixture self-test behavior-prompt baseline"
    done
    local effect response classification task_value source_day start_epoch end_epoch
    for effect in work gaming unknown; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot"
        "$SCRIPT_PATH" prepare qualifying "$database"
        source_day="$(sqlite3 "$database" "SELECT source_day FROM behavior_records LIMIT 1;")"
        start_epoch="$(sqlite3 "$database" "SELECT MIN(epoch) FROM behavior_records;")"
        end_epoch="$(( $(sqlite3 "$database" "SELECT MAX(epoch) FROM behavior_records;") + 60 ))"
        sqlite3 "$database" <<SQL
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc
) VALUES (
    '$PREFIX-prompt', 'ambiguous-activity:$source_day:$start_epoch:$TASK_ID',
    'AMBIGUOUS_ACTIVITY', 'queued', 'Did this support $TASK_TITLE?',
    'Zoid 666 observed about 10 minutes in Safari while $TASK_TITLE was active. Application and duration alone cannot show your intent.',
    '$PREFIX-seed',
    '{"actions":[{"kind":"classify_as_supporting_work"},{"kind":"classify_as_gaming"},{"kind":"keep_activity_unknown"}],"payload":{"sourceDay":"$source_day","sessionStartEpoch":"$start_epoch","sessionEndEpoch":"$end_epoch"}}',
    '2026-07-15T00:00:00Z', '2026-07-15T00:30:00Z'
);
SQL
        "$SCRIPT_PATH" assert-prompt "$database"
        case "$effect" in
            work)
                response="classify_as_supporting_work"
                classification="work"
                task_value="'$TASK_ID'"
                ;;
            gaming)
                response="classify_as_gaming"
                classification="gaming"
                task_value="NULL"
                ;;
            unknown)
                response="keep_activity_unknown"
                classification=""
                task_value="NULL"
                ;;
        esac
        sqlite3 "$database" <<SQL
UPDATE prompt_episodes SET state = 'responded' WHERE id = '$PREFIX-prompt';
INSERT INTO prompt_responses(id, prompt_id, action_token, response, surface, responded_at_utc)
VALUES ('$PREFIX-response', '$PREFIX-prompt', '$PREFIX-token', '$response', 'dashboard', '2026-07-15T00:01:00Z');
INSERT INTO prompt_response_effects(response_id, prompt_id, effect_type, state, created_at_utc, updated_at_utc)
VALUES ('$PREFIX-response', '$PREFIX-prompt', 'AMBIGUOUS_ACTIVITY:$response', 'applied', '2026-07-15T00:01:00Z', '2026-07-15T00:01:00Z');
SQL
        if [[ "$effect" != "unknown" ]]; then
            sqlite3 "$database" <<SQL
INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc)
VALUES ('$PREFIX-correction', '$source_day', $start_epoch, $end_epoch, '$classification', $task_value, '2026-07-15T00:01:00Z');
SQL
        fi
        "$SCRIPT_PATH" assert-effect "$effect" "$database"
        "$SCRIPT_PATH" assert-no-reprompt "$database"
    done
    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot"
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot"
    rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc025006-target" "$snapshot.zc025006-manifest" "$snapshot.zc025006-restored-manifest"
    trap - EXIT
    print -- "PASS: ZC-025-006 ambiguity fixture self-test"
}

[[ -n "$COMMAND" ]] || usage
case "$COMMAND" in
    snapshot-root) snapshot_root ;;
    restore-root) restore_root ;;
    assert-root-restored) assert_root_restored ;;
    prepare) prepare_phase ;;
    assert-prompt) require_database; assert_prompt ;;
    assert-absent) require_database; assert_absent ;;
    assert-effect) assert_effect ;;
    assert-no-reprompt) require_database; assert_no_reprompt ;;
    cleanup-owned) cleanup_owned ;;
    self-test) self_test ;;
    *) usage ;;
esac
