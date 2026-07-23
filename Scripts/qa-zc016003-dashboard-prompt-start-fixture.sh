#!/bin/zsh

set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly PROMPT_ID="qa-zc016003-start-prompt"
readonly TASK_ID="qa-ready-task"
readonly DECISION_KEY="qa:zc016003:start:qa-ready-task"

if [[ -z "$COMMAND" || -z "$DATABASE" ]]; then
    print -u2 "usage: $0 <insert|assert-waiting|assert-started|cleanup> <database>"
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
    insert)
        assert_scalar "SELECT COUNT(*) FROM source_tasks WHERE source_id = '$TASK_ID' AND is_completed = 0;" "1" "ready source task"
        assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'ready';" "1" "ready execution state"
        sql "
        PRAGMA busy_timeout = 5000;
        BEGIN IMMEDIATE;
        DELETE FROM prompt_response_effects WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_episodes WHERE id = '$PROMPT_ID';
        INSERT INTO prompt_episodes(
            id, decision_key, prompt_type, state, title, summary,
            action_token, payload_json, created_at_utc
        )
        VALUES(
            '$PROMPT_ID',
            '$DECISION_KEY',
            'QA_TASK_START',
            'presented',
            'Ready to start?',
            'QA Ready Task is the current recommendation.',
            'qa-zc016003-episode-seed',
            json_object(
                'decisionKey', '$DECISION_KEY',
                'actions', json_array(
                    json_object(
                        'kind', 'start_recommended_task',
                        'title', 'Start QA Ready Task',
                        'role', 'primary',
                        'requiresConfirmation', 0
                    )
                ),
                'payload', json_object(
                    'taskID', '$TASK_ID',
                    'taskTitle', 'QA Ready Task'
                )
            ),
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        );
        COMMIT;
        "
        "$0" assert-waiting "$DATABASE"
        print "PASS: ZC-016-003 dashboard prompt fixture inserted"
        ;;
    assert-waiting)
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID' AND state = 'presented';" "1" "waiting prompt"
        assert_scalar "SELECT json_valid(payload_json) FROM prompt_episodes WHERE id = '$PROMPT_ID';" "1" "prompt JSON validity"
        assert_scalar "SELECT json_array_length(payload_json, '$.actions') FROM prompt_episodes WHERE id = '$PROMPT_ID';" "1" "prompt action count"
        assert_scalar "SELECT json_extract(payload_json, '$.actions[0].kind') FROM prompt_episodes WHERE id = '$PROMPT_ID';" "start_recommended_task" "canonical start action"
        assert_scalar "SELECT json_extract(payload_json, '$.payload.taskID') FROM prompt_episodes WHERE id = '$PROMPT_ID';" "$TASK_ID" "task binding"
        assert_scalar "SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';" "0" "pre-action response count"
        ;;
    assert-started)
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID' AND state = 'responded';" "1" "responded prompt"
        assert_scalar "SELECT COUNT(*) FROM prompt_responses WHERE prompt_id = '$PROMPT_ID' AND response = 'start_recommended_task';" "1" "exactly one start response"
        assert_scalar "SELECT COUNT(*) FROM prompt_response_effects WHERE prompt_id = '$PROMPT_ID';" "1" "exactly one durable effect"
        assert_scalar "SELECT COUNT(*) FROM task_execution_states WHERE task_id = '$TASK_ID' AND state = 'active';" "1" "active task state"
        assert_scalar "SELECT COUNT(*) FROM task_activity_intervals WHERE task_id = '$TASK_ID' AND ended_at IS NULL;" "1" "single open interval"
        ;;
    cleanup)
        sql "
        PRAGMA busy_timeout = 5000;
        BEGIN IMMEDIATE;
        DELETE FROM prompt_response_effects WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_responses WHERE prompt_id = '$PROMPT_ID';
        DELETE FROM prompt_episodes WHERE id = '$PROMPT_ID';
        COMMIT;
        "
        assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE id = '$PROMPT_ID';" "0" "cleaned prompt"
        print "PASS: ZC-016-003 dashboard prompt fixture removed"
        ;;
    *)
        print -u2 "FAIL: unknown command: $COMMAND"
        exit 2
        ;;
esac
