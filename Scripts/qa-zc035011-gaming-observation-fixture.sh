#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly SCRIPT_PATH="${0:A}"
readonly TIME_ZONE="${ZOID_666_QA_ZC035011_TIME_ZONE:-Africa/Cairo}"
readonly LOCAL_DAY="${ZOID_666_QA_ZC035011_DAY:-$(TZ="$TIME_ZONE" date '+%F')}"
readonly NOW_EPOCH="${ZOID_666_QA_ZC035011_NOW_EPOCH:-$(date '+%s')}"
readonly PREFIX="qa-zc035011"
readonly TASK_ID="$PREFIX-priority"
readonly TASK_TITLE="ZC-035-011 priority objective"
readonly PRIVATE_TITLE="PRIVATE-ZC035011-WINDOW-SENTINEL"
readonly PRIVATE_URL="https://private-zc035011.invalid/raw?secret=sentinel"
readonly BACKUP_TABLE="qa_zc035011_policy_backup"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare-gaming|assert-coaching|advance-aligned|assert-observation|advance-gaming|assert-recoaching|cleanup|self-test> [database]"
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

require_table() {
    assert_scalar \
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$1';" \
        "1" \
        "$1 table"
}

require_schema() {
    local table
    for table in settings policy_versions behavior_records daily_review_corrections baseline_observation_days source_tasks daily_plan_entries prompt_episodes notification_delivery_events; do
        require_table "$table"
    done
    command -v jq >/dev/null 2>&1 || fail "jq is required"
    assert_scalar "SELECT COUNT(*) FROM settings WHERE key = 'user_policy';" "1" "active policy setting"
    assert_scalar "SELECT COUNT(*) FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1;" "1" "active policy version"
}

sql_quote() {
    print -r -- "${1//\'/\'\'}"
}

