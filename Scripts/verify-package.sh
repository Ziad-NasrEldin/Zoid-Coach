#!/bin/zsh

set -euo pipefail

APP_ROOT="${1:-${ZOID_COACH_APP_PATH:-${0:A:h:h}/.build/app/Zoid Coach.app}}"
CONTENTS="$APP_ROOT/Contents"
PLIST="$CONTENTS/Info.plist"
AGENT_PLIST="$CONTENTS/Library/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist"
APP_EXECUTABLE="$CONTENTS/MacOS/ZoidCoach"
AGENT_EXECUTABLE="$CONTENTS/MacOS/ZoidCoachAgent"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -d "$APP_ROOT" ]] || fail "app bundle is missing: $APP_ROOT"
[[ -x "$APP_EXECUTABLE" ]] || fail "main executable is missing or not executable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "agent executable is missing or not executable"
plutil -lint "$PLIST" "$AGENT_PLIST" >/dev/null

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" == "com.ziadnasreldin.ZoidCoach" ]] \
    || fail "unexpected app bundle identifier"
"${0:A:h}/verify-build-identity.sh" "$PLIST" "${@:2}" >/dev/null
[[ "$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")" == "Contents/MacOS/ZoidCoachAgent" ]] \
    || fail "LaunchAgent BundleProgram does not point to the bundled helper"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MachServices:com.ziadnasreldin.ZoidCoach.agent' "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent Mach service is missing"
[[ "$(plutil -extract RunAtLoad raw -o - "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent must run at login"
[[ "$(plutil -extract KeepAlive raw -o - "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent must recover after an unexpected exit"
[[ "$(plutil -extract ThrottleInterval raw -o - "$AGENT_PLIST")" -ge 10 ]] \
    || fail "LaunchAgent must throttle repeated crashes"

codesign --verify --deep --strict --verbose=2 "$APP_ROOT" >/dev/null
app_identifier="$(codesign -d --verbose=4 "$APP_EXECUTABLE" 2>&1 | sed -n 's/^Identifier=//p')"
agent_identifier="$(codesign -d --verbose=4 "$AGENT_EXECUTABLE" 2>&1 | sed -n 's/^Identifier=//p')"
[[ "$app_identifier" == "com.ziadnasreldin.ZoidCoach" ]] || fail "unexpected signed app identifier: $app_identifier"
[[ "$agent_identifier" == "com.ziadnasreldin.ZoidCoach.agent" ]] || fail "unexpected signed agent identifier: $agent_identifier"

app_team="$(codesign -d --verbose=4 "$APP_EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
agent_team="$(codesign -d --verbose=4 "$AGENT_EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$app_team" == "$agent_team" ]] || fail "app and helper were signed by different teams"

echo "PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent"
