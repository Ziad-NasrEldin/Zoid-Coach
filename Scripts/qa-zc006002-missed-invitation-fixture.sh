#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly SQLITE3="/usr/bin/sqlite3"
readonly JQ="/usr/bin/jq"
readonly TIME_ZONE="Africa/Cairo"
readonly PRIVATE_SENTINEL="qa-zc006001-private-window-title"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <configure|assert-database|assert-work-unplanned|assert-notification|self-test> [path]"
    exit 2
}

configure() {
    local database="$1"
    [[ -f "$database" && ! -L "$database" && "$database" != *"'"* ]] \
        || fail "isolated database is unavailable or unsafe"
    local planning_hour planning_minute morning_hour morning_minute previous_heartbeat
    planning_hour="$(TZ="$TIME_ZONE" /bin/date -v+5M '+%H')"
    planning_minute="$(TZ="$TIME_ZONE" /bin/date -v+5M '+%M')"
    morning_hour="$(TZ="$TIME_ZONE" /bin/date -v-5M '+%H')"
    morning_minute="$(TZ="$TIME_ZONE" /bin/date -v-5M '+%M')"
    previous_heartbeat="$(/bin/date -u -v-25H '+%Y-%m-%dT%H:%M:%SZ')"

    "$SQLITE3" -batch "$database" <<SQL
BEGIN IMMEDIATE;
UPDATE settings
SET value_json = json_set(
        value_json,
        '$.schedule.timeZoneIdentifier', '$TIME_ZONE',
        '$.schedule.nightlyPlanningTime.hour', CAST('$planning_hour' AS INTEGER),
        '$.schedule.nightlyPlanningTime.minute', CAST('$planning_minute' AS INTEGER),
        '$.schedule.morningConfirmationTime.hour', CAST('$morning_hour' AS INTEGER),
        '$.schedule.morningConfirmationTime.minute', CAST('$morning_minute' AS INTEGER)
    ),
    updated_at_utc = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE key = 'user_policy';
UPDATE policy_versions
SET payload_json = (SELECT value_json FROM settings WHERE key = 'user_policy')
WHERE policy_type = 'user_policy'
  AND version = (SELECT policy_version FROM settings WHERE key = 'user_policy');
DELETE FROM processing_checkpoints WHERE source_id IN ('agent-runtime', 'nightly-plan');
INSERT INTO processing_checkpoints(
    source_id, byte_offset, last_success_at_utc, diagnostic
) VALUES ('agent-runtime', 0, '$previous_heartbeat', NULL);
DELETE FROM prompt_responses;
DELETE FROM prompt_episodes WHERE prompt_type = 'PLAN_READY';
COMMIT;
SQL

    local policy_count heartbeat_count
    policy_count="$($SQLITE3 -batch -noheader "$database" "SELECT COUNT(*) FROM settings WHERE key='user_policy' AND json_extract(value_json, '$.schedule.timeZoneIdentifier')='$TIME_ZONE';")"
    heartbeat_count="$($SQLITE3 -batch -noheader "$database" "SELECT COUNT(*) FROM processing_checkpoints WHERE source_id='agent-runtime' AND last_success_at_utc='$previous_heartbeat';")"
    [[ "$policy_count" == 1 && "$heartbeat_count" == 1 ]] \
        || fail "missed-boundary fixture did not persist"
    print -- "EXPECTED_LOCAL_DAY=$(TZ="$TIME_ZONE" /bin/date '+%Y-%m-%d')"
    print -- "PREVIOUS_HEARTBEAT=$previous_heartbeat"
    print -- "PASS: ZC-006-002 genuine inactive boundary configured"
}