timestamp() {
    date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

owned_prompt_filter() {
    print -r -- "prompt_type = 'GAMING_DRIFT' AND payload_json LIKE '%\"taskID\":\"$TASK_ID\"%'"
}

backup_and_configure_policy() {
    assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$BACKUP_TABLE';" "0" "unused policy backup namespace"
    local setting_payload version_payload version configured_payload quoted
    setting_payload="$(scalar "SELECT value_json FROM settings WHERE key = 'user_policy';")"
    version="$(scalar "SELECT policy_version FROM settings WHERE key = 'user_policy';")"
    version_payload="$(scalar "SELECT payload_json FROM policy_versions WHERE policy_type = 'user_policy' AND version = $version;")"
    [[ -n "$setting_payload" && -n "$version_payload" ]] || fail "active policy payload is unavailable"
    configured_payload="$(print -r -- "$setting_payload" | jq -c \
        --arg timeZone "$TIME_ZONE" \
        '.operatingMode = "autonomous"
        | .automationPause.pauseRequested = false
        | .automationPause.resumesAtUTC = null
        | .schedule.timeZoneIdentifier = $timeZone
        | .schedule.workWindows = [{weekdays:[1,2,3,4,5,6,7],start:{hour:0,minute:0},end:{hour:23,minute:59}}]
        | .gaming.dailyBudgetMinutes = 0
        | .gaming.priorityTaskRewardMinutes = 0
        | .gaming.coachingLevel = "gentle"
        | .gaming.dailyPromptCap = 3
        | .gaming.promptCooldownMinutes = 5
        | .gaming.taskStartGraceMinutes = 0
        | .gaming.returnFromIdleGraceMinutes = 0
        | .gaming.budgetEnabled = true')"
    print -r -- "$configured_payload" | jq -e \
        --arg timeZone "$TIME_ZONE" \
        '.operatingMode == "autonomous"
        and .automationPause.pauseRequested == false
        and .schedule.timeZoneIdentifier == $timeZone
        and .gaming.dailyBudgetMinutes == 0
        and .gaming.budgetEnabled == true' >/dev/null \
        || fail "configured policy is invalid"
    setting_payload="$(sql_quote "$setting_payload")"
    version_payload="$(sql_quote "$version_payload")"
    quoted="$(sql_quote "$configured_payload")"
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
CREATE TABLE $BACKUP_TABLE (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    policy_version INTEGER NOT NULL,
    setting_payload TEXT NOT NULL,
    version_payload TEXT NOT NULL
);
INSERT INTO $BACKUP_TABLE(singleton, policy_version, setting_payload, version_payload)
VALUES (1, $version, '$setting_payload', '$version_payload');
UPDATE settings
SET value_json = '$quoted'
WHERE key = 'user_policy' AND policy_version = $version;
UPDATE policy_versions
SET payload_json = '$quoted'
WHERE policy_type = 'user_policy' AND version = $version;
COMMIT;
SQL
    assert_scalar "SELECT COUNT(*) FROM $BACKUP_TABLE;" "1" "policy backup"
}

seed_baseline() {
    local values=""
    local day
    for day in {1..7}; do
        values+="('1998-01-0$day',480,420,30,15,15,1,'complete','1998-01-0${day}T23:59:00Z')"
        (( day < 7 )) && values+=","
    done
    assert_scalar "SELECT COUNT(*) FROM baseline_observation_days WHERE local_day BETWEEN '1998-01-01' AND '1998-01-07';" "0" "unused baseline namespace"
    sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO baseline_observation_days(
    local_day, observed_minutes, work_minutes, gaming_minutes,
    distracting_minutes, unknown_minutes, eligible_drift_count,
    coverage, recorded_at_utc
) VALUES $values;
SQL
}

insert_behavior() {
    local phase="$1"
    local classification="$2"
    local first_epoch="$3"
    local count="$4"
    local app="$5"
    local values=""
    local index epoch separator
    for (( index = 0; index < count; index++ )); do
        epoch=$((first_epoch + index * 60))
        separator=","
        (( index == count - 1 )) && separator=""
        values+="('$LOCAL_DAY',$epoch,'$(TZ="$TIME_ZONE" date -r "$epoch" '+%H:%M')','$app','$PRIVATE_TITLE-$phase-$index','$PRIVATE_URL/$phase/$index',0,NULL,'$(timestamp "$epoch")','$classification',1)$separator"
    done
    sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES $values;
SQL
}

prepare_gaming() {
    require_schema
    [[ "$NOW_EPOCH" == <-> ]] || fail "now epoch must be numeric"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-%';" "0" "unused behavior namespace"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND (title != '$TASK_TITLE' OR is_completed != 0);" "0" "conflicting task namespace"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID' AND (is_optional != 0 OR blocked_reason IS NOT NULL OR deferred_until_utc IS NOT NULL);" "0" "conflicting plan namespace"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $(owned_prompt_filter);" "0" "unused prompt namespace"
    backup_and_configure_policy
    seed_baseline
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at)
VALUES ('$TASK_ID', '$TASK_TITLE', 1, 0, '$(timestamp "$NOW_EPOCH")')
ON CONFLICT(source_id) DO UPDATE SET
    title = excluded.title,
    priority = excluded.priority,
    is_completed = 0,
    updated_at = excluded.updated_at;
INSERT INTO daily_plan_entries(
    day_key, reminder_id, rank, is_main_objective, estimate_minutes,
    selection_reason, selection_score, is_optional, blocked_reason,
    deferred_until_utc, updated_at
) VALUES (
    '$LOCAL_DAY', '$TASK_ID', 1, 1, 30,
    'ZC-035-011 signed acceptance', 100, 0, NULL, NULL,
    '$(timestamp "$NOW_EPOCH")'
)
ON CONFLICT(day_key, reminder_id) DO UPDATE SET
    rank = excluded.rank,
    is_main_objective = excluded.is_main_objective,
    estimate_minutes = excluded.estimate_minutes,
    selection_reason = excluded.selection_reason,
    selection_score = excluded.selection_score,
    is_optional = 0,
    blocked_reason = NULL,
    deferred_until_utc = NULL,
    updated_at = excluded.updated_at;
COMMIT;
SQL
    insert_behavior "initial-gaming" "gaming" $((NOW_EPOCH - 541)) 10 "Steam"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-initial-gaming-%';" "10" "initial gaming observations"
    print -- "PASS: prepared a fresh 10-minute gaming session, zero-minute allowance, complete baseline, and unfinished priority objective"
    print -- "WAIT: the signed helper must produce exactly one visible gaming-drift decision through its normal cycle"
}

