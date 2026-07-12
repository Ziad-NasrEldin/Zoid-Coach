#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
MODE="stamp"
if [[ "${1:-}" == "--print" ]]; then
    MODE="print"
    shift
fi
PLIST=""
if [[ "$MODE" == "stamp" ]]; then
    PLIST="${1:?usage: stamp-build-identity.sh [--print] <Info.plist> [repository]}"
    shift
fi
REPOSITORY="${1:-$ROOT}"
GIT=(env -i "PATH=$PATH" "HOME=$HOME" "TMPDIR=${TMPDIR:-/tmp}" git -C "$REPOSITORY")
COMMIT="$("${GIT[@]}" rev-parse HEAD)"

if [[ ! "$COMMIT" =~ '^[0-9a-f]{40}$' ]]; then
    echo "Invalid build commit: $COMMIT" >&2
    exit 1
fi

if [[ -z "$("${GIT[@]}" status --porcelain --untracked-files=normal)" ]]; then
    STATE="clean"
else
    STATE="dirty"
fi

BUILD_IDENTITY="zoid-coach-$COMMIT-$STATE"
if [[ "$MODE" == "print" ]]; then
    echo "$BUILD_IDENTITY"
    exit 0
fi
plutil -insert ZoidCoachGitCommit -string "$COMMIT" "$PLIST"
plutil -insert ZoidCoachGitState -string "$STATE" "$PLIST"
plutil -insert ZoidCoachBuildIdentity -string "$BUILD_IDENTITY" "$PLIST"

echo "$BUILD_IDENTITY"
