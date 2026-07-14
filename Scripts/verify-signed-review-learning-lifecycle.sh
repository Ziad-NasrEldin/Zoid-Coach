#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROBE="$SCRIPT_DIR/qa-combined-review-ax-probe.swift"
readonly FIXTURE="$SCRIPT_DIR/qa-combined-review-fixture.sh"
readonly APP="${1:-}"
readonly DATABASE="${2:-}"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

[[ -d "$APP" ]] || fail "signed app does not exist: $APP"
[[ -f "$DATABASE" ]] || fail "database does not exist: $DATABASE"
[[ -x "$FIXTURE" ]] || fail "fixture is unavailable"
[[ -f "$PROBE" ]] || fail "AX probe is unavailable"

readonly EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
readonly EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
[[ -x "$EXECUTABLE" ]] || fail "signed app executable is unavailable"

scalar() {
    sqlite3 -batch -noheader "$DATABASE" "$1"
}

assert_scalar() {
    local sql="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(scalar "$sql")"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

running_pid() {
    local pid
    for _ in {1..40}; do
        for pid in ${(f)"$(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null || true)"}; do
            if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$EXECUTABLE"; then
                print -- "$pid"
                return 0
            fi
        done
        sleep 0.2
    done
    return 1
}

launch_app() {
    open "$APP"
    local pid
    pid="$(running_pid)" || fail "signed QA app did not launch from the expected bundle"
    print -- "$pid"
}

relaunch_app() {
    local pid="$1"
    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..30}; do
        kill -0 "$pid" >/dev/null 2>&1 || break
        sleep 0.1
    done
    launch_app
}

assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "0" "initial learned promotion count"

pid="$(launch_app)"
swift "$PROBE" --pid "$pid" --skip-daily --expand-weekly --accept-hypothesis
assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "1" "accepted learned promotion count"

pid="$(relaunch_app "$pid")"
swift "$PROBE" --pid "$pid" --skip-daily --expand-weekly --expect-learned
assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "1" "relaunch learned promotion count"

pid="$(relaunch_app "$pid")"
swift "$PROBE" --pid "$pid" --delete-learning
assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "0" "privacy-deleted learned promotion count"

# Privacy deletion intentionally clears the review inputs that derived the pattern.
# Re-seeding the same deterministic evidence proves the candidate identity is still NOT LEARNED after relaunch.
"$FIXTURE" prepare "$DATABASE"
assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "0" "reseeded learned promotion count"

pid="$(relaunch_app "$pid")"
swift "$PROBE" --pid "$pid" --skip-daily --expand-weekly
assert_scalar "SELECT COUNT(*) FROM review_hypothesis_promotions;" "0" "final not-learned promotion count"

print -- "PASS: signed six-category and review-learning lifecycle verified end to end"
print -- "PASS: accept created one row, relaunch restored LEARNED, privacy deletion removed it, and deterministic re-derivation remained NOT LEARNED"
