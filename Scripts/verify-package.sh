#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
PACKAGE_MODE="${ZOID_COACH_PACKAGE_MODE:-production}"
APP_ROOT="${1:-${ZOID_COACH_APP_PATH:-$ROOT/.build/app/Zoid Coach.app}}"
if [[ $# -gt 0 ]]; then
    shift
fi
if [[ "${1:-}" == "--mode" ]]; then
    PACKAGE_MODE="${2:?missing package mode}"
    shift 2
fi
[[ "$PACKAGE_MODE" == "production" || "$PACKAGE_MODE" == "qa" ]] || {
    echo "FAIL: package mode must be production or qa" >&2
    exit 1
}
IDENTITIES="$ROOT/App/PackageIdentities.plist"
identity_value() {
    /usr/libexec/PlistBuddy -c "Print :$PACKAGE_MODE:$1" "$IDENTITIES"
}
CONTENTS="$APP_ROOT/Contents"
PLIST="$CONTENTS/Info.plist"
APP_BUNDLE_IDENTIFIER="$(identity_value appBundleIdentifier)"
APP_SIGNING_IDENTIFIER="$(identity_value appSigningIdentifier)"
APP_EXECUTABLE_NAME="$(identity_value appExecutableName)"
AGENT_SIGNING_IDENTIFIER="$(identity_value agentSigningIdentifier)"
AGENT_EXECUTABLE_NAME="$(identity_value agentExecutableName)"
LAUNCH_AGENT_LABEL="$(identity_value launchAgentLabel)"
LAUNCH_AGENT_PLIST_NAME="$(identity_value launchAgentPlistName)"
MACH_SERVICE_NAME="$(identity_value machServiceName)"
AGENT_PLIST="$CONTENTS/Library/LaunchAgents/$LAUNCH_AGENT_PLIST_NAME"
APP_EXECUTABLE="$CONTENTS/MacOS/$APP_EXECUTABLE_NAME"
AGENT_EXECUTABLE="$CONTENTS/MacOS/$AGENT_EXECUTABLE_NAME"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

[[ -d "$APP_ROOT" ]] || fail "app bundle is missing: $APP_ROOT"
[[ -x "$APP_EXECUTABLE" ]] || fail "main executable is missing or not executable"
[[ -x "$AGENT_EXECUTABLE" ]] || fail "agent executable is missing or not executable"
plutil -lint "$PLIST" "$AGENT_PLIST" >/dev/null

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" == "$APP_BUNDLE_IDENTIFIER" ]] \
    || fail "unexpected app bundle identifier"
"$ROOT/Scripts/verify-build-identity.sh" "$PLIST" "$@" >/dev/null
[[ "$(plutil -extract Label raw -o - "$AGENT_PLIST")" == "$LAUNCH_AGENT_LABEL" ]] \
    || fail "unexpected LaunchAgent label"
[[ "$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")" == "Contents/MacOS/$AGENT_EXECUTABLE_NAME" ]] \
    || fail "LaunchAgent BundleProgram does not point to the bundled helper"
[[ "$(/usr/libexec/PlistBuddy -c "Print :MachServices:$MACH_SERVICE_NAME" "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent Mach service is missing"
[[ "$(plutil -extract RunAtLoad raw -o - "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent must run at login"
[[ "$(plutil -extract KeepAlive raw -o - "$AGENT_PLIST")" == "true" ]] \
    || fail "LaunchAgent must recover after an unexpected exit"
[[ "$(plutil -extract ThrottleInterval raw -o - "$AGENT_PLIST")" -ge 10 ]] \
    || fail "LaunchAgent must throttle repeated crashes"

codesign --verify --deep --strict --verbose=2 "$APP_ROOT" >/dev/null
bundle_identifier="$(codesign -d --verbose=4 "$APP_ROOT" 2>&1 | sed -n 's/^Identifier=//p')"
app_identifier="$(codesign -d --verbose=4 "$APP_EXECUTABLE" 2>&1 | sed -n 's/^Identifier=//p')"
agent_identifier="$(codesign -d --verbose=4 "$AGENT_EXECUTABLE" 2>&1 | sed -n 's/^Identifier=//p')"
[[ "$bundle_identifier" == "$APP_BUNDLE_IDENTIFIER" ]] || fail "unexpected signed bundle identifier: $bundle_identifier"
[[ "$app_identifier" == "$APP_SIGNING_IDENTIFIER" ]] || fail "unexpected signed app identifier: $app_identifier"
[[ "$agent_identifier" == "$AGENT_SIGNING_IDENTIFIER" ]] || fail "unexpected signed agent identifier: $agent_identifier"

app_team="$(codesign -d --verbose=4 "$APP_EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
agent_team="$(codesign -d --verbose=4 "$AGENT_EXECUTABLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$app_team" == "$agent_team" ]] || fail "app and helper were signed by different teams"

if [[ "$PACKAGE_MODE" == "qa" ]]; then
    [[ "$(plutil -extract ZoidCoachPackageMode raw -o - "$PLIST")" == "qa" ]] \
        || fail "QA package mode stamp is missing"
    qa_run_root="$(plutil -extract ZoidCoachQARunRoot raw -o - "$PLIST")"
    [[ "$qa_run_root" == /* ]] || fail "QA run root must be absolute"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")" == "$qa_run_root" ]] \
        || fail "QA app and LaunchAgent runtime roots disagree"
    qa_identity_output="$(plutil -convert xml1 -o - "$PLIST"; plutil -convert xml1 -o - "$AGENT_PLIST")"
    [[ "$qa_identity_output" != *"com.ziadnasreldin.ZoidCoach"* ]] \
        || fail "QA package output contains a production identity string"
fi

echo "PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent"
