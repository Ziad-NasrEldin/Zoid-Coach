#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE_APP="$ROOT/.build/app/Zoid Coach.app"
INSTALL_ROOT="${ZOID_COACH_INSTALL_ROOT:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_ROOT/Zoid Coach.app"

"$ROOT/Scripts/package-app.sh"
"$ROOT/Scripts/ensure-screenwatch.sh"
mkdir -p "$INSTALL_ROOT"
rm -rf "$INSTALLED_APP"
ditto "$SOURCE_APP" "$INSTALLED_APP"
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"
open "$INSTALLED_APP"

expected_build="$(plutil -extract CFBundleVersion raw -o - "$INSTALLED_APP/Contents/Info.plist")"
restarted_agent=false
for _ in {1..30}; do
    service="$(launchctl print "gui/$(id -u)/com.ziadnasreldin.ZoidCoach.agent" 2>/dev/null || true)"
    if grep -q "parent bundle version = $expected_build" <<<"$service"; then
        if [[ "$restarted_agent" == "false" ]]; then
            launchctl kickstart -k "gui/$(id -u)/com.ziadnasreldin.ZoidCoach.agent"
            restarted_agent=true
            sleep 1
            continue
        fi
        pid="$(awk '/pid =/{print $3; exit}' <<<"$service")"
        executable="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep 'ZoidCoachAgent$')"
        if [[ "$executable" == "$INSTALLED_APP/Contents/MacOS/ZoidCoachAgent" ]]; then
            "$ROOT/Scripts/verify-background-services.sh"
            echo "$INSTALLED_APP"
            exit 0
        fi
    fi
    sleep 1
done

echo "Zoid Coach was copied, but its login agent did not move to the installed app" >&2
exit 1