assert_database() {
    local database="$1" expected_day="${2:-$(TZ="$TIME_ZONE" /bin/date '+%Y-%m-%d')}"
    [[ -f "$database" && ! -L "$database" && "$database" != *"'"* ]] \
        || fail "isolated database is unavailable or unsafe"
    local valid
    valid="$($SQLITE3 -batch -noheader "$database" <<SQL
SELECT CASE WHEN
    (SELECT COUNT(*) FROM prompt_episodes
      WHERE prompt_type='PLAN_READY' AND state IN ('queued', 'presented')) = 1
    AND (SELECT COUNT(*) FROM processing_checkpoints
      WHERE source_id='nightly-plan'
        AND last_scheduled_local_day='$expected_day'
        AND last_scheduled_timezone='$TIME_ZONE'
        AND missed_trigger_at_utc IS NOT NULL) = 1
    AND (SELECT COUNT(*) FROM prompt_episodes
      WHERE prompt_type='PLAN_READY'
        AND json_extract(payload_json, '$.payload.localDay')='$expected_day'
        AND json_extract(payload_json, '$.payload.allowsDismissal')='true'
        AND instr(lower(title || ' ' || summary), lower('$PRIVATE_SENTINEL'))=0) = 1
THEN 1 ELSE 0 END;
SQL
)"
    [[ "$valid" == 1 ]] || fail "one idempotent privacy-safe recovered invitation was not persisted"
    print -- "PASS: ZC-006-002 checkpoint and one privacy-safe invitation persisted"
}

assert_work_unplanned() {
    local database="$1" expected_day="$2" expected_prompt_id="$3"
    [[ -f "$database" && ! -L "$database" && "$database" != *"'"* ]] \
        || fail "isolated database is unavailable or unsafe"
    local valid
    valid="$($SQLITE3 -batch -noheader "$database" <<SQL
SELECT CASE WHEN
    (SELECT COUNT(*) FROM prompt_episodes
      WHERE prompt_type='PLAN_READY' AND state IN ('queued', 'presented')) = 0
    AND (SELECT COUNT(*) FROM prompt_episodes
      WHERE id='$expected_prompt_id' AND prompt_type='PLAN_READY' AND state='answered'
        AND json_extract(payload_json, '$.payload.localDay')='$expected_day'
        AND instr(lower(title || ' ' || summary), lower('$PRIVATE_SENTINEL'))=0) = 1
    AND (SELECT COUNT(*) FROM prompt_responses response
      JOIN prompt_episodes episode ON episode.id=response.prompt_id
      WHERE episode.id='$expected_prompt_id' AND episode.prompt_type='PLAN_READY'
        AND response.response='work_unplanned'
        AND response.surface='dashboard') = 1
    AND (SELECT COUNT(*) FROM prompt_response_effects effect
      JOIN prompt_responses response ON response.id=effect.response_id
      JOIN prompt_episodes episode ON episode.id=response.prompt_id
      WHERE episode.id='$expected_prompt_id' AND episode.prompt_type='PLAN_READY'
        AND response.response='work_unplanned'
        AND effect.effect_type='PLAN_READY:work_unplanned'
        AND effect.state='applied') = 1
    AND (SELECT COUNT(*) FROM processing_checkpoints
      WHERE source_id='nightly-plan'
        AND last_scheduled_local_day='$expected_day'
        AND last_scheduled_timezone='$TIME_ZONE'
        AND missed_trigger_at_utc IS NOT NULL) = 1
THEN 1 ELSE 0 END;
SQL
)"
    [[ "$valid" == 1 ]] || fail "Work Unplanned response, applied effect, or recovered checkpoint was not durable"
    print -- "PASS: ZC-006-002 Work Unplanned response and applied effect are durable"
}

