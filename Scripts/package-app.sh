#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-debug}"
ARCH="$(uname -m)"
BUILD_ROOT="$ROOT/.build/$ARCH-apple-macosx/$CONFIGURATION"
APP_ROOT="$ROOT/.build/app/Zoid Coach.app"
CONTENTS="$APP_ROOT/Contents"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Apple Development: Ziad Ahmed (4VJ4SRGADX)}"

cd "$ROOT"
swift build --configuration "$CONFIGURATION" --product ZoidCoach
swift build --configuration "$CONFIGURATION" --product ZoidCoachAgent

rm -rf "$APP_ROOT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Library/LaunchAgents"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$BUILD_ROOT/ZoidCoach" "$CONTENTS/MacOS/ZoidCoach"
cp "$BUILD_ROOT/ZoidCoachAgent" "$CONTENTS/MacOS/ZoidCoachAgent"
cp "$ROOT/App/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist" "$CONTENTS/Library/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist"
chmod +x "$CONTENTS/MacOS/ZoidCoach"
chmod +x "$CONTENTS/MacOS/ZoidCoachAgent"

plutil -lint "$CONTENTS/Info.plist" "$CONTENTS/Library/LaunchAgents/com.ziadnasreldin.ZoidCoach.agent.plist" >/dev/null

# Sign nested code first with stable identifiers so the XPC peer validator can
# authenticate both processes and EventKit permissions remain stable.
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier com.ziadnasreldin.ZoidCoach.agent "$CONTENTS/MacOS/ZoidCoachAgent" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier com.ziadnasreldin.ZoidCoach "$CONTENTS/MacOS/ZoidCoach" >/dev/null
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_ROOT" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_ROOT" >/dev/null

echo "$APP_ROOT"
