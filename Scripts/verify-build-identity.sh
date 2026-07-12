#!/bin/zsh

set -euo pipefail

PLIST="${1:?usage: verify-build-identity.sh <Info.plist> [--expected-commit SHA] [--require-clean]}"
shift
EXPECTED_COMMIT=""
REQUIRE_CLEAN=0

while (( $# > 0 )); do
    case "$1" in
        --expected-commit)
            (( $# >= 2 )) || { echo "Missing value for --expected-commit" >&2; exit 1; }
            EXPECTED_COMMIT="$2"
            shift 2
            ;;
        --require-clean)
            REQUIRE_CLEAN=1
            shift
            ;;
        *)
            echo "Unknown build identity option: $1" >&2
            exit 1
            ;;
    esac
done

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

build_commit="$(plutil -extract ZoidCoachGitCommit raw -o - "$PLIST")"
build_state="$(plutil -extract ZoidCoachGitState raw -o - "$PLIST")"
build_identity="$(plutil -extract ZoidCoachBuildIdentity raw -o - "$PLIST")"
[[ "$build_commit" =~ '^[0-9a-f]{40}$' ]] || fail "packaged build commit is invalid"
[[ "$build_state" == "clean" || "$build_state" == "dirty" ]] || fail "packaged build state is invalid"
[[ "$build_identity" == "zoid-coach-$build_commit-$build_state" ]] \
    || fail "packaged build identity does not match its commit and state"
if [[ -n "$EXPECTED_COMMIT" && "$build_commit" != "$EXPECTED_COMMIT" ]]; then
    fail "packaged build commit does not match expected commit $EXPECTED_COMMIT"
fi
if (( REQUIRE_CLEAN )) && [[ "$build_state" != "clean" ]]; then
    fail "dirty packages cannot prove scenario completion"
fi

echo "$build_identity"
