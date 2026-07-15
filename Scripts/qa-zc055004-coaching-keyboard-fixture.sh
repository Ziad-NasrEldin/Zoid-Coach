#!/bin/zsh
set -euo pipefail

readonly PRIMARY_ID='qa-zc055004-primary'
readonly SECONDARY_ID='qa-zc055004-secondary'
readonly PRIVATE_VALUE='ZC055004_PRIVATE_PROMPT_PAYLOAD'

fail() { print -u2 -- "FAIL: $*"; exit 1; }

usage() {
    print -u2 -- "Usage: $0 self-test"
    print -u2 -- "       $0 snapshot|restore DATABASE BACKUP"
    print -u2 -- "       $0 seed|assert-ready|assert-dismissed DATABASE"
    exit 64
}

scalar() {
    local database="$1" query="$2" label="$3" value
    value="$(sqlite3 -batch -noheader "$database" "$query")" || fail "SQL failed for $label"
    print -r -- "$value"
}

assert_scalar() {
    local actual
    actual="$(scalar "$1" "$2" "$4")" || exit 1
    [[ "$actual" == "$3" ]] || fail "$4: expected '$3', got '$actual'"
}

require_database() {
    local database="$1"
    [[ -f "$database" ]] || fail "database does not exist: $database"
    assert_scalar "$database" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='prompt_episodes';" 1 "prompt_episodes table"
    assert_scalar "$database" "SELECT COUNT(*) FROM pragma_table_info('prompt_episodes') WHERE name IN ('id','decision_key','prompt_type','state','title','summary','action_token','payload_json','created_at_utc','expires_at_utc','resolution_origin','resolution_reason');" 12 "prompt_episodes schema"
}

snapshot() {
    local database="$1" backup="$2"
    require_database "$database"
    [[ ! -e "$backup" ]] || fail "backup already exists"
    umask 077
    cp -p "$database" "$backup"
    shasum -a 256 "$backup" | awk '{print $1}' > "$backup.sha256"
    print -- "PASS: saved exact database bytes"
}

restore() {
    local database="$1" backup="$2" expected
    [[ -f "$backup" && -f "$backup.sha256" ]] || fail "backup is incomplete"
    expected="$(sed -n '1p' "$backup.sha256")"
    [[ "$expected" =~ '^[0-9a-f]{64}$' ]] || fail "backup hash is invalid"
    cp -p "$backup" "$database"
    [[ "$(shasum -a 256 "$database" | awk '{print $1}')" == "$expected" ]] || fail "database restore is not byte exact"
    print -- "PASS: restored exact database bytes"
}

seed() {
    local database="$1"
    require_database "$database"
    sqlite3 -batch "$database" <<SQL
BEGIN IMMEDIATE;
DELETE FROM prompt_episodes WHERE id IN ('$PRIMARY_ID', '$SECONDARY_ID');
INSERT INTO prompt_episodes(
 id, decision_key, prompt_type, state, title, summary, action_token, payload_json,
 created_at_utc, expires_at_utc, resolution_origin, resolution_reason
) VALUES (
 '$PRIMARY_ID', 'gaming-drift:qa:1', 'GAMING_DRIFT', 'presented', 'Is this gaming intentional?',
 'Choose a keyboard action without exposing private evidence.', 'qa-zc055004-primary-token',
 json_object(
   'decisionKey', 'gaming-drift:qa:1',
   'actions', json_array(
     json_object('kind','return_to_active_task','title','Return to active task','role','primary','requiresConfirmation',json('false')),
     json_object('kind','start_work_sprint','title','Start a work sprint','role','secondary','requiresConfirmation',json('false')),
     json_object('kind','start_break','title','Take a break','role','secondary','requiresConfirmation',json('false')),
     json_object('kind','reschedule_task','title','Reschedule task','role','destructive','requiresConfirmation',json('true')),
     json_object('kind','mark_blocked','title','Mark task blocked','role','destructive','requiresConfirmation',json('true')),
     json_object('kind','continue_intentionally','title','Continue intentionally','role','secondary','requiresConfirmation',json('false'))
   ),
   'payload', json_object('taskID','qa-task','allowsDismissal','true','privateEvidence','$PRIVATE_VALUE'),
   'presentedAt', json('null'), 'resolvedAt', json('null')
 ), strftime('%Y-%m-%dT%H:%M:%SZ','now'), strftime('%Y-%m-%dT%H:%M:%SZ','now','+30 minutes'), NULL, NULL
), (
 '$SECONDARY_ID', 'gaming-drift:qa:2', 'GAMING_DRIFT', 'presented', 'Second coaching decision',
 'This row must not own duplicate global shortcuts.', 'qa-zc055004-secondary-token',
 json_object(
   'decisionKey', 'gaming-drift:qa:2',
   'actions', json_array(json_object('kind','return_to_active_task','title','Return later','role','primary','requiresConfirmation',json('false'))),
   'payload', json_object('taskID','qa-task-2','allowsDismissal','true'),
   'presentedAt', json('null'), 'resolvedAt', json('null')
 ), strftime('%Y-%m-%dT%H:%M:%SZ','now','+1 second'), strftime('%Y-%m-%dT%H:%M:%SZ','now','+30 minutes'), NULL, NULL
);
COMMIT;
SQL
    assert_ready "$database"
}