assert_coaching() {
    require_schema
    local filter
    filter="$(owned_prompt_filter)"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND state IN ('detected','queued','presented');" "1" "unresolved gaming coaching"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND title IN ('Ready for an easy return?','Is this gaming intentional?') AND summary LIKE '%10 observed minutes in Steam%' AND summary LIKE '%$TASK_TITLE remains unfinished%' AND payload_json LIKE '%\"allowsDismissal\":\"true\"%';" "1" "coaching content"
    print -- "PASS: product created exactly one unresolved ZC-035-011 gaming-drift decision"
}

advance_aligned() {
    assert_coaching >/dev/null
    local latest aligned_epoch
    latest="$(scalar "SELECT MAX(epoch) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-initial-gaming-%';")"
    aligned_epoch="$NOW_EPOCH"
    (( aligned_epoch > latest )) || aligned_epoch=$((latest + 1))
    insert_behavior "aligned-work" "work" "$aligned_epoch" 1 "Xcode"
    print -- "PASS: inserted one fresh, certain aligned-work observation after unresolved coaching"
    print -- "WAIT: the signed helper must withdraw the stale decision on its next normal cycle"
}

assert_observation() {
    require_schema
    local filter
    filter="$(owned_prompt_filter)"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-aligned-work-%' AND classification = 'work';" "1" "aligned work observation"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND state IN ('detected','queued','presented');" "0" "unresolved coaching after alignment"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND state = 'dismissed' AND resolution_origin = 'system' AND resolution_reason = 'screenwatch_evidence_invalid';" "1" "system withdrawal"
    print -- "PASS: aligned work withdrew coaching and left observation-only durable state"
}

advance_gaming() {
    assert_observation >/dev/null
    local aligned_epoch first_epoch latest_epoch age
    aligned_epoch="$(scalar "SELECT epoch FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-aligned-work-%' LIMIT 1;")"
    first_epoch=$((aligned_epoch + 1))
    latest_epoch=$((first_epoch + 540))
    (( NOW_EPOCH >= latest_epoch )) \
        || fail "fresh follow-up gaming needs $((latest_epoch - NOW_EPOCH)) more real-time seconds after aligned work"
    age=$((NOW_EPOCH - latest_epoch))
    (( age <= 120 )) \
        || fail "follow-up gaming window was missed by $((age - 120)) seconds; rerun from a clean isolated QA root"
    insert_behavior "later-gaming" "gaming" "$first_epoch" 10 "Steam"
    print -- "PASS: inserted a later fresh 10-minute gaming session after the aligned-work boundary"
    print -- "WAIT: the signed helper must produce one new decision, not revive the withdrawn decision"
}

assert_recoaching() {
    require_schema
    local filter
    filter="$(owned_prompt_filter)"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter;" "2" "two distinct gaming decisions"
    assert_scalar "SELECT COUNT(DISTINCT id) FROM prompt_episodes WHERE $filter;" "2" "distinct decision IDs"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND state = 'dismissed' AND resolution_origin = 'system' AND resolution_reason = 'screenwatch_evidence_invalid';" "1" "preserved withdrawn decision"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $filter AND state IN ('detected','queued','presented') AND summary LIKE '%10 observed minutes in Steam%';" "1" "later unresolved coaching"
    print -- "PASS: later fresh gaming produced exactly one new coaching decision while preserving the withdrawn history"
}

