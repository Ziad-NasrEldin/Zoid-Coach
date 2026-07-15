#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="72854220dd3c1de0ff1a8c7e701a9a966912226d"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift
    Scripts/qa-zc062003-source-warning-suppression-fixture.sh
    Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift
    Scripts/qa-zc062003-signed-preflight.sh
    Scripts/verify-zc-062-003-source-warning-suppression-static.sh
    docs/ZC-062-003-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized() { sed '/^$/d' | LC_ALL=C sort -u; }
require_text() { rg -Fq "$2" "$ROOT/$1" || fail "missing contract in $1: $2"; }

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "required parent unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD || fail "candidate is not stacked on ZC-062-002"
expected="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized)"
actual="$({ git -C "$ROOT" diff --name-only "$PARENT" --; git -C "$ROOT" ls-files --others --exclude-standard; } | normalized)"
[[ "$actual" == "$expected" ]] || { diff -u <(print -- "$expected") <(print -- "$actual") >&2 || true; fail "candidate differs from exact six-file scope"; }

for owned_path in "${EXPECTED_PATHS[@]}"; do [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"; done
for executable_path in Scripts/qa-zc062003-source-warning-suppression-fixture.sh Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift Scripts/qa-zc062003-signed-preflight.sh Scripts/verify-zc-062-003-source-warning-suppression-static.sh; do
    [[ -x "$ROOT/$executable_path" ]] || fail "script is not executable: $executable_path"
done

require_text Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift "zc062003HealthyControlThenOutageWarnsAndSuppresses"
require_text Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift "noEligibleBaseline"
require_text Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift "notificationRemains"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "one healthy eligible strong prompt"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "seven complete baseline days"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "exact system withdrawal reason"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "scheduled or delivered strong notification remains"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "visible source warning state"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "existing-handled"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "no-eligible-baseline"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "real Screenwatch path"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "SQL/schema failure"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "privacy leakage"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "duplicate snapshot"
require_text Scripts/qa-zc062003-source-warning-suppression-fixture.sh "cleanup mismatch"
require_text Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift '"healthy", "stale", "missing"'
require_text Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift "!strongWording.contains"
require_text Scripts/qa-zc062003-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc062003-signed-preflight.sh "wrong database path accepted"
require_text Scripts/qa-zc062003-signed-preflight.sh "wrong helper path accepted"
require_text docs/ZC-062-003-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-062-003-SIGNED-QA-RUNBOOK.md "ordinary foreground app relaunch"
require_text docs/ZC-062-003-SIGNED-QA-RUNBOOK.md "run_outage scheduled stale"
require_text docs/ZC-062-003-SIGNED-QA-RUNBOOK.md "run_outage delivered missing"
require_text docs/ZC-062-003-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'

zsh -n "$ROOT/Scripts/qa-zc062003-source-warning-suppression-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc062003-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-062-003-source-warning-suppression-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC062003SourceWarningSuppressionJourneyTests.swift"
swiftc -typecheck "$ROOT/Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift"
swift "$ROOT/Scripts/qa-zc062003-source-warning-suppression-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc062003-source-warning-suppression-fixture.sh" self-test
"$ROOT/Scripts/qa-zc062003-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-062-003 exact scope, syntax, healthy control, warnings, suppression, notification withdrawal, persistence, privacy, negatives, and restore contracts"
