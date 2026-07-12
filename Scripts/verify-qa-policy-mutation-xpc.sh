#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
QA_ROOT="$ROOT/.build/qa-policy-mutation-xpc-$PPID"
PACKAGED_APP="$ROOT/.build/app-qa/Zoid Coach QA.app"
INSTALLED_APP="$HOME/Applications/Zoid Coach QA Policy Probe.app"
LABEL="qa.ziadnasreldin.ZoidCoach.agent"
USER_DOMAIN="gui/$(id -u)"

cleanup() {
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        launchctl print "$USER_DOMAIN/$LABEL" >&2 || true
    fi
    launchctl bootout "$USER_DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -rf "$INSTALLED_APP" "$QA_ROOT"
}
trap cleanup EXIT

rm -rf "$QA_ROOT" "$INSTALLED_APP"
mkdir -p "$QA_ROOT" "$HOME/Applications"
ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
    "$ROOT/Scripts/package-app.sh" >/dev/null
ditto "$PACKAGED_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" >/dev/null
launchctl bootout "$USER_DOMAIN/$LABEL" >/dev/null 2>&1 || true

"$INSTALLED_APP/Contents/MacOS/ZoidCoachQA" \
    --qa-policy-mutation-xpc-probe