cleanup_fixture() {
    require_schema
    if [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$BACKUP_TABLE';")" == "1" ]]; then
        sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
UPDATE settings
SET value_json = (SELECT setting_payload FROM $BACKUP_TABLE WHERE singleton = 1)
WHERE key = 'user_policy'
  AND policy_version = (SELECT policy_version FROM $BACKUP_TABLE WHERE singleton = 1);
UPDATE policy_versions
SET payload_json = (SELECT version_payload FROM $BACKUP_TABLE WHERE singleton = 1)
WHERE policy_type = 'user_policy'
  AND version = (SELECT policy_version FROM $BACKUP_TABLE WHERE singleton = 1);
DELETE FROM notification_delivery_events
WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE $(owned_prompt_filter));
DELETE FROM prompt_episodes WHERE $(owned_prompt_filter);
DELETE FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID';
DELETE FROM source_tasks WHERE source_id = '$TASK_ID';
DELETE FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-%';
DELETE FROM baseline_observation_days WHERE local_day BETWEEN '1998-01-01' AND '1998-01-07' AND recorded_at_utc LIKE '1998-%';
DROP TABLE $BACKUP_TABLE;
COMMIT;
SQL
    fi
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND window_title LIKE '$PRIVATE_TITLE-%';" "0" "cleaned behavior rows"
    assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID';" "0" "cleaned source task"
    assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = '$LOCAL_DAY' AND reminder_id = '$TASK_ID';" "0" "cleaned plan row"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE $(owned_prompt_filter);" "0" "cleaned prompt rows"
    assert_scalar "SELECT COUNT(*) FROM notification_delivery_events WHERE prompt_id IN ('initial','later');" "0" "cleaned notification evidence"
    print -- "PASS: ZC-035-011 fixture policy and owned rows restored"
}

