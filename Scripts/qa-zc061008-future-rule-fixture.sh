#!/bin/zsh
set -euo pipefail

readonly SCRIPT_PATH="${0:A}"
readonly PREFIX="qa-zc061008"
readonly HISTORICAL_LABEL="$PREFIX-historical"
readonly FUTURE_LABEL="$PREFIX-future"
readonly CORRECTION_ID="$PREFIX-correction"
readonly PRIVATE_TITLE="$PREFIX-private-future-window"
readonly PRIVATE_URL="https://$PREFIX.private.invalid/token"

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
    [[ "$root" == /private/tmp/zoid-666-zc061008-* ]] \
        || fail "refusing non-ZC-061-008 isolated root: $root"
    [[ "$root" != /private/tmp && "$root" != / ]] || fail "refusing unsafe root: $root"
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
    [[ "$snapshot" == /private/tmp/zoid-666-zc061008-* ]] \
        || fail "snapshot must use the ZC-061-008 namespace"
    [[ ! -e "$snapshot" ]] || fail "snapshot already exists: $snapshot"
    /usr/bin/ditto "$qa_root" "$snapshot"
    print -r -- "$qa_root" > "$snapshot.zc061008-target"
    root_manifest "$snapshot" > "$snapshot.zc061008-manifest"
    [[ -s "$snapshot.zc061008-manifest" ]] || fail "snapshot manifest is empty"
    print -- "PASS: snapshotted isolated QA root"
}

restore_root() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    assert_safe_root "$qa_root"
    [[ -d "$snapshot" ]] || fail "snapshot does not exist: $snapshot"
    [[ -f "$snapshot.zc061008-target" ]] || fail "snapshot target marker is missing"
    [[ "$(<"$snapshot.zc061008-target")" == "$qa_root" ]] \
        || fail "snapshot target does not match the requested QA root"
    rm -rf -- "$qa_root"
    /usr/bin/ditto "$snapshot" "$qa_root"
    root_manifest "$qa_root" > "$snapshot.zc061008-restored-manifest"
    cmp -s "$snapshot.zc061008-manifest" "$snapshot.zc061008-restored-manifest" \
        || fail "restored QA root differs from the byte manifest"
    print -- "PASS: restored isolated QA root byte-for-byte"
}

assert_root_restored() {
    local qa_root="${1:A}"
    local snapshot="${2:A}"
    local current
    assert_safe_root "$qa_root"
    current="$(mktemp /private/tmp/zoid-666-zc061008-manifest.XXXXXX)"
    trap 'rm -f -- "$current"' EXIT
    root_manifest "$qa_root" > "$current"
    cmp -s "$snapshot.zc061008-manifest" "$current" \
        || fail "current QA root differs from the byte manifest"
    rm -f -- "$current"
    trap - EXIT
    print -- "PASS: isolated QA root matches the byte-exact baseline"
}

