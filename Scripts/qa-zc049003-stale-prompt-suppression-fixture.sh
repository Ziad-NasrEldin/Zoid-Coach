#!/bin/zsh
set -euo pipefail

readonly INITIAL_PROMPT_ID='qa-zc049003-initial'
readonly INITIAL_TITLE='Is this gaming intentional?'
readonly INITIAL_SUMMARY='Gaming was observed while a priority task remains unfinished.'
readonly PRIVATE_APP='ZC049003_PRIVATE_APP'
readonly PRIVATE_WINDOW='ZC049003_PRIVATE_WINDOW'
readonly PRIVATE_URL='https://private.invalid/zc049003'

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "Usage: $0 self-test"
    print -u2 -- "       $0 snapshot|restore DATABASE OS_STATE BACKUP_DIR"
    print -u2 -- "       $0 seed-initial|invalidate-evidence|refresh-evidence|assert-initial|assert-stale|assert-fresh DATABASE OS_STATE DAY"
    print -u2 -- "       $0 capture-guard|assert-guard-preserved DATABASE GUARD_FILE"
    exit 64
}

sql_scalar() {
    local database="$1" query="$2" label="$3" value
    value="$(sqlite3 -batch -noheader "$database" "$query")" || fail "SQL failed for $label"
    print -r -- "$value"
}

assert_scalar() {
    local database="$1" query="$2" expected="$3" label="$4" actual
    actual="$(sql_scalar "$database" "$query" "$label")" || exit 1
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

require_tools() {
    command -v sqlite3 >/dev/null || fail "sqlite3 is required"
    command -v jq >/dev/null || fail "jq is required"
    command -v shasum >/dev/null || fail "shasum is required"
}

require_database() {
    local database="$1"
    [[ -f "$database" ]] || fail "database does not exist: $database"
    assert_scalar "$database" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='prompt_episodes';" 1 "prompt_episodes table"
    assert_scalar "$database" "SELECT COUNT(*) FROM pragma_table_info('prompt_episodes') WHERE name IN ('id','decision_key','prompt_type','state','title','summary','action_token','payload_json','created_at_utc','expires_at_utc','resolution_origin','resolution_reason');" 12 "prompt_episodes schema"
    assert_scalar "$database" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='behavior_records';" 1 "behavior_records table"
}

require_os_state() {
    local os_state="$1"
    [[ -f "$os_state" ]] || fail "OS fixture state does not exist: $os_state"
    jq -e '.notifications | type == "array"' "$os_state" >/dev/null || fail "OS fixture notifications are unavailable"
}

require_day() {
    [[ "$1" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ]] || fail "day must use YYYY-MM-DD"
}

rewrite_os_state() {
    local os_state="$1" filter="$2" tmp
    tmp="$(mktemp "${os_state:h}/.zc049003-state.XXXXXX")"
    if ! jq --arg prompt "$INITIAL_PROMPT_ID" "$filter" "$os_state" > "$tmp"; then
        rm -f "$tmp"
        fail "OS fixture JSON update failed"
    fi
    chmod --reference="$os_state" "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$os_state"
}

snapshot() {
    local database="$1" os_state="$2" backup="$3"
    require_database "$database"
    require_os_state "$os_state"
    [[ ! -e "$backup" ]] || fail "backup path already exists: $backup"
    mkdir -m 700 "$backup"
    cp -p "$database" "$backup/database.sqlite3"
    cp -p "$os_state" "$backup/os-state.json"
    {
        shasum -a 256 "$backup/database.sqlite3" | awk '{print $1}'
        shasum -a 256 "$backup/os-state.json" | awk '{print $1}'
    } > "$backup/sha256"
    chmod 600 "$backup/sha256"
    print -- "PASS: saved exact database and OS fixture bytes"
}

restore() {
    local database="$1" os_state="$2" backup="$3" database_hash state_hash
    [[ -f "$backup/database.sqlite3" && -f "$backup/os-state.json" && -f "$backup/sha256" ]] || fail "backup is incomplete"
    database_hash="$(sed -n '1p' "$backup/sha256")"
    state_hash="$(sed -n '2p' "$backup/sha256")"
    [[ "$database_hash" =~ '^[0-9a-f]{64}$' && "$state_hash" =~ '^[0-9a-f]{64}$' ]] || fail "backup hashes are invalid"
    cp -p "$backup/database.sqlite3" "$database"
    cp -p "$backup/os-state.json" "$os_state"
    [[ "$(shasum -a 256 "$database" | awk '{print $1}')" == "$database_hash" ]] || fail "database restore is not byte exact"
    [[ "$(shasum -a 256 "$os_state" | awk '{print $1}')" == "$state_hash" ]] || fail "OS fixture restore is not byte exact"
    print -- "PASS: restored exact database and OS fixture bytes"
}

seed_initial() {
    local database="$1" os_state="$2" day="$3" now start
    require_database "$database"
    require_os_state "$os_state"
    require_day "$day"
    now="$(date +%s)"
    start=$((now - 540))
    sqlite3 -batch "$database" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE app_name = '$PRIVATE_APP';
DELETE FROM prompt_episodes WHERE id = '$INITIAL_PROMPT_ID';
INSERT INTO behavior_records(src_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version)
WITH RECURSIVE offsets(value) AS (VALUES(0) UNION ALL SELECT value + 1 FROM offsets WHERE value < 9)
SELECT '$day', $start + (value * 60), 'QA', '$PRIVATE_APP', '$PRIVATE_WINDOW', '$PRIVATE_URL', 0, NULL,
       strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), 'gaming', 1
FROM offsets;
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token, payload_json,
    created_at_utc, expires_at_utc, resolution_origin, resolution_reason
) VALUES (
    '$INITIAL_PROMPT_ID', 'gaming-drift:$day:$start', 'GAMING_DRIFT', 'presented',
    '$INITIAL_TITLE', '$INITIAL_SUMMARY', 'qa-zc049003-token',
    json_object(
        'decisionKey', 'gaming-drift:$day:$start',
        'actions', json_array(),
        'payload', json_object(
            'application', '$PRIVATE_APP',
            'privateWindow', '$PRIVATE_WINDOW',
            'privateURL', '$PRIVATE_URL',
            'allowsDismissal', 'true'
        ),
        'presentedAt', json('null'),
        'resolvedAt', json('null')
    ),
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '+30 minutes'),
    NULL, NULL
);
COMMIT;
SQL
    rewrite_os_state "$os_state" '
        .notifications |= map(select(.desired.promptID != $prompt)) |
        .notifications += [{
            id: $prompt,
            desired: {
                category: "GAMING_DRIFT",
                title: "Is this gaming intentional?",
                body: "Gaming was observed while a priority task remains unfinished.",
                promptID: $prompt,
                deliveryDate: null
            },
            status: "delivered",
            deliveredAt: null,
            actionIdentifier: null,
            respondedAt: null
        }]'
    assert_initial "$database" "$os_state"
}

