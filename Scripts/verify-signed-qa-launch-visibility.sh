#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <package-repository> <isolated-qa-root> [evidence-directory]" >&2
    exit 2
fi

PACKAGE_REPOSITORY="${1:A}"
QA_ROOT="${2:A}"
EVIDENCE_DIRECTORY="${3:-}"
SCRIPT_ROOT="${0:A:h}"
PACKAGE_SCRIPT="$PACKAGE_REPOSITORY/Scripts/package-app.sh"
PACKAGED_APP="$PACKAGE_REPOSITORY/.build/app-qa/Zoid 666 QA.app"
EXECUTABLE="$PACKAGED_APP/Contents/MacOS/ZoidCoachQA"
APP_PID=""

if [[ ! -x "$PACKAGE_SCRIPT" ]]; then
    echo "SETUP_FAIL: signed QA package script is missing in $PACKAGE_REPOSITORY" >&2
    exit 2
fi

cleanup() {
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    pkill -f "$EXECUTABLE" 2>/dev/null || true
    rm -rf "$QA_ROOT"
}
trap cleanup EXIT INT TERM

cleanup
CONFIGURATION=release ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
    "$PACKAGE_SCRIPT" >/tmp/zoid-qa-visibility-package.stdout 2>/tmp/zoid-qa-visibility-package.stderr

"$EXECUTABLE" >/tmp/zoid-qa-foreground.stdout 2>/tmp/zoid-qa-foreground.stderr &
APP_PID=$!
/usr/bin/swift "$SCRIPT_ROOT/qa-app-visibility-probe.swift" "$APP_PID" foreground-visible 3

CONTENT_ARGS=("$APP_PID")
if [[ -n "$EVIDENCE_DIRECTORY" ]]; then
    mkdir -p "$EVIDENCE_DIRECTORY"
    CONTENT_ARGS+=(--screenshot "$EVIDENCE_DIRECTORY/foreground-window.png")
fi
/usr/bin/swift "$SCRIPT_ROOT/qa-window-content-probe.swift" "${CONTENT_ARGS[@]}"
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

"$EXECUTABLE" --background-schedule >/tmp/zoid-qa-background.stdout 2>/tmp/zoid-qa-background.stderr &
APP_PID=$!
/usr/bin/swift "$SCRIPT_ROOT/qa-app-visibility-probe.swift" "$APP_PID" background-windowless-menu-ready 5
