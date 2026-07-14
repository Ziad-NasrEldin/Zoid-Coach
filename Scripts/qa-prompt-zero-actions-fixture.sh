#!/bin/zsh

set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly PROMPT_ID="qa-zero-actions-block-1"
readonly ACTIVE_TASK_ID="qa-zero-actions-active"
readonly REPLACEMENT_TASK_ID="qa-zero-actions-replacement"

if [[ -z "$COMMAND" || -z "$DATABASE" ]]; then
    print -u2 "usage: $0 <prepare|insert|assert-zero|assert-waiting|assert-resolved|cleanup> <database>"
    exit 2
fi

if [[ ! -f "$DATABASE" ]]; then
    print -u2 "FAIL: database does not exist: $DATABASE"
    exit 2
fi

sql() {
    sqlite3 -batch -bail "$DATABASE" "$1"
}

assert_scalar() {
    local query="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(sql "$query")"
    if [[ "$actual" != "$expected" ]]; then
        print -u2 "FAIL: $label expected '$expected', got '$actual'"
        exit 1
    fi
}

case "$COMMAND" in
    prepare)
        sql "
        PRAGMA busy_timeout = 5000;
        BEGIN IMMEDIATE;
        DELETE FROM prompt_response_effects WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_episodes WHERE id = '$PROMPT_ID';
        DELETE FROM task_activity_intervals WHERE task_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM task_execution_states WHERE task_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM daily_plan_entries WHERE reminder_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM source_tasks WHERE source_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        INSERT INTO source_tasks(source_id, title, priority, is_completed, updated_at, source_kind)
        VALUES
            ('$ACTIVE_TASK_ID', 'Ship client proposal', 9, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'local'),
            ('$REPLACEMENT_TASK_ID', 'Prepare launch notes', 8, 0, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'local');
        INSERT INTO daily_plan_entries(
            day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at, is_optional
        )
        VALUES
            (date('now', 'localtime'), '$ACTIVE_TASK_ID', 1, 1, 45, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 0),
            (date('now', 'localtime'), '$REPLACEMENT_TASK_ID', 2, 0, 30, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 0);
        INSERT INTO task_execution_states(task_id, state, updated_at)
        VALUES
            ('$ACTIVE_TASK_ID', 'active', strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
            ('$REPLACEMENT_TASK_ID', 'ready', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
        INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
        VALUES ('$ACTIVE_TASK_ID', strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-5 minutes'), NULL);
        COMMIT;
        "
        "$0" assert-zero "$DATABASE"
        print "PASS: zero-action task fixture prepared"
        ;;
    insert)
        sql "
        PRAGMA busy_timeout = 5000;
        INSERT INTO prompt_episodes(
            id, decision_key, prompt_type, state, title, summary,
            action_token, payload_json, created_at_utc
        )
        VALUES(
            '$PROMPT_ID',
            'qa:zero-actions:block:1',
            'GAMING_DRIFT',
            'presented',
            'Gaming drift detected',
            'Ship client proposal remains unfinished. Choose a recovery action.',
            'qa-zero-actions-token-1',
            json_object(
                'decisionKey', 'qa:zero-actions:block:1',
                'actions', json_array(
                    json_object('kind', 'return_to_active_task', 'title', 'Return to Ship client proposal', 'role', 'primary', 'requiresConfirmation', 0),
                    json_object('kind', 'start_work_sprint', 'title', 'Start a 20-minute work sprint', 'role', 'secondary', 'requiresConfirmation', 0),
                    json_object('kind', 'start_break', 'title', 'Take a break', 'role', 'secondary', 'requiresConfirmation', 0),
                    json_object('kind', 'reschedule_task', 'title', 'Reschedule Ship client proposal', 'role', 'destructive', 'requiresConfirmation', 1),
                    json_object('kind', 'mark_blocked', 'title', 'Mark Ship client proposal blocked', 'role', 'destructive', 'requiresConfirmation', 1),
                    json_object('kind', 'continue_intentionally', 'title', 'Continue intentionally', 'role', 'secondary', 'requiresConfirmation', 0)
                ),
                'payload', json_object(
                    'taskID', '$ACTIVE_TASK_ID',
                    'taskTitle', 'Ship client proposal',
                    'privateSentinel', 'SECRET-E2E-PAYLOAD https://private.invalid/zoid'
                )
            ),
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        );
        "
        "$0" assert-waiting "$DATABASE"
        print "PASS: delayed six-action prompt inserted"
        ;;
    assert-zero)
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID';" "0" "owned prompt count"
        assert_scalar "SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';" "0" "owned response count"
        assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$ACTIVE_TASK_ID' AND state = 'active';" "1" "active task state"
        assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$ACTIVE_TASK_ID' AND is_main_objective = 1;" "1" "active main objective"
        ;;
    assert-waiting)
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID' AND state = 'presented';" "1" "waiting prompt count"
        assert_scalar "SELECT json_valid(payload_json) FROM prompt_episodes WHERE id = '$PROMPT_ID';" "1" "prompt JSON validity"
        assert_scalar "SELECT json_array_length(payload_json, '$.actions') FROM prompt_episodes WHERE id = '$PROMPT_ID';" "6" "prompt action count"
        assert_scalar "SELECT COUNT(DISTINCT json_extract(value, '$.kind')) FROM prompt_episodes, json_each(payload_json, '$.actions') WHERE prompt_episodes.id = '$PROMPT_ID';" "6" "distinct action kind count"
        assert_scalar "SELECT group_concat(json_extract(value, '$.kind'), ',') FROM prompt_episodes, json_each(payload_json, '$.actions') WHERE prompt_episodes.id = '$PROMPT_ID';" "return_to_active_task,start_work_sprint,start_break,reschedule_task,mark_blocked,continue_intentionally" "stable action order"
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes, json_each(payload_json, '$.actions') WHERE prompt_episodes.id = '$PROMPT_ID' AND json_type(value, '$.requiresConfirmation') = 'integer' AND json_extract(value, '$.requiresConfirmation') IN (0, 1);" "6" "numeric confirmation flags"
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID' AND length(created_at_utc) = 20 AND created_at_utc GLOB '????-??-??T??:??:??Z';" "1" "RFC3339 prompt timestamp"
        assert_scalar "SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';" "0" "pre-action response count"
        ;;
    assert-resolved)
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID' AND state = 'responded';" "1" "responded prompt count"
        assert_scalar "SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';" "1" "exactly-once response count"
        assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$ACTIVE_TASK_ID' AND state = 'blocked';" "1" "blocked original task"
        assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$ACTIVE_TASK_ID' AND blocked_reason = 'Waiting for approval.';" "1" "durable blocker reason"
        assert_scalar "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = '$REPLACEMENT_TASK_ID' AND is_main_objective = 1;" "1" "replacement main objective"
        ;;
    cleanup)
        sql "
        PRAGMA busy_timeout = 5000;
        BEGIN IMMEDIATE;
        DELETE FROM prompt_response_effects WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_episodes WHERE id = '$PROMPT_ID';
        DELETE FROM task_activity_intervals WHERE task_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM task_execution_states WHERE task_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM daily_plan_entries WHERE reminder_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        DELETE FROM source_tasks WHERE source_id IN ('$ACTIVE_TASK_ID', '$REPLACEMENT_TASK_ID');
        COMMIT;
        "
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID';" "0" "cleaned prompt count"
        print "PASS: zero-actions prompt fixture removed"
        ;;
    *)
        print -u2 "FAIL: unknown command: $COMMAND"
        exit 2
        ;;
esac