invalidate_evidence() {
    local database="$1" day="$2" future
    require_database "$database"
    require_day "$day"
    future=$(( $(date +%s) + 600 ))
    sqlite3 -batch "$database" "UPDATE behavior_records SET epoch = $future WHERE rowid = (SELECT rowid FROM behavior_records WHERE src_day='$day' AND app_name='$PRIVATE_APP' ORDER BY epoch DESC LIMIT 1);"
    assert_scalar "$database" "SELECT COUNT(*) FROM behavior_records WHERE src_day='$day' AND app_name='$PRIVATE_APP' AND epoch > CAST(strftime('%s','now') AS INTEGER);" 1 "future-invalid Screenwatch evidence"
    print -- "PASS: staged future-invalid Screenwatch evidence"
}

refresh_evidence() {
    local database="$1" day="$2" current
    require_database "$database"
    require_day "$day"
    current="$(date +%s)"
    sqlite3 -batch "$database" "UPDATE behavior_records SET epoch = $current WHERE rowid = (SELECT rowid FROM behavior_records WHERE src_day='$day' AND app_name='$PRIVATE_APP' ORDER BY epoch DESC LIMIT 1);"
    assert_scalar "$database" "SELECT COUNT(*) FROM behavior_records WHERE src_day='$day' AND app_name='$PRIVATE_APP' AND epoch BETWEEN CAST(strftime('%s','now') AS INTEGER)-5 AND CAST(strftime('%s','now') AS INTEGER)+5;" 1 "current Screenwatch evidence"
    print -- "PASS: restored current Screenwatch evidence for the same session"
}

assert_initial() {
    local database="$1" os_state="$2"
    require_database "$database"
    require_os_state "$os_state"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID' AND prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented') AND resolution_origin IS NULL AND resolution_reason IS NULL;" 1 "initial unresolved prompt"
    assert_scalar "$database" "SELECT json_extract(payload_json, '$.payload.application') FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID';" "$PRIVATE_APP" "private payload sentinel"
    [[ "$(jq --arg id "$INITIAL_PROMPT_ID" '[.notifications[] | select(.desired.promptID == $id and (.status == "scheduled" or .status == "delivered"))] | length' "$os_state")" == 1 ]] || fail "initial fixture notification is absent"
    print -- "PASS: initial prompt and notification are present"
}

