#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly DATABASE="${2:-}"
readonly LOCAL_DAY="${ZOID_COACH_QA_DRIFT_LOCAL_DAY:-$(date '+%F')}"
readonly NOW_EPOCH="${ZOID_COACH_QA_DRIFT_NOW_EPOCH:-$(date '+%s')}"
readonly PROMPT_TYPE="GAMING_DRIFT"
readonly PRIVATE_PREFIX="qa-drift-private-sentinel"
readonly PRIVATE_URL_PREFIX="https://private.invalid/qa-drift"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <prepare|assert-prepared|advance-ambiguous|advance-recovery|assert-recovery|cleanup> <database>"
    exit 2
}

[[ -n "$COMMAND" && -n "$DATABASE" ]] || usage
[[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
[[ "$LOCAL_DAY" == <->-<->-<-> ]] || fail "local day must use YYYY-MM-DD"
[[ "$NOW_EPOCH" == <-> ]] || fail "fixture now must be an epoch"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
command -v date >/dev/null 2>&1 || fail "date is required"

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

require_column() {
    local table="$1"
    local column="$2"
    assert_scalar \
        "SELECT COUNT(*) FROM pragma_table_info('$table') WHERE name = '$column';" \
        "1" \
        "$table.$column column"
}

validate_schema() {
    assert_scalar "PRAGMA user_version;" "46" "schema version"
    local table
    for table in behavior_records daily_review_corrections prompt_episodes; do
        assert_scalar \
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" \
            "1" \
            "$table table"
    done
    local column
    for column in source_day epoch time_label app_name window_title url has_screenshot screenshot_path ingested_at classification classification_policy_version; do
        require_column behavior_records "$column"
    done
    for column in source_day start_epoch end_epoch classification created_at_utc; do
        require_column daily_review_corrections "$column"
    done
    for column in id decision_key prompt_type state payload_json created_at_utc resolution_origin resolution_reason; do
        require_column prompt_episodes "$column"
    done
}

timestamp_for_epoch() {
    date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

owned_prompt_where() {
    print -r -- "prompt_type = '$PROMPT_TYPE' AND payload_json LIKE '%qa-drift-%' AND (decision_key LIKE 'gaming-drift:$LOCAL_DAY:%' OR decision_key LIKE 'resolved:%:gaming-drift:$LOCAL_DAY:%')"
}

assert_phase() {
    local phase="$1"
    local expected_count="$2"
    local classification="$3"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-$phase-game';" \
        "$expected_count" \
        "$phase evidence count"
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-$phase-game' AND classification = '$classification' AND window_title LIKE '$PRIVATE_PREFIX-$phase%' AND url LIKE '$PRIVATE_URL_PREFIX/$phase%' AND ingested_at GLOB '????-??-??T??:??:??Z';" \
        "$expected_count" \
        "$phase raw evidence unchanged"
    if [[ "$expected_count" == "10" ]]; then
        assert_scalar \
            "SELECT MAX(epoch) - MIN(epoch) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-$phase-game';" \
            "540" \
            "$phase ten-minute span"
    fi
}

insert_gaming_phase() {
    local phase="$1"
    local first_epoch="$2"
    local existing
    existing="$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-$phase-game';")"
    if [[ "$existing" != "0" ]]; then
        [[ "$existing" == "10" ]] || fail "$phase phase is partially seeded"
        return
    fi

    local values=""
    local index epoch timestamp separator
    for index in {0..9}; do
        epoch=$((first_epoch + index * 60))
        timestamp="$(timestamp_for_epoch "$epoch")"
        separator=","
        [[ "$index" == "9" ]] && separator=""
        values+="('$LOCAL_DAY',$epoch,'$(date -u -r "$epoch" '+%H:%M')','qa-drift-$phase-game','$PRIVATE_PREFIX-$phase-$index SECRET-QA-DRIFT-$phase-$index','$PRIVATE_URL_PREFIX/$phase/$index',0,NULL,'$timestamp','gaming',1)$separator"
    done

    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES $values;
COMMIT;
SQL
}

assert_prepared() {
    validate_schema
    assert_phase baseline 10 gaming
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name LIKE 'qa-drift-%';" \
        "10" \
        "prepared owned row count"
}

prepare() {
    validate_schema
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name LIKE 'qa-drift-%' AND app_name != 'qa-drift-baseline-game';" \
        "0" \
        "prepare phase collision"
    insert_gaming_phase baseline $((NOW_EPOCH - 600))
    assert_prepared
    print -- "PASS: seeded 10 fresh certain gaming minutes"
    print -- "HELPER CYCLE REQUIRED: call GamingDriftPromptService.produce with completed baseline, confidenceIsLimited=false, unlockedRemainingMinutes=0, coaching enabled, and an existing incomplete priority task."
    print -- "NOT SEEDED: baseline, allowance, policy, and priority-task gates are product/runtime-owned inputs, not fixture tables."
}

advance_ambiguous() {
    validate_schema
    assert_phase baseline 10 gaming
    local prompt_where
    prompt_where="$(owned_prompt_where)"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where AND state IN ('detected','queued','presented');" \
        "1" \
        "initial unresolved drift prompt after helper cycle"
    local existing
    existing="$(scalar "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-ambiguous-game';")"
    if [[ "$existing" == "0" ]]; then
        local latest ambiguous_epoch timestamp
        latest="$(scalar "SELECT MAX(epoch) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-baseline-game';")"
        ambiguous_epoch=$((NOW_EPOCH - 1))
        (( ambiguous_epoch > latest )) || ambiguous_epoch=$((latest + 1))
        timestamp="$(timestamp_for_epoch "$ambiguous_epoch")"
        sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES (
    '$LOCAL_DAY', $ambiguous_epoch, '$(date -u -r "$ambiguous_epoch" '+%H:%M')',
    'qa-drift-ambiguous-game', '$PRIVATE_PREFIX-ambiguous SECRET-QA-DRIFT-AMBIGUOUS',
    '$PRIVATE_URL_PREFIX/ambiguous', 0, NULL, '$timestamp', 'unknown', 1
);
COMMIT;
SQL
    else
        [[ "$existing" == "1" ]] || fail "ambiguous phase is duplicated"
    fi
    assert_phase ambiguous 1 unknown
    print -- "PASS: newest non-neutral Unknown evidence inserted"
    print -- "HELPER CYCLE REQUIRED: run produce once; it must withdraw the unresolved drift prompt with system/screenwatch_evidence_invalid."
    print -- "NON-DISPLAY EXPECTATION: UI must not expose '$PRIVATE_PREFIX', 'SECRET-QA-DRIFT-', or '$PRIVATE_URL_PREFIX'."
}

advance_recovery() {
    validate_schema
    assert_phase baseline 10 gaming
    assert_phase ambiguous 1 unknown
    local prompt_where
    prompt_where="$(owned_prompt_where)"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where AND state IN ('detected','queued','presented');" \
        "0" \
        "ambiguous evidence unresolved prompt withdrawal"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where AND state = 'dismissed' AND resolution_origin = 'system' AND resolution_reason = 'screenwatch_evidence_invalid';" \
        "1" \
        "ambiguous evidence system withdrawal reason"
    local ambiguous_epoch first_epoch
    ambiguous_epoch="$(scalar "SELECT epoch FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name = 'qa-drift-ambiguous-game' LIMIT 1;")"
    first_epoch=$((NOW_EPOCH - 541))
    (( first_epoch > ambiguous_epoch )) \
        || fail "recovery needs 10 fresh minutes after ambiguity; wait and rerun advance-recovery"
    insert_gaming_phase recovery "$first_epoch"
    assert_phase recovery 10 gaming
    print -- "PASS: seeded 10 fresh certain recovery minutes after verified ambiguity withdrawal"
    print -- "HELPER CYCLE REQUIRED: run produce twice. First must queue one prompt; second must suppress as sessionAlreadyHandled."
}

assert_recovery() {
    validate_schema
    assert_phase baseline 10 gaming
    assert_phase ambiguous 1 unknown
    assert_phase recovery 10 gaming
    local prompt_where
    prompt_where="$(owned_prompt_where)"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where AND state = 'dismissed' AND resolution_origin = 'system' AND resolution_reason = 'screenwatch_evidence_invalid';" \
        "1" \
        "preserved invalid-evidence withdrawal"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where AND state IN ('detected','queued','presented');" \
        "1" \
        "exactly one recovered unresolved prompt"
    assert_scalar \
        "SELECT COUNT(*) FROM prompt_episodes WHERE $prompt_where;" \
        "2" \
        "no duplicate prompt after repeated recovery cycle"
    print -- "PASS: ambiguity withdrawal and single-prompt recovery postconditions hold"
    print -- "NON-DISPLAY EXPECTATION: raw private evidence remains present in SQLite and forbidden in UI copy."
}

cleanup() {
    validate_schema
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records
WHERE source_day = '$LOCAL_DAY'
  AND app_name LIKE 'qa-drift-%';
COMMIT;
SQL
    assert_scalar \
        "SELECT COUNT(*) FROM behavior_records WHERE source_day = '$LOCAL_DAY' AND app_name LIKE 'qa-drift-%';" \
        "0" \
        "cleaned owned evidence rows"
    print -- "PASS: ambiguous drift evidence fixture cleaned"
    print -- "CLEANUP BOUNDARY: product-created prompts are postconditions, not qa-drift fixture rows; discard the caller-supplied isolated QA database after verification."
}

case "$COMMAND" in
    prepare) prepare ;;
    assert-prepared) assert_prepared; print -- "PASS: ambiguous drift baseline remains prepared" ;;
    advance-ambiguous) advance_ambiguous ;;
    advance-recovery) advance_recovery ;;
    assert-recovery) assert_recovery ;;
    cleanup) cleanup ;;
    *) usage ;;
esac