assert_notification() {
    local state_file="$1"
    [[ -f "$state_file" && ! -L "$state_file" ]] || fail "OS fixture state is unavailable or unsafe"
    "$JQ" -e --arg sentinel "$PRIVATE_SENTINEL" '
        [.notifications[] | select(.desired.category | endswith("PLAN_READY"))] as $matching
        | ($matching | length) == 1
        and ($matching[0].status == "delivered" or $matching[0].status == "scheduled")
        and (($matching[0].desired.title + " " + $matching[0].desired.body)
            | test($sentinel; "i") | not)
        and ([.audit[] | select(.subsystem == "notifications" and .operation == "schedule")]
            | length) >= 1
    ' "$state_file" >/dev/null || fail "one privacy-safe planning notification was not scheduled"
    print -- "PASS: ZC-006-002 one privacy-safe notification is due"
}

self_test() (
    local root="${TMPDIR:-/private/tmp}/zc006002-fixture-self-test.$$"
    /bin/mkdir -m 700 "$root"
    trap '/bin/rm -rf -- "$root"' EXIT
    local state="$root/state.json"
    "$JQ" -n '{
      notifications: [{
        desired: {title: "Planning is available when you are ready", body: "1 commitment is ready.", category: "qa.PLAN_READY"},
        status: "delivered"
      }],
      audit: [{subsystem: "notifications", operation: "schedule"}]
    }' > "$state"
    assert_notification "$state" >/dev/null
    "$JQ" '.notifications += [.notifications[0]]' "$state" > "$root/duplicate.json"
    if (assert_notification "$root/duplicate.json") >/dev/null 2>&1; then
        fail "duplicate planning notifications were accepted"
    fi
    "$JQ" --arg sentinel "$PRIVATE_SENTINEL" '.notifications[0].desired.body = $sentinel' "$state" > "$root/private.json"
    if (assert_notification "$root/private.json") >/dev/null 2>&1; then
        fail "private notification content was accepted"
    fi
    local database="$root/action.sqlite" expected_day="2026-07-15"
    "$SQLITE3" -batch "$database" <<SQL
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY, prompt_type TEXT, state TEXT, title TEXT, summary TEXT, payload_json TEXT);
CREATE TABLE prompt_responses(id TEXT PRIMARY KEY, prompt_id TEXT, response TEXT, surface TEXT);
CREATE TABLE prompt_response_effects(response_id TEXT, prompt_id TEXT, effect_type TEXT, state TEXT);
CREATE TABLE processing_checkpoints(source_id TEXT, last_scheduled_local_day TEXT, last_scheduled_timezone TEXT, missed_trigger_at_utc TEXT);
INSERT INTO prompt_episodes VALUES(
  'prompt-1', 'PLAN_READY', 'answered',
  'Planning is available when you are ready', 'Nothing is blocked.',
  '{"payload":{"localDay":"$expected_day"}}'
);
INSERT INTO prompt_responses VALUES('response-1', 'prompt-1', 'work_unplanned', 'dashboard');
INSERT INTO prompt_response_effects VALUES('response-1', 'prompt-1', 'PLAN_READY:work_unplanned', 'applied');
INSERT INTO processing_checkpoints VALUES('nightly-plan', '$expected_day', '$TIME_ZONE', '2026-07-14T06:00:00Z');
SQL
    assert_work_unplanned "$database" "$expected_day" prompt-1 >/dev/null
    "$SQLITE3" -batch "$database" "UPDATE prompt_response_effects SET state='pending';"
    if (assert_work_unplanned "$database" "$expected_day" prompt-1) >/dev/null 2>&1; then
        fail "pending Work Unplanned effect was accepted"
    fi
    print -- "PASS: ZC-006-002 fixture self-test rejects privacy, duplicate notification, and non-durable action drift"
)

case "$COMMAND" in
    configure) (( $# == 2 )) || usage; configure "$2" ;;
    assert-database) (( $# == 2 || $# == 3 )) || usage; assert_database "$2" "${3:-}" ;;
    assert-work-unplanned) (( $# == 4 )) || usage; assert_work_unplanned "$2" "$3" "$4" ;;
    assert-notification) (( $# == 2 )) || usage; assert_notification "$2" ;;
    self-test) (( $# == 1 )) || usage; self_test ;;
    *) usage ;;
esac