assert_ready() {
    local database="$1"
    require_database "$database"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id IN ('$PRIMARY_ID','$SECONDARY_ID') AND state IN ('detected','queued','presented');" 2 "two unresolved coaching prompts"
    assert_scalar "$database" "SELECT json_array_length(payload_json,'$.actions') FROM prompt_episodes WHERE id='$PRIMARY_ID';" 6 "primary coaching action count"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes,json_each(payload_json,'$.actions') WHERE prompt_episodes.id='$PRIMARY_ID' AND json_extract(value,'$.requiresConfirmation')=1;" 2 "destructive confirmation count"
    assert_scalar "$database" "SELECT json_extract(payload_json,'$.payload.privateEvidence') FROM prompt_episodes WHERE id='$PRIMARY_ID';" "$PRIVATE_VALUE" "private payload sentinel"
    print -- "PASS: deterministic coaching prompts are ready"
}

assert_dismissed() {
    local database="$1"
    require_database "$database"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id='$PRIMARY_ID' AND state='dismissed' AND resolution_origin='user';" 1 "keyboard dismissal state"
    assert_scalar "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE id='$SECONDARY_ID' AND state IN ('detected','queued','presented');" 1 "secondary prompt remains untouched"
    print -- "PASS: keyboard dismissal affected only the primary prompt"
}

expect_failure() {
    local needle="$1" output exit_code
    shift
    set +e
    output="$("$@" 2>&1)"
    exit_code=$?
    set -e
    (( exit_code != 0 )) || fail "negative self-test false-passed: $needle"
    print -r -- "$output" | grep -Fq "$needle" || fail "negative self-test failed for the wrong reason: $needle"
}

self_test() {
    local root database backup original_hash
    root="$(mktemp -d "${TMPDIR:-/tmp}/zc055004-fixture.XXXXXX")"
    trap "rm -rf ${(q)root}" EXIT
    database="$root/qa.sqlite3"
    backup="$root/original.sqlite3"
    sqlite3 "$database" <<'SQL'
CREATE TABLE prompt_episodes(
 id TEXT PRIMARY KEY, decision_key TEXT NOT NULL, prompt_type TEXT NOT NULL, state TEXT NOT NULL,
 title TEXT NOT NULL, summary TEXT NOT NULL, action_token TEXT NOT NULL, payload_json TEXT NOT NULL,
 created_at_utc TEXT NOT NULL, expires_at_utc TEXT, resolution_origin TEXT, resolution_reason TEXT
);
INSERT INTO prompt_episodes VALUES('original','original','SOURCE','dismissed','Original','Original','token','{}','2026-07-15T00:00:00Z',NULL,NULL,NULL);
SQL
    original_hash="$(shasum -a 256 "$database" | awk '{print $1}')"
    expect_failure "two unresolved coaching prompts" assert_ready "$database"
    expect_failure "SQL failed for deliberate broken SQL" scalar "$database" 'SELECT * FROM missing_table;' "deliberate broken SQL"
    snapshot "$database" "$backup"
    seed "$database"
    expect_failure "keyboard dismissal state" assert_dismissed "$database"
    sqlite3 "$database" "UPDATE prompt_episodes SET decision_key='resolved:'||id||':'||decision_key,state='dismissed',resolution_origin='user',resolution_reason='explicit_dismissal' WHERE id='$PRIMARY_ID';"
    assert_dismissed "$database"
    restore "$database" "$backup"
    [[ "$(shasum -a 256 "$database" | awk '{print $1}')" == "$original_hash" ]] || fail "self-test restore comparison failed"
    print -- "PASS: ZC-055-004 fixture self-test"
}

command -v sqlite3 >/dev/null || fail "sqlite3 is required"
COMMAND="${1:-}"
case "$COMMAND" in
    self-test) (( $# == 1 )) || usage; self_test ;;
    snapshot|restore) (( $# == 3 )) || usage; "$COMMAND" "$2" "$3" ;;
    seed) (( $# == 2 )) || usage; seed "$2" ;;
    assert-ready) (( $# == 2 )) || usage; assert_ready "$2" ;;
    assert-dismissed) (( $# == 2 )) || usage; assert_dismissed "$2" ;;
    *) usage ;;
esac
