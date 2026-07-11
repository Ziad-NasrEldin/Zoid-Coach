#!/bin/zsh

set -euo pipefail

USER_DOMAIN="gui/$(id -u)"

ensure_launch_agent() {
    local label="$1"
    local plist="$2"

    [[ -f "$plist" ]] || {
        echo "Missing required launch agent: $plist" >&2
        exit 1
    }
    launchctl enable "$USER_DOMAIN/$label"
    if ! launchctl print "$USER_DOMAIN/$label" >/dev/null 2>&1; then
        launchctl bootstrap "$USER_DOMAIN" "$plist"
    fi
    launchctl kickstart "$USER_DOMAIN/$label"
}

ensure_launch_agent "com.screenwatch" "$HOME/Library/LaunchAgents/com.screenwatch.plist"
ensure_launch_agent "com.screenwatch.timer" "$HOME/Library/LaunchAgents/com.screenwatch.timer.plist"

echo "Screenwatch launch agents are enabled and loaded"
