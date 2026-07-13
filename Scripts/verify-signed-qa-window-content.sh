#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <signed-qa-app> <isolated-qa-root>" >&2
    exit 2
fi

APP_PATH="${1:A}"
QA_ROOT="${2:A}"
SOURCE_EXECUTABLE="$APP_PATH/Contents/MacOS/ZoidCoachQA"
SCRIPT_ROOT="${0:A:h}"
INSTALL_ROOT="${QA_ROOT}-install"
INSTALLED_APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
EXECUTABLE="$INSTALLED_APP/Contents/MacOS/ZoidCoachQA"

if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
    echo "SETUP_FAIL: signed QA executable is missing at $SOURCE_EXECUTABLE" >&2
    exit 2
fi

codesign --verify --deep --strict "$APP_PATH"
rm -rf "$QA_ROOT" "$INSTALL_ROOT"
mkdir -p "$QA_ROOT" "$INSTALL_ROOT"
ditto "$APP_PATH" "$INSTALLED_APP"
"$EXECUTABLE" --qa-register-agent >/tmp/zoid-qa-window-register.stdout 2>/tmp/zoid-qa-window-register.stderr
for _ in {1..100}; do
    if launchctl print gui/$UID/qa.ziadnasreldin.ZoidCoach.agent 2>/dev/null | grep -q 'state = running'; then
        break
    fi
    sleep 0.1
done
open -na "$INSTALLED_APP"

APP_PID=""
for _ in {1..100}; do
    APP_PID="$(pgrep -f "$EXECUTABLE" | head -1 || true)"
    [[ -n "$APP_PID" ]] && break
    sleep 0.1
done
if [[ -z "$APP_PID" ]]; then
    echo "SETUP_FAIL: installed signed QA process did not launch" >&2
    exit 2
fi

cleanup() {
    kill "$APP_PID" 2>/dev/null || true
    "$EXECUTABLE" --qa-unregister-agent >/dev/null 2>&1 || true
    rm -rf "$QA_ROOT" "$INSTALL_ROOT"
}
trap cleanup EXIT INT TERM

swift "$SCRIPT_ROOT/qa-window-content-probe.swift" "$APP_PID"