require_database() {
    [[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
    local table
    for table in behavior_records daily_review_corrections app_classification_correction_rules prompt_episodes; do
        assert_scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$table';" "1" "$table production table"
    done
}

clear_owned_state() {
    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
DELETE FROM app_classification_correction_rules
WHERE source_day = '$SOURCE_DAY'
  AND source_session_start_epoch IN (
      SELECT epoch FROM behavior_records WHERE time_label = '$HISTORICAL_LABEL'
  );
DELETE FROM daily_review_corrections WHERE id = '$CORRECTION_ID';
DELETE FROM behavior_records WHERE time_label LIKE '$PREFIX-%';
COMMIT;
SQL
    rm -f -- "$LOG_FILE"
}

active_rule_count_sql() {
    print -r -- "SELECT COUNT(*) FROM app_classification_correction_rules rule WHERE rule.normalized_app = 'safari' AND rule.state = 'active' AND NOT EXISTS (SELECT 1 FROM app_classification_correction_rules newer WHERE newer.normalized_app = rule.normalized_app AND (newer.effective_from_epoch > rule.effective_from_epoch OR (newer.effective_from_epoch = rule.effective_from_epoch AND newer.id > rule.id)));"
}

prepare_phase() {
    local phase="$1"
    case "$phase" in
        qualifying|pre-effective|nonmatching|removed-rule) ;;
        *) fail "unsupported fixture phase: $phase" ;;
    esac
    require_database
    mkdir -p "$DAY_DIRECTORY"
    clear_owned_state
    assert_scalar "$(active_rule_count_sql)" "0" "no foreign active Safari rule"

    local observation_epoch="$FUTURE_EPOCH"
    local application="Safari"
    if [[ "$phase" == "pre-effective" ]]; then observation_epoch=$((RULE_EFFECTIVE_EPOCH - 60)); fi
    if [[ "$phase" == "nonmatching" ]]; then application="Unmapped Browser"; fi

    sqlite3 -batch "$DATABASE" <<SQL
BEGIN IMMEDIATE;
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES (
    '$SOURCE_DAY', $HISTORICAL_EPOCH, '$HISTORICAL_LABEL', 'Safari', '', '',
    0, NULL, '$TIMESTAMP', 'unknown', 1
);
INSERT INTO daily_review_corrections(
    id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc
) VALUES (
    '$CORRECTION_ID', '$SOURCE_DAY', $HISTORICAL_EPOCH,
    $((HISTORICAL_EPOCH + 60)), 'work', NULL, '$TIMESTAMP'
);
INSERT INTO app_classification_correction_rules(
    normalized_app, display_app, classification, state, source_day,
    source_session_start_epoch, effective_from_epoch, created_at_utc
) VALUES (
    'safari', 'Safari', 'work', 'active', '$SOURCE_DAY',
    $HISTORICAL_EPOCH, $RULE_EFFECTIVE_EPOCH, '$TIMESTAMP'
);
COMMIT;
SQL
    if [[ "$phase" == "removed-rule" ]]; then
        sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO app_classification_correction_rules(
    normalized_app, display_app, classification, state, source_day,
    source_session_start_epoch, effective_from_epoch, created_at_utc
) VALUES (
    'safari', 'Safari', NULL, 'removed', NULL, NULL,
    $((FUTURE_EPOCH - 30)), '$TIMESTAMP'
);
SQL
    fi
    print -r -- "{\"t\":\"$FUTURE_LABEL\",\"epoch\":$observation_epoch,\"app\":\"$application\",\"window\":\"$PRIVATE_TITLE\",\"url\":\"$PRIVATE_URL\",\"img\":false}" > "$LOG_FILE"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label = '$HISTORICAL_LABEL' AND app_name = 'Safari' AND classification = 'unknown';" "1" "historical raw Unknown"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id = '$CORRECTION_ID' AND classification = 'work' AND start_epoch = $HISTORICAL_EPOCH AND end_epoch = $((HISTORICAL_EPOCH + 60));" "1" "historical Work correction"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE lower(COALESCE(classification, '')) = 'research';" "0" "no Research invention"
    print -- "OBSERVATION_EPOCH=$observation_epoch"
    print -- "PASS: prepared $phase future-rule fixture"
}

