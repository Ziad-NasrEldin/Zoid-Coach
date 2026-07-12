#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_ROOT="$ROOT/.build/app/Zoid Coach.app"
CONTENTS="$APP_ROOT/Contents"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Development: Ziad Ahmed (4VJ4SRGADX)}"

cd "$ROOT"
security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY" || {
    echo "Signing identity is unavailable: $SIGNING_IDENTITY" >&2
    exit 1
}
BUILD_IDENTITY_BEFORE="$("$ROOT/Scripts/stamp-build-identity.sh" --print "$ROOT")"
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
STAMPED_IDENTITY="$("$ROOT/Scripts/stamp-build-identity.sh" "$CONTENTS/Info.plist" "$ROOT")"
[[ "$STAMPED_IDENTITY" == "$BUILD_IDENTITY_BEFORE" ]] || {
    echo "Stamped identity changed after compilation" >&2
    exit 1
}
cp "$BUILD_ROOT/ZoidCoach" "$CONTENTS/MacOS/ZoidCoach"
cp "$BUILD_ROOT/ZoidCoachAgent" "$CONTENTS/MacOS/ZoidCoachAgent"
cp "$ROOT/App/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist" "$CONTENTS/Library/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist"
chmod +x "$CONTENTS/MacOS/ZoidCoach"
chmod +x "$CONTENTS/MacOS/ZoidCoachAgent"

plutil -lint "$CONTENTS/Info.plist" "$CONTENTS/Library/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist" >/dev/null

# Sign nested code first with stable identifiers so the XPC peer validator can
# authenticate both processes and EventKit permissions remain stable.
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier com.ziadnasreldin.ZoidCoach.agent "$CONTENTS/MacOS/ZoidCoachAgent" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier com.ziadnasreldin.ZoidCoach --entitlements "$ROOT/App/ZoidCoach.entitlements" "$CONTENTS/MacOS/ZoidCoach" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ROOT/App/ZoidCoach.entitlements" "$APP_ROOT" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_ROOT" >/dev/null
"$ROOT/Scripts/verify-package.sh" "$APP_ROOT" --expected-commit "$BUILD_COMMIT"

echo "$APP_ROOT"
