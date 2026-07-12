#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
PLIST="${1:?usage: stamp-build-identity.sh <Info.plist>}"
COMMIT="${ZOID_COACH_BUILD_COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}"

if [[ ! "$COMMIT" =~ '^[0-9a-f]{40}$' ]]; then
    echo "Invalid build commit: $COMMIT" >&2
    exit 1
fi

if [[ -n "${ZOID_COACH_BUILD_STATE:-}" ]]; then
    STATE="$ZOID_COACH_BUILD_STATE"
elif git -C "$ROOT" diff --quiet \
    && git -C "$ROOT" diff --cached --quiet \
    && [[ -z "$(git -C "$ROOT" ls-files --others --exclude-standard)" ]]; then
    STATE="clean"
else
    STATE="dirty"
fi

if [[ "$STATE" != "clean" && "$STATE" != "dirty" ]]; then
    echo "Invalid build state: $STATE" >&2
    exit 1
fi

BUILD_IDENTITY="zoid-coach-$COMMIT-$STATE"
plutil -insert ZoidCoachGitCommit -string "$COMMIT" "$PLIST"
plutil -insert ZoidCoachGitState -string "$STATE" "$PLIST"
plutil -insert ZoidCoachBuildIdentity -string "$BUILD_IDENTITY" "$PLIST"

echo "$BUILD_IDENTITY"
