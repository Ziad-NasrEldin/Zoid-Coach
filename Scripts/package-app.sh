#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-debug}"
ARCH="$(uname -m)"
BUILD_ROOT="$ROOT/.build/$ARCH-apple-macosx/$CONFIGURATION"
APP_ROOT="$ROOT/.build/app/Zoid Coach.app"
CONTENTS="$APP_ROOT/Contents"

cd "$ROOT"
swift build --configuration "$CONFIGURATION"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
cp "$BUILD_ROOT/ZoidCoach" "$CONTENTS/MacOS/ZoidCoach"
chmod +x "$CONTENTS/MacOS/ZoidCoach"

codesign --force --deep --sign - "$APP_ROOT" >/dev/null

echo "$APP_ROOT"