assert_stale() {
    local database="$1" os_state="$2"
    require_database "$database"
    require_os_state "$os_state"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID' AND state='dismissed' AND decision_key LIKE 'resolved:%' AND resolution_origin='system' AND resolution_reason='screenwatch_evidence_invalid';" 1 "stale prompt withdrawal"
    [[ "$(jq --arg id "$INITIAL_PROMPT_ID" '[.notifications[] | select(.desired.promptID == $id and (.status == "scheduled" or .status == "delivered"))] | length' "$os_state")" == 0 ]] || fail "stale prompt notification was not removed"
    print -- "PASS: stale prompt and notification were withdrawn"
}

assert_fresh() {
    local database="$1" os_state="$2" original_key
    require_database "$database"
    require_os_state "$os_state"
    original_key="$(sql_scalar "$database" "SELECT substr(decision_key, instr(decision_key, 'gaming-drift:')) FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID';" "original decision key")"
    [[ -n "$original_key" ]] || fail "original decision key is unavailable"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id != '$INITIAL_PROMPT_ID' AND decision_key='$original_key' AND prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented');" 1 "fresh same-session recovery prompt"
    local fresh_id
    fresh_id="$(sql_scalar "$database" "SELECT id FROM prompt_episodes WHERE id != '$INITIAL_PROMPT_ID' AND decision_key='$original_key' AND state IN ('detected','queued','presented') LIMIT 1;" "fresh prompt identifier")"
    [[ -n "$fresh_id" ]] || fail "fresh prompt identifier is absent"
    [[ "$(jq --arg id "$fresh_id" '[.notifications[] | select(.desired.promptID == $id and (.status == "scheduled" or .status == "delivered"))] | length' "$os_state")" == 1 ]] || fail "fresh recovery notification is absent"
    print -- "PASS: fresh evidence recovered one same-session prompt and notification"
}

capture_guard() {
    local database="$1" guard_file="$2" tmp
    require_database "$database"
    tmp="$(mktemp "${guard_file:h}/.zc049003-guard.XXXXXX")"
    jq -n \
        --arg total "$(sql_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT';" "gaming prompt count")" \
        --arg user "$(sql_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state='dismissed' AND resolution_origin='user';" "user dismissal count")" \
        --arg unresolved "$(sql_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented');" "unresolved prompt count")" \
        '{total: ($total|tonumber), userDismissed: ($user|tonumber), unresolved: ($unresolved|tonumber)}' > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$guard_file"
    print -- "PASS: captured dismissal, cooldown, and daily-cap guard counts"
}

assert_guard_preserved() {
    local database="$1" guard_file="$2"
    require_database "$database"
    jq -e '.total >= 0 and .userDismissed >= 1 and .unresolved >= 0' "$guard_file" >/dev/null || fail "guard snapshot is invalid or has no user dismissal"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT';" "$(jq -r .total "$guard_file")" "preserved prompt count"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state='dismissed' AND resolution_origin='user';" "$(jq -r .userDismissed "$guard_file")" "preserved user dismissal count"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE prompt_type='GAMING_DRIFT' AND state IN ('detected','queued','presented');" "$(jq -r .unresolved "$guard_file")" "preserved unresolved count"
    print -- "PASS: user dismissal and prompt gates were preserved"
}

expect_failure_message() {
    local needle="$1"
    shift
    local output exit_code
    set +e
    output="$("$@" 2>&1)"
    exit_code=$?
    set -e
    (( exit_code != 0 )) || fail "negative self-test unexpectedly succeeded: $needle"
    print -r -- "$output" | grep -Fq "$needle" || fail "negative self-test failed for the wrong reason: $needle"
}

