#!/bin/zsh

set -euo pipefail

USER_DOMAIN="gui/$(id -u)"
DATABASE="$HOME/Library/Application Support/Zoid 666/zoid-coach.sqlite"
SCREENWATCH_LOG="$HOME/screenwatch/days/$(date +%F)/log.jsonl"
INSTALLED_APP="${ZOID_COACH_INSTALL_ROOT:-$HOME/Applications}/Zoid 666.app"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_launch_agent() {
    local label="$1"
    local plist="$2"

    [[ -f "$plist" ]] || fail "$label plist is missing"
    [[ "$(plutil -extract RunAtLoad raw -o - "$plist")" == "true" ]] || fail "$label is not RunAtLoad"
    [[ "$(plutil -extract KeepAlive raw -o - "$plist")" == "true" ]] || fail "$label is not KeepAlive"
    local service
    service="$(launchctl print "$USER_DOMAIN/$label" 2>/dev/null)" || fail "$label is not loaded"
    grep -q "state = running" <<<"$service" || fail "$label is not running"
}

assert_launch_agent \
    "com.screenwatch" \
    "$HOME/Library/LaunchAgents/com.screenwatch.plist"
assert_launch_agent \
    "com.screenwatch.timer" \
    "$HOME/Library/LaunchAgents/com.screenwatch.timer.plist"

zoid_service="$(launchctl print "$USER_DOMAIN/com.ziadnasreldin.ZoidCoach.agent" 2>/dev/null)" \
    || fail "Zoid 666 agent is not registered"
grep -q "state = running" <<<"$zoid_service" || fail "Zoid 666 agent is not running"

if [[ -d "$INSTALLED_APP" ]]; then
    "${0:A:h}/verify-package.sh" "$INSTALLED_APP"
    agent_pid="$(awk '/pid =/{print $3; exit}' <<<"$zoid_service")"
    agent_executable="$(lsof -Fn -a -p "$agent_pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep 'ZoidCoachAgent$')"
    [[ "$agent_executable" == "$INSTALLED_APP/Contents/MacOS/ZoidCoachAgent" ]] \
        || fail "Zoid 666 agent is not running from the permanent installed app"
fi

[[ -f "$SCREENWATCH_LOG" ]] || fail "today's Screenwatch log is missing"
[[ -f "$DATABASE" ]] || fail "Zoid 666 database is missing"

now_epoch="$(date +%s)"
screenwatch_modified="$(stat -f %m "$SCREENWATCH_LOG")"
(( now_epoch - screenwatch_modified <= 240 )) || fail "Screenwatch has not written within the wake grace period"

latest_screenwatch_epoch="$(tail -1 "$SCREENWATCH_LOG" | sed -E 's/.*"epoch": ([0-9]+).*/\1/')"
latest_source_epoch="$(sqlite3 "$DATABASE" "SELECT COALESCE(MAX(epoch), 0) FROM behavior_records WHERE source_day = '$(date +%F)';")"
(( latest_screenwatch_epoch - latest_source_epoch <= 240 )) \
    || fail "Zoid 666 ingestion is behind the latest Screenwatch record"

heartbeat="$(sqlite3 "$DATABASE" "SELECT last_success_at_utc FROM processing_checkpoints WHERE source_id = 'agent-runtime';")"
[[ -n "$heartbeat" ]] || fail "Zoid 666 agent heartbeat is missing"
heartbeat_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$heartbeat" +%s 2>/dev/null)" \
    || fail "Zoid 666 agent heartbeat is invalid"
(( now_epoch - heartbeat_epoch <= 240 )) || fail "Zoid 666 agent heartbeat is stale"

echo "PASS: Screenwatch and Zoid 666 are loaded, running, and fresh"
