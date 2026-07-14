#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly FIXTURE="$SCRIPT_DIR/qa-ambiguous-drift-fixture.sh"
readonly TEMP_ROOT="$(mktemp -d /private/tmp/zoid-666-ambiguous-drift-fixture.XXXXXX)"
readonly DATABASE="$TEMP_ROOT/zoid-coach.sqlite"

cleanup() { rm -rf "$TEMP_ROOT"; }
trap cleanup EXIT
fail() { print -u2 -- "FAIL: $*"; exit 1; }

[[ -x "$FIXTURE" ]] || fail "fixture script is not executable"
command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 is required"

sqlite3 -batch "$DATABASE" <<'SQL'
PRAGMA user_version = 46;
CREATE TABLE behavior_records (
    source_day TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    time_label TEXT NOT NULL,
    app_name TEXT NOT NULL,
    window_title TEXT NOT NULL,
    url TEXT NOT NULL,
    has_screenshot INTEGER NOT NULL,
    screenshot_path TEXT,
    ingested_at TEXT NOT NULL,
    classification TEXT,
    classification_policy_version INTEGER,
    PRIMARY KEY(source_day, epoch)
);
CREATE TABLE daily_review_corrections (
    id TEXT PRIMARY KEY,
    source_day TEXT NOT NULL,
    start_epoch INTEGER NOT NULL,
    end_epoch INTEGER NOT NULL,
    classification TEXT NOT NULL,
    task_id TEXT,
    created_at_utc TEXT NOT NULL
);
CREATE TABLE prompt_episodes (
    id TEXT PRIMARY KEY,
    decision_key TEXT NOT NULL UNIQUE,
    prompt_type TEXT NOT NULL,
    state TEXT NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    action_token TEXT NOT NULL UNIQUE,
    payload_json TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    expires_at_utc TEXT,
    resolution_origin TEXT,
    resolution_reason TEXT
);
INSERT INTO behavior_records(
    source_day, epoch, time_label, app_name, window_title, url,
    has_screenshot, screenshot_path, ingested_at, classification,
    classification_policy_version
) VALUES (
    '2033-05-17', 2000000000, '00:00', 'foreign-app', 'foreign-title', '',
    0, NULL, '2033-05-17T00:00:00Z', 'work', 1
);
SQL

export ZOID_COACH_QA_DRIFT_LOCAL_DAY=2033-05-18
export ZOID_COACH_QA_DRIFT_NOW_EPOCH=2000100000

"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"

baseline_epoch="$(sqlite3 -batch -noheader "$DATABASE" "SELECT MIN(epoch) FROM behavior_records WHERE app_name = 'qa-drift-baseline-game';")"
sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc, resolution_origin, resolution_reason
) VALUES (
    'qa-drift-simulated-initial', 'gaming-drift:2033-05-18:$baseline_epoch',
    'GAMING_DRIFT', 'queued', 'Initial', 'Initial', 'qa-drift-token-initial',
    '{"payload":{"application":"qa-drift-baseline-game"}}',
    '2033-05-18T03:20:00Z', NULL, NULL, NULL
);
SQL

export ZOID_COACH_QA_DRIFT_NOW_EPOCH=2000100060
"$FIXTURE" advance-ambiguous "$DATABASE"
"$FIXTURE" advance-ambiguous "$DATABASE"

sqlite3 -batch "$DATABASE" <<'SQL'
UPDATE prompt_episodes
SET decision_key = 'resolved:qa-drift-simulated-initial:' || decision_key,
    state = 'dismissed',
    resolution_origin = 'system',
    resolution_reason = 'screenwatch_evidence_invalid'
WHERE id = 'qa-drift-simulated-initial';
SQL

export ZOID_COACH_QA_DRIFT_NOW_EPOCH=2000100720
"$FIXTURE" advance-recovery "$DATABASE"
"$FIXTURE" advance-recovery "$DATABASE"

recovery_epoch="$(sqlite3 -batch -noheader "$DATABASE" "SELECT MIN(epoch) FROM behavior_records WHERE app_name = 'qa-drift-recovery-game';")"
sqlite3 -batch "$DATABASE" <<SQL
INSERT INTO prompt_episodes(
    id, decision_key, prompt_type, state, title, summary, action_token,
    payload_json, created_at_utc, expires_at_utc, resolution_origin, resolution_reason
) VALUES (
    'qa-drift-simulated-recovery', 'gaming-drift:2033-05-18:$recovery_epoch',
    'GAMING_DRIFT', 'queued', 'Recovered', 'Recovered', 'qa-drift-token-recovery',
    '{"payload":{"application":"qa-drift-recovery-game"}}',
    '2033-05-18T03:32:00Z', NULL, NULL, NULL
);
SQL

"$FIXTURE" assert-recovery "$DATABASE"
"$FIXTURE" assert-recovery "$DATABASE"

[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM behavior_records WHERE app_name = 'foreign-app';")" == "1" ]] \
    || fail "fixture changed foreign evidence"

"$FIXTURE" cleanup "$DATABASE"
"$FIXTURE" cleanup "$DATABASE"

[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM behavior_records;")" == "1" ]] \
    || fail "cleanup removed foreign evidence"
[[ "$(sqlite3 -batch -noheader "$DATABASE" "SELECT COUNT(*) FROM prompt_episodes;")" == "2" ]] \
    || fail "cleanup crossed product prompt ownership boundary"

grep -Fq "HELPER CYCLE REQUIRED" "$FIXTURE" \
    || fail "required product cycle is not documented"
grep -Fq "NOT SEEDED: baseline, allowance, policy, and priority-task gates" "$FIXTURE" \
    || fail "derived input boundary is not documented"
grep -Fq "NON-DISPLAY EXPECTATION" "$FIXTURE" \
    || fail "privacy boundary is not documented"

print -- "PASS: ambiguous drift evidence timeline, helper-cycle postconditions, idempotency, privacy, and cleanup are deterministic"
print -- "OWNED: 21 qa-drift behavior rows only"
print -- "POSTCONDITIONS: one system-invalid withdrawal, then one unresolved recovery prompt with no duplicate"
print -- "NOT SEEDED: derived baseline, allowance, policy, priority-task, or prompt state"
