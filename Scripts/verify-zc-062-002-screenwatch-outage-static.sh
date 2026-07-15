#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="e38794acb3068ed16051c6eb820405319dbda912"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062002ScreenwatchOutageJourneyTests.swift
    Scripts/qa-zc062002-screenwatch-outage-fixture.sh
    Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift
    Scripts/qa-zc062002-signed-preflight.sh
    Scripts/verify-zc-062-002-screenwatch-outage-static.sh
    docs/ZC-062-002-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized() { sed '/^$/d' | LC_ALL=C sort -u; }
require_text() { rg -Fq "$2" "$ROOT/$1" || fail "missing contract in $1: $2"; }

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "required parent unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD || fail "candidate is not stacked on required parent"
expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized)"
actual="$({ git -C "$ROOT" diff --name-only "$PARENT" --; git -C "$ROOT" ls-files --others --exclude-standard; } | normalized)"
[[ "$actual" == "$expected" ]] || { diff -u <(print -- "$expected") <(print -- "$actual") >&2 || true; fail "candidate differs from exact six-file scope"; }

for owned_path in "${EXPECTED_PATHS[@]}"; do [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"; done
for executable_path in Scripts/qa-zc062002-screenwatch-outage-fixture.sh Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift Scripts/qa-zc062002-signed-preflight.sh Scripts/verify-zc-062-002-screenwatch-outage-static.sh; do
    [[ -x "$ROOT/$executable_path" ]] || fail "script is not executable: $executable_path"
done

require_text Tests/ZoidCoachAppTests/ZC062002ScreenwatchOutageJourneyTests.swift "zc062002ActiveTechnicalTaskSurvivesIsolatedScreenwatchOutage"
require_text Tests/ZoidCoachAppTests/ZC062002ScreenwatchOutageJourneyTests.swift "staleAcceptedAsFresh"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh '/private/tmp/zoid-666-zc062002-'
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "active execution state"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "wrong source root"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "real Screenwatch path"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "SQL/schema failure"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "privacy leak"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "duplicate snapshot"
require_text Scripts/qa-zc062002-screenwatch-outage-fixture.sh "cleanup mismatch"
require_text Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift '"fresh", "stale", "missing"'
require_text Scripts/qa-zc062002-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc062002-signed-preflight.sh "wrong database path accepted"
require_text Scripts/qa-zc062002-signed-preflight.sh "wrong helper path accepted"
require_text docs/ZC-062-002-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-062-002-SIGNED-QA-RUNBOOK.md "ordinary foreground app relaunch"
require_text docs/ZC-062-002-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'
require_text docs/ZC-062-002-SIGNED-QA-RUNBOOK.md "does not qualify ZC-062-003"

zsh -n "$ROOT/Scripts/qa-zc062002-screenwatch-outage-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc062002-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-062-002-screenwatch-outage-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC062002ScreenwatchOutageJourneyTests.swift"
swiftc -typecheck "$ROOT/Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift"
swift "$ROOT/Scripts/qa-zc062002-screenwatch-outage-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc062002-screenwatch-outage-fixture.sh" self-test
"$ROOT/Scripts/qa-zc062002-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-062-002 exact scope, syntax, typecheck, outage transitions, active persistence, identity, privacy, negatives, and restore contracts"