self_test() {
    local root database os_state backup guard day start fresh_id original_hash
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc049003-fixture.XXXXXX")"
    trap "rm -rf ${(q)root}" EXIT
    database="$root/qa.sqlite3"
    os_state="$root/state.json"
    backup="$root/backup"
    guard="$root/guard.json"
    day="$(date +%F)"
    sqlite3 -batch "$database" <<'SQL'
CREATE TABLE prompt_episodes(
 id TEXT PRIMARY KEY, decision_key TEXT NOT NULL, prompt_type TEXT NOT NULL, state TEXT NOT NULL,
 title TEXT NOT NULL, summary TEXT NOT NULL, action_token TEXT NOT NULL, payload_json TEXT NOT NULL,
 created_at_utc TEXT NOT NULL, expires_at_utc TEXT, resolution_origin TEXT, resolution_reason TEXT
);
CREATE TABLE behavior_records(
 src_day TEXT, epoch INTEGER, time_label TEXT, app_name TEXT, window_title TEXT, url TEXT,
 has_screenshot INTEGER, screenshot_path TEXT, ingested_at TEXT, classification TEXT,
 classification_policy_version INTEGER
);
SQL
    print -r -- '{"notifications":[]}' > "$os_state"
    expect_failure_message "initial unresolved prompt" assert_initial "$database" "$os_state"
    local broken="$root/broken.sqlite3"
    sqlite3 "$broken" 'CREATE TABLE unrelated(value TEXT);'
    expect_failure_message "prompt_episodes table" require_database "$broken"
    snapshot "$database" "$os_state" "$backup"
    original_hash="$(shasum -a 256 "$database" "$os_state")"
    seed_initial "$database" "$os_state" "$day"
    invalidate_evidence "$database" "$day"
    expect_failure_message "stale prompt withdrawal" assert_stale "$database" "$os_state"
    sqlite3 "$database" "UPDATE prompt_episodes SET decision_key='resolved:' || id || ':' || decision_key, state='dismissed', resolution_origin='system', resolution_reason='screenwatch_evidence_invalid' WHERE id='$INITIAL_PROMPT_ID';"
    rewrite_os_state "$os_state" '.notifications |= map(select(.desired.promptID != $prompt))'
    assert_stale "$database" "$os_state"
    refresh_evidence "$database" "$day"
    expect_failure_message "fresh same-session recovery prompt" assert_fresh "$database" "$os_state"
    start="$(sql_scalar "$database" "SELECT substr(decision_key, instr(decision_key, 'gaming-drift:')) FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID';" "self-test decision key")"
    fresh_id='qa-zc049003-fresh'
    sqlite3 "$database" "INSERT INTO prompt_episodes SELECT '$fresh_id', '$start', prompt_type, 'presented', title, summary, 'fresh-token', replace(payload_json, '$INITIAL_PROMPT_ID', '$fresh_id'), created_at_utc, expires_at_utc, NULL, NULL FROM prompt_episodes WHERE id='$INITIAL_PROMPT_ID';"
    rewrite_os_state "$os_state" '.notifications += [{id:"qa-zc049003-fresh",desired:{category:"GAMING_DRIFT",title:"Recovered",body:"Recovered",promptID:"qa-zc049003-fresh",deliveryDate:null},status:"delivered",deliveredAt:null,actionIdentifier:null,respondedAt:null}]'
    assert_fresh "$database" "$os_state"
    sqlite3 "$database" "UPDATE prompt_episodes SET decision_key='resolved:' || id || ':' || decision_key, state='dismissed', resolution_origin='user', resolution_reason='explicit_dismissal' WHERE id='$fresh_id';"
    capture_guard "$database" "$guard"
    assert_guard_preserved "$database" "$guard"
    sqlite3 "$database" "INSERT INTO prompt_episodes SELECT 'qa-zc049003-unexpected', 'unexpected', prompt_type, 'presented', title, summary, 'unexpected-token', payload_json, created_at_utc, expires_at_utc, NULL, NULL FROM prompt_episodes WHERE id='$fresh_id';"
    expect_failure_message "preserved prompt count" assert_guard_preserved "$database" "$guard"
    restore "$database" "$os_state" "$backup"
    [[ "$(shasum -a 256 "$database" "$os_state")" == "$original_hash" ]] || fail "self-test exact restore comparison failed"
    print -- "PASS: ZC-049-003 fixture self-test"
}

require_tools
COMMAND="${1:-}"
case "$COMMAND" in
    self-test)
        (( $# == 1 )) || usage
        self_test
        ;;
    snapshot|restore)
        (( $# == 4 )) || usage
        "$COMMAND" "$2" "$3" "$4"
        ;;
    seed-initial|assert-initial|assert-stale|assert-fresh)
        (( $# == 4 )) || usage
        case "$COMMAND" in
            seed-initial) seed_initial "$2" "$3" "$4" ;;
            assert-initial) assert_initial "$2" "$3" ;;
            assert-stale) assert_stale "$2" "$3" ;;
            assert-fresh) assert_fresh "$2" "$3" ;;
        esac
        ;;
    invalidate-evidence|refresh-evidence)
        (( $# == 4 )) || usage
        if [[ "$COMMAND" == invalidate-evidence ]]; then invalidate_evidence "$2" "$4"; else refresh_evidence "$2" "$4"; fi
        ;;
    capture-guard|assert-guard-preserved)
        (( $# == 3 )) || usage
        if [[ "$COMMAND" == capture-guard ]]; then capture_guard "$2" "$3"; else assert_guard_preserved "$2" "$3"; fi
        ;;
    *) usage ;;
esac
