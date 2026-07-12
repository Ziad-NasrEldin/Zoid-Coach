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
[[ "$(plutil -extract ZoidCoachPackageMode raw -o - "$PLIST")" == "$PACKAGE_MODE" ]] \
    || fail "package runtime mode stamp does not match verification mode"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_PACKAGE_MODE' "$PLIST")" == "$PACKAGE_MODE" ]] \
    || fail "app launch environment mode does not match package mode"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_PACKAGE_MODE' "$AGENT_PLIST")" == "$PACKAGE_MODE" ]] \
    || fail "LaunchAgent environment mode does not match package mode"
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
    qa_run_root="$(plutil -extract ZoidCoachQARunRoot raw -o - "$PLIST")"
    [[ "$qa_run_root" == /* ]] || fail "QA run root must be absolute"
    canonical_qa_run_root="$("$ROOT/Scripts/qa_run_root.py" "$qa_run_root")" \
        || fail "QA run root overlaps production storage"
    [[ "$qa_run_root" == "$canonical_qa_run_root" ]] \
        || fail "QA run root is not canonical"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$PLIST")" == "$qa_run_root" ]] \
        || fail "QA app marker and launch environment roots disagree"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST")" == "$qa_run_root" ]] \
        || fail "QA app and LaunchAgent runtime roots disagree"
    qa_identity_output="$(plutil -convert xml1 -o - "$PLIST"; plutil -convert xml1 -o - "$AGENT_PLIST")"
    [[ "$qa_identity_output" != *"com.ziadnasreldin.ZoidCoach"* ]] \
        || fail "QA package output contains a production identity string"
    stripped_runtime="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)" \
        || fail "QA agent could not resolve its embedded runtime with a stripped environment"
    [[ "$stripped_runtime" == "package=qa mode=qa identity=$AGENT_SIGNING_IDENTIFIER root=$qa_run_root" ]] \
        || fail "QA agent resolved the wrong embedded runtime: $stripped_runtime"
else
    if plutil -extract ZoidCoachQARunRoot raw -o - "$PLIST" >/dev/null 2>&1; then
        fail "production package contains a QA run root"
    fi
    if /usr/libexec/PlistBuddy -c 'Print :LSEnvironment:ZOID_COACH_QA_RUN_ROOT' "$PLIST" >/dev/null 2>&1; then
        fail "production app environment contains a QA run root"
    fi
    if /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ZOID_COACH_QA_RUN_ROOT' "$AGENT_PLIST" >/dev/null 2>&1; then
        fail "production LaunchAgent contains a QA run root"
    fi
    stripped_runtime="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --print-runtime-identity)" \
        || fail "production agent could not resolve its embedded runtime with a stripped environment"
    [[ "$stripped_runtime" == "package=production mode=production identity=$AGENT_SIGNING_IDENTIFIER root=-" ]] \
        || fail "production agent resolved the wrong embedded runtime: $stripped_runtime"
fi

echo "PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent"
