#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <prepare-suppression|verify-grant|verify-probe|stale-day|changed-time-zone|restore-snapshot|ledger-unavailable|restore-ledger|verify-zero-write|cleanup> <database> <qa-run-root>" >&2
    exit 64
}

[[ $# -eq 3 ]] || usage
command_name="$1"
database="$2"
qa_root="$3"
[[ -f "$database" ]] || { echo "Database not found: $database" >&2; exit 66; }
[[ -d "$qa_root" ]] || { echo "QA run root not found: $qa_root" >&2; exit 66; }
command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 is required." >&2; exit 69; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 69; }

readonly token="qa-zc030011"
readonly app_name="$token-game"
readonly note="$token-manual-grant"
readonly control_root="$qa_root/QA Control"
readonly state_file="$control_root/gaming-manual-adjustment-verifier.json"
readonly probe_file="$control_root/gaming-drift-probe.json"
readonly os_state="$qa_root/OS Fixtures/state.json"
mkdir -p "$control_root"

scalar() { sqlite3 -batch -noheader "$database" "$1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
require_table() {
    [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '$1';")" == "1" ]] \
        || fail "required table is unavailable: $1"
}
sql_quote() { printf "%s" "$1" | sed "s/'/''/g"; }

validate_schema() {
    require_table behavior_records
    require_table baseline_observation_days
    require_table gaming_manual_adjustments
    require_table prompt_episodes
    require_table notification_delivery_events
    require_table today_snapshots
}

write_state() {
    local mode="$1"
    local ledger_count="$2"
    local ledger_sum="$3"
    MODE="$mode" LEDGER_COUNT="$ledger_count" LEDGER_SUM="$ledger_sum" STATE_FILE="$state_file" python3 - <<'PY'
import json, os
path = os.environ["STATE_FILE"]
state = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        state = json.load(handle)
state.update({
    "mode": os.environ["MODE"],
    "ledgerCount": int(os.environ["LEDGER_COUNT"]),
    "ledgerSum": int(os.environ["LEDGER_SUM"]),
})
with open(path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
PY
}

capture_ledger() {
    local mode="$1"
    write_state \
        "$mode" \
        "$(scalar "SELECT COUNT(*) FROM gaming_manual_adjustments;")" \
        "$(scalar "SELECT COALESCE(SUM(minutes), 0) FROM gaming_manual_adjustments;")"
}

mutate_snapshot() {
    local mode="$1"
    MODE="$mode" DATABASE="$database" STATE_FILE="$state_file" python3 - <<'PY'
import base64, datetime, json, os, sqlite3
db = sqlite3.connect(os.environ["DATABASE"])
row = db.execute("SELECT day_key, payload FROM today_snapshots ORDER BY updated_at DESC LIMIT 1").fetchone()
if row is None:
    raise SystemExit("No cached Today snapshot is available.")
day_key, payload = row
raw = payload.encode("utf-8") if isinstance(payload, str) else bytes(payload)
document = json.loads(raw)
state_path = os.environ["STATE_FILE"]
state = {}
if os.path.exists(state_path):
    with open(state_path, encoding="utf-8") as handle:
        state = json.load(handle)
state["snapshotDayKey"] = day_key
state["snapshotPayload"] = base64.b64encode(raw).decode("ascii")
state["snapshotMode"] = os.environ["MODE"]
if os.environ["MODE"] == "stale-day":
    value = document["localDate"]
    parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    document["localDate"] = (parsed - datetime.timedelta(days=1)).isoformat().replace("+00:00", "Z")
else:
    current = document["timeZoneIdentifier"]
    document["timeZoneIdentifier"] = "UTC" if current != "UTC" else "Africa/Cairo"
replacement = json.dumps(document, separators=(",", ":")).encode("utf-8")
db.execute("UPDATE today_snapshots SET payload = ? WHERE day_key = ?", (replacement, day_key))
db.commit()
with open(state_path, "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
PY
}

restore_snapshot() {
    DATABASE="$database" STATE_FILE="$state_file" python3 - <<'PY'
import base64, json, os, sqlite3
with open(os.environ["STATE_FILE"], encoding="utf-8") as handle:
    state = json.load(handle)
day_key = state.pop("snapshotDayKey", None)
payload = state.pop("snapshotPayload", None)
state.pop("snapshotMode", None)
if day_key is None or payload is None:
    raise SystemExit("No verifier snapshot backup is available.")
db = sqlite3.connect(os.environ["DATABASE"])
db.execute("UPDATE today_snapshots SET payload = ? WHERE day_key = ?", (base64.b64decode(payload), day_key))
db.commit()
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as handle:
    json.dump(state, handle, indent=2, sort_keys=True)
PY
}

verify_zero_write() {
    DATABASE="$database" STATE_FILE="$state_file" python3 - <<'PY'
import json, os, sqlite3
with open(os.environ["STATE_FILE"], encoding="utf-8") as handle:
    state = json.load(handle)
db = sqlite3.connect(os.environ["DATABASE"])
count, total = db.execute("SELECT COUNT(*), COALESCE(SUM(minutes), 0) FROM gaming_manual_adjustments").fetchone()
if count != state["ledgerCount"] or total != state["ledgerSum"]:
    raise SystemExit(f"Ledger changed: expected ({state['ledgerCount']}, {state['ledgerSum']}), got ({count}, {total}).")
print(f"PASS: {state['mode']} produced zero manual-ledger writes.")
PY
}

case "$command_name" in
    prepare-suppression)
        validate_schema
        [[ "$(scalar "SELECT COUNT(*) FROM baseline_observation_days WHERE coverage = 'complete';")" -ge 7 ]] \
            || fail "seven complete baseline days are required before the signed helper probe"
        local_day="$(date +%F)"
        now_epoch="$(date +%s)"
        sqlite3 -batch "$database" <<SQL
BEGIN IMMEDIATE;
DELETE FROM behavior_records WHERE source_day = '$local_day' AND app_name = '$app_name';
DELETE FROM gaming_manual_adjustments WHERE note = '$note';
DELETE FROM prompt_episodes WHERE payload_json LIKE '%$app_name%';
COMMIT;
SQL
        for offset in 10 9 8 7 6 5 4 3 2 1; do
            epoch="$((now_epoch - offset * 60))"
            sqlite3 -batch "$database" "INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification, classification_policy_version) VALUES ('$local_day', $epoch, 'qa', '$app_name', '', '', 0, NULL, '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'gaming', 1);"
        done
        rm -f "$probe_file"
        capture_ledger prepare-suppression
        echo "Prepared ten current gaming observations. Save a positive adjustment with note: $note"
        ;;
    verify-grant)
        validate_schema
        [[ "$(scalar "SELECT COUNT(*) FROM gaming_manual_adjustments WHERE note = '$note' AND minutes > 0;")" == "1" ]] \
            || fail "exactly one positive signed-app grant with the verifier note is required"
        [[ "$(scalar "SELECT COUNT(*) FROM behavior_records WHERE app_name = '$app_name' AND classification = 'gaming';")" == "10" ]] \
            || fail "raw verifier observations changed"
        echo "PASS: the signed-app manual grant is durable and raw observations remain intact."
        ;;
    verify-probe)
        [[ -f "$probe_file" ]] || fail "signed helper probe output is unavailable"
        PROBE_FILE="$probe_file" python3 - <<'PY'
import json, os
with open(os.environ["PROBE_FILE"], encoding="utf-8") as handle:
    result = json.load(handle)
if result.get("outcome") != "suppressed:gamingIsUnlocked":
    raise SystemExit(f"Unexpected helper result: {result.get('outcome')}")
if int(result.get("unlockedRemainingMinutes", 0)) <= 0:
    raise SystemExit("The helper did not observe the manually unlocked allowance.")
PY
        [[ "$(scalar "SELECT COUNT(*) FROM prompt_episodes WHERE payload_json LIKE '%$app_name%';")" == "0" ]] \
            || fail "the helper wrote a gaming-drift prompt"
        [[ "$(scalar "SELECT COUNT(*) FROM notification_delivery_events WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE payload_json LIKE '%$app_name%');")" == "0" ]] \
            || fail "the helper queued a gaming-drift notification"
        if [[ -f "$os_state" ]] && grep -Fq "$app_name" "$os_state"; then
            fail "the QA OS fixture contains a gaming-drift notification for verifier evidence"
        fi
        echo "PASS: the signed helper evaluated the production service and suppressed drift because gaming is unlocked."
        ;;
    stale-day|changed-time-zone)
        validate_schema
        capture_ledger "$command_name"
        mutate_snapshot "$command_name"
        echo "Prepared $command_name cached Today state. Keep the helper stopped until the adjustment form is open."
        ;;
    restore-snapshot)
        restore_snapshot
        echo "Restored the original cached Today snapshot."
        ;;
    ledger-unavailable)
        validate_schema
        capture_ledger ledger-unavailable
        sqlite3 -batch "$database" "ALTER TABLE gaming_manual_adjustments RENAME TO qa_zc030011_gaming_manual_adjustments;"
        echo "Prepared unavailable manual ledger. Launch the signed app with the helper stopped and inspect Today."
        ;;
    restore-ledger)
        [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'qa_zc030011_gaming_manual_adjustments';")" == "1" ]] \
            || fail "the verifier ledger backup is unavailable"
        sqlite3 -batch "$database" "ALTER TABLE qa_zc030011_gaming_manual_adjustments RENAME TO gaming_manual_adjustments;"
        echo "Restored the manual gaming ledger."
        ;;
    verify-zero-write)
        verify_zero_write
        ;;
    cleanup)
        local_day="$(date +%F)"
        if [[ "$(scalar "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'qa_zc030011_gaming_manual_adjustments';")" == "1" ]]; then
            sqlite3 -batch "$database" "ALTER TABLE qa_zc030011_gaming_manual_adjustments RENAME TO gaming_manual_adjustments;"
        fi
        if [[ -f "$state_file" ]] && python3 -c 'import json,sys; print(int("snapshotPayload" in json.load(open(sys.argv[1]))))' "$state_file" | grep -qx 1; then
            restore_snapshot
        fi
        sqlite3 -batch "$database" "DELETE FROM behavior_records WHERE source_day = '$local_day' AND app_name = '$app_name'; DELETE FROM gaming_manual_adjustments WHERE note = '$note'; DELETE FROM prompt_episodes WHERE payload_json LIKE '%$app_name%';"
        rm -f "$state_file" "$probe_file"
        echo "Removed verifier-owned gaming evidence and restored temporary schema changes."
        ;;
    *) usage ;;
esac
