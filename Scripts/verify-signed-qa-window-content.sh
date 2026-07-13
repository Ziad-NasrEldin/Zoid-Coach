#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <package-repository> <isolated-qa-root> <isolated-install-root>" >&2
    exit 2
fi

PACKAGE_REPOSITORY="${1:A}"
QA_ROOT="${2:A}"
INSTALL_ROOT="${3:A}"
SCRIPT_ROOT="${0:A:h}"
INSTALLED_APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
EXECUTABLE="$INSTALLED_APP/Contents/MacOS/ZoidCoachQA"
AGENT_EXECUTABLE="$INSTALLED_APP/Contents/MacOS/ZoidCoachAgentQA"
INSTALL_SCRIPT="$PACKAGE_REPOSITORY/Scripts/install-signed-qa-runtime.sh"
UNINSTALL_SCRIPT="$PACKAGE_REPOSITORY/Scripts/uninstall-signed-qa-runtime.sh"

if [[ ! -x "$INSTALL_SCRIPT" || ! -x "$UNINSTALL_SCRIPT" ]]; then
    echo "SETUP_FAIL: signed QA lifecycle scripts are missing in $PACKAGE_REPOSITORY" >&2
    exit 2
fi

cleanup() {
    pkill -f "$EXECUTABLE" 2>/dev/null || true
    pkill -f "$AGENT_EXECUTABLE" 2>/dev/null || true
    ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
        "$UNINSTALL_SCRIPT" >/dev/null 2>&1 || true
    rm -rf "$QA_ROOT" "$INSTALL_ROOT"
}
trap cleanup EXIT INT TERM

cleanup
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
    "$INSTALL_SCRIPT" >/tmp/zoid-qa-window-install.stdout 2>/tmp/zoid-qa-window-install.stderr

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

VERDICT=""
for _ in {1..100}; do
    VERDICT="$(/usr/bin/osascript "$SCRIPT_ROOT/qa-window-system-events-probe.applescript" 2>&1)"
    case "$VERDICT" in
        SETUP_FAIL\|process=absent*|SETUP_FAIL\|process=present\|window=absent*) sleep 0.1 ;;
        *) break ;;
    esac
done
echo "$VERDICT"
case "$VERDICT" in
    RED\|*) exit 1 ;;
    GREEN\|*) exit 0 ;;
    *) exit 2 ;;
esac
