#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
source "$ROOT/Scripts/lib/signed-qa-runtime-lifecycle.sh"
IDENTITIES="$ROOT/App/PackageIdentities.plist"
INSTALL_ROOT="${ZOID_COACH_QA_INSTALL_ROOT:-$HOME/Applications}"
QA_ROOT="${ZOID_COACH_QA_RUN_ROOT:-/private/tmp/zoid-666-signed-qa}"
USER_DOMAIN="gui/$(id -u)"

identity_value() {
    /usr/libexec/PlistBuddy -c "Print :qa:$1" "$IDENTITIES"
}

DISPLAY_NAME="$(identity_value appDisplayName)"
APP_EXECUTABLE="$(identity_value appExecutableName)"
AGENT_LABEL="$(identity_value launchAgentLabel)"
INSTALLED_APP="$INSTALL_ROOT/$DISPLAY_NAME E2E.app"

qa_unregister_installed_agent "$INSTALLED_APP" "$APP_EXECUTABLE"
launchctl bootout "$USER_DOMAIN/$AGENT_LABEL" >/dev/null 2>&1 || true
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
rm -rf "$INSTALLED_APP"
if [[ "${ZOID_COACH_QA_KEEP_DATA:-false}" != "true" ]]; then
    rm -rf "$QA_ROOT"
fi

echo "PASS: signed QA runtime removed"
