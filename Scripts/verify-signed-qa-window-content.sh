#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <signed-qa-app> <isolated-qa-root>" >&2
    exit 2
fi

APP_PATH="${1:A}"
QA_ROOT="${2:A}"
EXECUTABLE="$APP_PATH/Contents/MacOS/ZoidCoachQA"
SCRIPT_ROOT="${0:A:h}"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "SETUP_FAIL: signed QA executable is missing at $EXECUTABLE" >&2
    exit 2
fi

codesign --verify --deep --strict "$APP_PATH"
rm -rf "$QA_ROOT"
mkdir -p "$QA_ROOT"

ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" "$EXECUTABLE" >/tmp/zoid-qa-window-repro.stdout 2>/tmp/zoid-qa-window-repro.stderr &
APP_PID=$!

cleanup() {
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    rm -rf "$QA_ROOT"
}
trap cleanup EXIT INT TERM

swift "$SCRIPT_ROOT/qa-window-content-probe.swift" "$APP_PID"