self_test() {
    local root database original_hash
    root="$(mktemp -d /private/tmp/zoid-666-zc035011-fixture.XXXXXX)"
    database="$root/test.sqlite"
    trap "rm -rf '$root'" EXIT
    sqlite3 -batch "$database" <<'SQL'
CREATE TABLE settings(key TEXT PRIMARY KEY, value_json TEXT NOT NULL, policy_version INTEGER NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE policy_versions(policy_type TEXT NOT NULL, version INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, is_active INTEGER NOT NULL, PRIMARY KEY(policy_type, version));
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_review_corrections(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, start_epoch INTEGER NOT NULL, end_epoch INTEGER NOT NULL, classification TEXT NOT NULL, created_at_utc TEXT NOT NULL);
CREATE TABLE baseline_observation_days(local_day TEXT PRIMARY KEY, observed_minutes INTEGER NOT NULL, work_minutes INTEGER NOT NULL, gaming_minutes INTEGER NOT NULL, distracting_minutes INTEGER NOT NULL, unknown_minutes INTEGER NOT NULL, eligible_drift_count INTEGER NOT NULL, coverage TEXT NOT NULL, recorded_at_utc TEXT NOT NULL);
CREATE TABLE source_tasks(source_id TEXT PRIMARY KEY, title TEXT NOT NULL, due_at TEXT, priority INTEGER NOT NULL DEFAULT 0, is_completed INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL);
CREATE TABLE daily_plan_entries(day_key TEXT NOT NULL, reminder_id TEXT NOT NULL, rank INTEGER NOT NULL, is_main_objective INTEGER NOT NULL, estimate_minutes INTEGER, selection_reason TEXT, selection_score INTEGER, is_optional INTEGER NOT NULL DEFAULT 0, blocked_reason TEXT, deferred_until_utc TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(day_key, reminder_id));
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY, decision_key TEXT NOT NULL UNIQUE, prompt_type TEXT NOT NULL, state TEXT NOT NULL, title TEXT NOT NULL, summary TEXT NOT NULL, action_token TEXT NOT NULL UNIQUE, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, expires_at_utc TEXT, resolution_origin TEXT, resolution_reason TEXT);
CREATE TABLE notification_delivery_events(id INTEGER PRIMARY KEY AUTOINCREMENT, request_identifier TEXT NOT NULL, prompt_id TEXT NOT NULL, category TEXT NOT NULL, outcome TEXT NOT NULL, scheduled_for TEXT, recorded_at TEXT NOT NULL, attempt INTEGER NOT NULL, replaced_prior_request INTEGER NOT NULL DEFAULT 0, redacted_error TEXT);
INSERT INTO settings VALUES('user_policy','{"operatingMode":"suggest","automationPause":{"pauseRequested":false},"schedule":{"timeZoneIdentifier":"UTC","workWindows":[]},"gaming":{"dailyBudgetMinutes":60,"priorityTaskRewardMinutes":15,"coachingLevel":"gentle","dailyPromptCap":1,"promptCooldownMinutes":180,"taskStartGraceMinutes":3,"returnFromIdleGraceMinutes":1,"budgetEnabled":true}}',1,'2033-05-18T00:00:00Z');
INSERT INTO policy_versions VALUES('user_policy',1,(SELECT value_json FROM settings WHERE key='user_policy'),'2033-05-18T00:00:00Z',1);
SQL
    original_hash="$(sqlite3 -batch -noheader "$database" "SELECT hex(value_json) FROM settings WHERE key = 'user_policy';")"
    ZOID_666_QA_ZC035011_DAY=2033-05-18 ZOID_666_QA_ZC035011_NOW_EPOCH=2000000000 "$SCRIPT_PATH" prepare-gaming "$database" >/dev/null
    sqlite3 -batch "$database" <<'SQL'
INSERT INTO prompt_episodes VALUES('initial','gaming-drift:2033-05-18:1999999459','GAMING_DRIFT','queued','Ready for an easy return?','The current session contains 10 observed minutes in Steam while ZC-035-011 priority objective remains unfinished. This shows activity, not why it happened or what you intended.','token-1','{"actions":[],"payload":{"taskID":"qa-zc035011-priority","allowsDismissal":"true"}}','2033-05-18T03:33:20Z',NULL,NULL,NULL);
SQL
    ZOID_666_QA_ZC035011_DAY=2033-05-18 ZOID_666_QA_ZC035011_NOW_EPOCH=2000000000 "$SCRIPT_PATH" assert-coaching "$database" >/dev/null
    ZOID_666_QA_ZC035011_DAY=2033-05-18 ZOID_666_QA_ZC035011_NOW_EPOCH=2000000010 "$SCRIPT_PATH" advance-aligned "$database" >/dev/null
    sqlite3 -batch "$database" "UPDATE prompt_episodes SET state='dismissed', decision_key='resolved:initial:' || decision_key, resolution_origin='system', resolution_reason='screenwatch_evidence_invalid' WHERE id='initial';"
    ZOID_666_QA_ZC035011_DAY=2033-05-18 "$SCRIPT_PATH" assert-observation "$database" >/dev/null
    ZOID_666_QA_ZC035011_DAY=2033-05-18 ZOID_666_QA_ZC035011_NOW_EPOCH=2000000610 "$SCRIPT_PATH" advance-gaming "$database" >/dev/null
    sqlite3 -batch "$database" <<'SQL'
INSERT INTO prompt_episodes VALUES('later','gaming-drift:2033-05-18:2000000011','GAMING_DRIFT','queued','Ready for an easy return?','The current session contains 10 observed minutes in Steam while ZC-035-011 priority objective remains unfinished. This shows activity, not why it happened or what you intended.','token-2','{"actions":[],"payload":{"taskID":"qa-zc035011-priority","allowsDismissal":"true"}}','2033-05-18T03:43:30Z',NULL,NULL,NULL);
SQL
    ZOID_666_QA_ZC035011_DAY=2033-05-18 "$SCRIPT_PATH" assert-recoaching "$database" >/dev/null
    ZOID_666_QA_ZC035011_DAY=2033-05-18 "$SCRIPT_PATH" cleanup "$database" >/dev/null
    [[ "$(sqlite3 -batch -noheader "$database" "SELECT hex(value_json) FROM settings WHERE key = 'user_policy';")" == "$original_hash" ]] \
        || fail "cleanup did not restore the exact policy payload"
    print -- "PASS: ZC-035-011 fixture phases, idempotent assertions, privacy ownership, and exact policy restore"
}

if [[ "$COMMAND" == "self-test" ]]; then
    self_test
    exit 0
fi

[[ -n "$COMMAND" && -n "$DATABASE" ]] || usage
[[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

case "$COMMAND" in
    prepare-gaming) prepare_gaming ;;
    assert-coaching) assert_coaching ;;
    advance-aligned) advance_aligned ;;
    assert-observation) assert_observation ;;
    advance-gaming) advance_gaming ;;
    assert-recoaching) assert_recoaching ;;
    cleanup) cleanup_fixture ;;
    *) usage ;;
esac