assert_result() {
    local phase="$1"
    require_database
    local historical_epoch
    historical_epoch="$(scalar "SELECT epoch FROM behavior_records WHERE time_label = '$HISTORICAL_LABEL';")"
    [[ "$historical_epoch" == <-> ]] || fail "historical fixture epoch is missing or ambiguous"
    local expected="unknown"
    [[ "$phase" == "qualifying" ]] && expected="work"
    local expected_rule_count=1
    [[ "$phase" == "removed-rule" ]] && expected_rule_count=0
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label = '$FUTURE_LABEL';" "1" "exactly one ingested future row"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label LIKE '$FUTURE_LABEL%';" "1" "no duplicate future ingestion"
    assert_scalar "SELECT classification FROM behavior_records WHERE time_label = '$FUTURE_LABEL';" "$expected" "$phase future classification"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE time_label = '$HISTORICAL_LABEL' AND classification = 'unknown';" "1" "historical raw Unknown preserved"
    assert_scalar "SELECT COUNT(*) FROM daily_review_corrections WHERE id = '$CORRECTION_ID' AND classification = 'work' AND start_epoch = $historical_epoch AND end_epoch = $((historical_epoch + 60));" "1" "historical correction preserved"
    assert_scalar "$(active_rule_count_sql)" "$expected_rule_count" "singular active rule boundary"
    assert_scalar "SELECT COUNT(*) FROM behavior_records WHERE lower(COALESCE(classification, '')) = 'research';" "0" "no Research classification"
    assert_scalar "SELECT COUNT(*) FROM prompt_episodes WHERE title LIKE '%$PRIVATE_TITLE%' OR summary LIKE '%$PRIVATE_TITLE%' OR payload_json LIKE '%$PRIVATE_TITLE%' OR title LIKE '%$PRIVATE_URL%' OR summary LIKE '%$PRIVATE_URL%' OR payload_json LIKE '%$PRIVATE_URL%';" "0" "private evidence excluded from prompts"
    print -- "PASS: $phase future-rule result is exact, idempotent, private, and correction-safe"
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "validator accepted $label"; fi
}

