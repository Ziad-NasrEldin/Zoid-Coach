#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
IDENTITIES="$ROOT/App/PackageIdentities.plist"
QA_ROOT="${ZOID_COACH_QA_RUN_ROOT:-/private/tmp/zoid-666-signed-qa}"
INSTALL_ROOT="${ZOID_COACH_QA_INSTALL_ROOT:-$HOME/Applications}"
KEEP_EXISTING_DATA="${ZOID_COACH_QA_KEEP_DATA:-false}"
USER_DOMAIN="gui/$(id -u)"

identity_value() {
    /usr/libexec/PlistBuddy -c "Print :qa:$1" "$IDENTITIES"
}

PACKAGED_RELATIVE_PATH="$(identity_value appPath)"
PACKAGED_APP="$ROOT/$PACKAGED_RELATIVE_PATH"
DISPLAY_NAME="$(identity_value appDisplayName)"
APP_EXECUTABLE="$(identity_value appExecutableName)"
AGENT_EXECUTABLE="$(identity_value agentExecutableName)"
AGENT_LABEL="$(identity_value launchAgentLabel)"
INSTALLED_APP="$INSTALL_ROOT/$DISPLAY_NAME E2E.app"

if [[ "$KEEP_EXISTING_DATA" != "true" ]]; then
    rm -rf "$QA_ROOT"
fi
mkdir -p "$QA_ROOT" "$INSTALL_ROOT"

launchctl bootout "$USER_DOMAIN/$AGENT_LABEL" >/dev/null 2>&1 || true
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
rm -rf "$INSTALLED_APP"

ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
    "$ROOT/Scripts/package-app.sh" >/dev/null
ditto "$PACKAGED_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" >/dev/null

"$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-register-agent

agent_path="$INSTALLED_APP/Contents/MacOS/$AGENT_EXECUTABLE"
service=""
for _ in {1..30}; do
    service="$(launchctl print "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true)"
    pid="$(awk '/pid =/{print $3; exit}' <<<"$service")"
    if [[ -n "$pid" ]]; then
        executable="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -F "$AGENT_EXECUTABLE" || true)"
        if [[ "$executable" == "$agent_path" ]] && grep -Fq "name = $AGENT_LABEL" <<<"$service"; then
            break
        fi
    fi
    sleep 0.2
done

if [[ "${executable:-}" != "$agent_path" ]]; then
    print -u2 "FAIL: QA LaunchAgent did not start from the installed signed app"
    print -u2 "$service"
    exit 1
fi

open "$INSTALLED_APP"

cat <<EOF
PASS: signed QA runtime installed
app=$INSTALLED_APP
qa_root=$QA_ROOT
agent_label=$AGENT_LABEL
agent_executable=$agent_path
EOF
