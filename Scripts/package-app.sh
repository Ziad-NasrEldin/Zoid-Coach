#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-debug}"
PACKAGE_MODE="${ZOID_COACH_PACKAGE_MODE:-production}"
[[ "$PACKAGE_MODE" == "production" || "$PACKAGE_MODE" == "qa" ]] || {
    echo "ZOID_COACH_PACKAGE_MODE must be production or qa" >&2
    exit 1
}
IDENTITIES="$ROOT/App/PackageIdentities.plist"
identity_value() {
    /usr/libexec/PlistBuddy -c "Print :$PACKAGE_MODE:$1" "$IDENTITIES"
}
APP_ROOT="$ROOT/$(identity_value appPath)"
CONTENTS="$APP_ROOT/Contents"
APP_EXECUTABLE_NAME="$(identity_value appExecutableName)"
APP_SIGNING_IDENTIFIER="$(identity_value appSigningIdentifier)"
AGENT_EXECUTABLE_NAME="$(identity_value agentExecutableName)"
AGENT_SIGNING_IDENTIFIER="$(identity_value agentSigningIdentifier)"
LAUNCH_AGENT_PLIST_NAME="$(identity_value launchAgentPlistName)"
QA_RUN_ROOT="${ZOID_COACH_QA_RUN_ROOT:-$ROOT/.build/qa-runtime}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Development: Ziad Ahmed (4VJ4SRGADX)}"

cd "$ROOT"
security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY" || {
    echo "Signing identity is unavailable: $SIGNING_IDENTITY" >&2
    exit 1
}
BUILD_IDENTITY_BEFORE="$("$ROOT/Scripts/stamp-build-identity.sh" --print "$ROOT")"
if [[ "$PACKAGE_MODE" == "qa" && "$BUILD_IDENTITY_BEFORE" != *-clean ]]; then
    echo "QA packages require a clean repository identity" >&2
    exit 1
fi
BUILD_COMMIT="$(git rev-parse HEAD)"
BUILD_ROOT="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
swift build --configuration "$CONFIGURATION" --product ZoidCoach
swift build --configuration "$CONFIGURATION" --product ZoidCoachAgent
BUILD_IDENTITY_AFTER="$("$ROOT/Scripts/stamp-build-identity.sh" --print "$ROOT")"
[[ "$BUILD_IDENTITY_AFTER" == "$BUILD_IDENTITY_BEFORE" ]] || {
    echo "Repository identity changed while the package was being built" >&2
    exit 1
}

rm -rf "$APP_ROOT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Library/LaunchAgents"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/App/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist" "$CONTENTS/Library/LaunchAgents/$LAUNCH_AGENT_PLIST_NAME"
"$ROOT/Scripts/configure-package-plists.py" \
    --mode "$PACKAGE_MODE" \
    --identities "$IDENTITIES" \
    --info-plist "$CONTENTS/Info.plist" \
    --launch-agent-plist "$CONTENTS/Library/LaunchAgents/$LAUNCH_AGENT_PLIST_NAME" \
    --qa-run-root "$QA_RUN_ROOT"
STAMPED_IDENTITY="$("$ROOT/Scripts/stamp-build-identity.sh" "$CONTENTS/Info.plist" "$ROOT")"
[[ "$STAMPED_IDENTITY" == "$BUILD_IDENTITY_BEFORE" ]] || {
    echo "Stamped identity changed after compilation" >&2
    exit 1
}
cp "$BUILD_ROOT/ZoidCoach" "$CONTENTS/MacOS/$APP_EXECUTABLE_NAME"
cp "$BUILD_ROOT/ZoidCoachAgent" "$CONTENTS/MacOS/$AGENT_EXECUTABLE_NAME"
chmod +x "$CONTENTS/MacOS/$APP_EXECUTABLE_NAME"
chmod +x "$CONTENTS/MacOS/$AGENT_EXECUTABLE_NAME"

plutil -lint "$CONTENTS/Info.plist" "$CONTENTS/Library/LaunchAgents/$LAUNCH_AGENT_PLIST_NAME" >/dev/null

# Sign nested code first with stable identifiers so the XPC peer validator can
# authenticate both processes and EventKit permissions remain stable.
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier "$AGENT_SIGNING_IDENTIFIER" "$CONTENTS/MacOS/$AGENT_EXECUTABLE_NAME" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier "$APP_SIGNING_IDENTIFIER" --entitlements "$ROOT/App/ZoidCoach.entitlements" "$CONTENTS/MacOS/$APP_EXECUTABLE_NAME" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/App/ZoidCoach.entitlements" "$APP_ROOT" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_ROOT" >/dev/null
VERIFY_ARGUMENTS=("--mode" "$PACKAGE_MODE" "--expected-commit" "$BUILD_COMMIT")
if [[ "$PACKAGE_MODE" == "qa" ]]; then
    VERIFY_ARGUMENTS+=("--require-clean")
fi
"$ROOT/Scripts/verify-package.sh" "$APP_ROOT" "${VERIFY_ARGUMENTS[@]}"

echo "$APP_ROOT"