self_test() (
    local root qa_root snapshot database screenwatch_root day_directory log_file
    root="$(mktemp -d /private/tmp/zoid-666-zc061008-self-test.XXXXXX)"
    qa_root="$root-runtime"
    snapshot="$root-snapshot"
    database="$qa_root/Application Support/Zoid 666/zoid-coach.sqlite"
    screenwatch_root="$qa_root/Screenwatch/days"
    day_directory="$screenwatch_root/$(date '+%Y-%m-%d')"
    log_file="$day_directory/log.jsonl"
    mkdir -p "${database:h}" "$day_directory"
    trap 'rm -rf -- "$root" "$qa_root" "$snapshot" "$snapshot.zc061008-target" "$snapshot.zc061008-manifest" "$snapshot.zc061008-restored-manifest"' EXIT
    sqlite3 -batch "$database" <<'SQL'
CREATE TABLE behavior_records(source_day TEXT NOT NULL, epoch INTEGER NOT NULL, time_label TEXT NOT NULL, app_name TEXT NOT NULL, window_title TEXT NOT NULL, url TEXT NOT NULL, has_screenshot INTEGER NOT NULL, screenshot_path TEXT, ingested_at TEXT NOT NULL, classification TEXT, classification_policy_version INTEGER, PRIMARY KEY(source_day, epoch));
CREATE TABLE daily_review_corrections(id TEXT PRIMARY KEY, source_day TEXT NOT NULL, start_epoch INTEGER NOT NULL, end_epoch INTEGER NOT NULL, classification TEXT NOT NULL, task_id TEXT, created_at_utc TEXT NOT NULL);
CREATE TABLE app_classification_correction_rules(id INTEGER PRIMARY KEY AUTOINCREMENT, normalized_app TEXT NOT NULL, display_app TEXT NOT NULL, classification TEXT, state TEXT NOT NULL, source_day TEXT, source_session_start_epoch INTEGER, effective_from_epoch INTEGER NOT NULL, created_at_utc TEXT NOT NULL);
CREATE TABLE prompt_episodes(id TEXT PRIMARY KEY, title TEXT NOT NULL, summary TEXT NOT NULL, payload_json TEXT NOT NULL);
CREATE TABLE foreign_state(id TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO foreign_state VALUES('preserve', 'exact');
SQL
    "$SCRIPT_PATH" snapshot-root "$qa_root" "$snapshot" >/dev/null

    local phase expected observation_epoch
    for phase in qualifying pre-effective nonmatching removed-rule; do
        "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
        observation_epoch="$("$SCRIPT_PATH" prepare "$phase" "$database" "$screenwatch_root" | sed -n 's/^OBSERVATION_EPOCH=//p')"
        expected="unknown"
        [[ "$phase" == "qualifying" ]] && expected="work"
        sqlite3 -batch "$database" <<SQL
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES (
    '$(date '+%Y-%m-%d')', $observation_epoch, '$FUTURE_LABEL',
    '$([[ "$phase" == "nonmatching" ]] && print "Unmapped Browser" || print Safari)',
    '$PRIVATE_TITLE', '$PRIVATE_URL', 0, NULL, '$(date -u '+%Y-%m-%dT%H:%M:%SZ')', '$expected', 1
);
SQL
        "$SCRIPT_PATH" assert-result "$phase" "$database" "$screenwatch_root" >/dev/null
    done

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    observation_epoch="$("$SCRIPT_PATH" prepare qualifying "$database" "$screenwatch_root" | sed -n 's/^OBSERVATION_EPOCH=//p')"
    sqlite3 "$database" "INSERT INTO behavior_records VALUES('$(date '+%Y-%m-%d')',$observation_epoch,'$FUTURE_LABEL','Safari','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'2026-07-15T00:00:00Z','work',1);"
    sqlite3 "$database" "INSERT INTO behavior_records VALUES('$(date '+%Y-%m-%d')',$((observation_epoch + 1)),'$FUTURE_LABEL-duplicate','Safari','$PRIVATE_TITLE','$PRIVATE_URL',0,NULL,'2026-07-15T00:00:00Z','work',1);"
    expect_failure "duplicate future ingestion" "$SCRIPT_PATH" assert-result qualifying "$database" "$screenwatch_root"
    sqlite3 "$database" "DELETE FROM behavior_records WHERE time_label = '$FUTURE_LABEL-duplicate'; INSERT INTO prompt_episodes VALUES('$PREFIX-private-prompt','$PRIVATE_TITLE','safe','{}');"
    expect_failure "privacy leakage" "$SCRIPT_PATH" assert-result qualifying "$database" "$screenwatch_root"
    sqlite3 "$database" "DELETE FROM prompt_episodes; DROP TABLE behavior_records;"
    expect_failure "SQL/schema failure" "$SCRIPT_PATH" assert-result qualifying "$database" "$screenwatch_root"

    "$SCRIPT_PATH" restore-root "$qa_root" "$snapshot" >/dev/null
    "$SCRIPT_PATH" assert-root-restored "$qa_root" "$snapshot" >/dev/null
    [[ "$(sqlite3 "$database" "SELECT value FROM foreign_state WHERE id = 'preserve';")" == "exact" ]] \
        || fail "foreign state was not restored"
    print -- "PASS: ZC-061-008 fixture self-test covers rule boundaries, duplicate, SQL, privacy, and byte restoration"
)

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"
readonly COMMAND="${1:-}"
shift || true
case "$COMMAND" in
    snapshot-root|restore-root|assert-root-restored)
        (( $# == 2 )) || usage
        "${COMMAND//-/_}" "$1" "$2"
        ;;
    prepare|assert-result)
        (( $# == 3 )) || usage
        readonly PHASE="$1"
        readonly DATABASE="${2:A}"
        readonly SCREENWATCH_ROOT="${3:A}"
        readonly SOURCE_DAY="$(date '+%Y-%m-%d')"
        readonly DAY_DIRECTORY="$SCREENWATCH_ROOT/$SOURCE_DAY"
        readonly LOG_FILE="$DAY_DIRECTORY/log.jsonl"
        readonly NOW_EPOCH="$(date '+%s')"
        readonly HISTORICAL_EPOCH=$((NOW_EPOCH - 3600))
        readonly RULE_EFFECTIVE_EPOCH=$((NOW_EPOCH - 1800))
        readonly FUTURE_EPOCH=$((NOW_EPOCH - 30))
        readonly TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        if [[ "$COMMAND" == "prepare" ]]; then prepare_phase "$PHASE"; else assert_result "$PHASE"; fi
        ;;
    self-test)
        (( $# == 0 )) || usage
        self_test
        ;;
    *) usage ;;
esac
