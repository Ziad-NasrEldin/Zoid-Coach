#!/bin/bash
set -euo pipefail

root="$(mktemp -d "${TMPDIR:-/tmp}/zoid-gaming-adjustment-verifier.XXXXXX")"
trap 'rm -rf "$root"' EXIT
database="$root/coach.sqlite"
qa_root="$root/qa"
fixture="$(cd "$(dirname "$0")" && pwd)/qa-gaming-manual-adjustment-verifier.sh"
mkdir -p "$qa_root/OS Fixtures" "$qa_root/QA Control"
printf '%s\n' '{"notifications":[]}' > "$qa_root/OS Fixtures/state.json"

local_day="$(date +%F)"
sqlite3 -batch "$database" <<SQL
CREATE TABLE behavior_records (
    source_day TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    time_label TEXT NOT NULL,
    app_name TEXT NOT NULL,
    window_title TEXT,
    url TEXT,
    has_screenshot INTEGER NOT NULL,
    screenshot_path TEXT,
    ingested_at TEXT NOT NULL,
    classification TEXT,
    classification_policy_version INTEGER
);
CREATE TABLE baseline_observation_days (
    local_day TEXT PRIMARY KEY,
    observed_minutes INTEGER NOT NULL,
    work_minutes INTEGER NOT NULL,
    gaming_minutes INTEGER NOT NULL,
    distracting_minutes INTEGER NOT NULL,
    unknown_minutes INTEGER NOT NULL,
    eligible_drift_count INTEGER NOT NULL,
    coverage TEXT NOT NULL,
    recorded_at_utc TEXT NOT NULL
);
CREATE TABLE gaming_manual_adjustments (
    request_id TEXT PRIMARY KEY,
    local_day TEXT NOT NULL,
    minutes INTEGER NOT NULL,
    note TEXT,
    recorded_at_utc TEXT NOT NULL
);
CREATE TABLE prompt_episodes (
    id TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL
);
CREATE TABLE notification_delivery_events (
    id INTEGER PRIMARY KEY,
    prompt_id TEXT NOT NULL
);
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    policy_version INTEGER NOT NULL,
    updated_at_utc TEXT NOT NULL
);
CREATE TABLE policy_versions (
    policy_type TEXT NOT NULL,
    version INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    is_active INTEGER NOT NULL,
    PRIMARY KEY(policy_type, version)
);
CREATE TABLE today_snapshots (
    day_key TEXT PRIMARY KEY,
    payload BLOB NOT NULL,
    updated_at TEXT NOT NULL
);
INSERT INTO today_snapshots(day_key, payload, updated_at)
VALUES ('$local_day', '{"localDate":"2026-07-14T12:00:00Z","timeZoneIdentifier":"Africa/Cairo"}', '2026-07-14T12:00:00Z');
INSERT INTO settings(key, value_json, policy_version, updated_at_utc)
VALUES ('user_policy', '{"schedule":{"timeZoneIdentifier":"Africa/Cairo"}}', 1, '2026-07-14T12:00:00Z');
INSERT INTO policy_versions(policy_type, version, payload_json, created_at_utc, is_active)
VALUES ('user', 1, '{"schedule":{"timeZoneIdentifier":"Africa/Cairo"}}', '2026-07-14T12:00:00Z', 1);
SQL

for offset in 1 2 3 4 5 6 7; do
    sqlite3 -batch "$database" "INSERT INTO baseline_observation_days VALUES ('2030-01-0$offset', 60, 45, 10, 0, 5, 0, 'complete', '2030-01-08T00:00:00Z');"
done

"$fixture" prepare-suppression "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM behavior_records WHERE app_name = 'qa-zc030011-game';")" == "10" ]]

sqlite3 -batch "$database" "INSERT INTO gaming_manual_adjustments VALUES ('gaming-adjustment-v1:qa', '$local_day', 15, 'qa-zc030011-manual-grant', '2026-07-14T12:00:00Z');"
"$fixture" verify-grant "$database" "$qa_root"
printf '%s\n' '{"outcome":"suppressed:gamingIsUnlocked","unlockedRemainingMinutes":15}' > "$qa_root/QA Control/gaming-drift-probe.json"
"$fixture" verify-probe "$database" "$qa_root"

original_settings_policy="$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")"
original_versioned_policy="$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")"
"$fixture" authoritative-next-day "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")" != "$original_settings_policy" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")" != "$original_versioned_policy" ]]
"$fixture" restore-policy "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")" == "$original_settings_policy" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")" == "$original_versioned_policy" ]]

"$fixture" authoritative-time-zone "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")" != "$original_settings_policy" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")" != "$original_versioned_policy" ]]
"$fixture" restore-policy "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")" == "$original_settings_policy" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")" == "$original_versioned_policy" ]]

sqlite3 -batch "$database" "ALTER TABLE settings RENAME COLUMN value_json TO val_json;"
"$fixture" authoritative-time-zone "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT val_json FROM settings WHERE key = 'user_policy';")" != "$original_settings_policy" ]]
"$fixture" restore-policy "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT val_json FROM settings WHERE key = 'user_policy';")" == "$original_settings_policy" ]]
sqlite3 -batch "$database" "ALTER TABLE settings RENAME COLUMN val_json TO value_json;"

"$fixture" ledger-unavailable "$database" "$qa_root"
[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'gaming_manual_adjustments';")" == "0" ]]
"$fixture" restore-ledger "$database" "$qa_root"
"$fixture" verify-zero-write "$database" "$qa_root"
"$fixture" cleanup "$database" "$qa_root"

[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM behavior_records;")" == "0" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT COUNT(*) FROM gaming_manual_adjustments;")" == "0" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT value_json FROM settings WHERE key = 'user_policy';")" == "$original_settings_policy" ]]
[[ "$(sqlite3 -batch -noheader "$database" "SELECT payload_json FROM policy_versions WHERE policy_type = 'user' AND version = 1;")" == "$original_versioned_policy" ]]
echo "PASS: gaming manual-adjustment verifier fixtures are deterministic, reversible, and ownership-bounded."
