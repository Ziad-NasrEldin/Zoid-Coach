#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="8c9e007d467fe2b5388e151914a559a8245d18ed"
readonly EXPECTED_PATHS=(
    Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift
    Scripts/qa-zc061008-future-rule-fixture.sh
    Scripts/qa-zc061008-future-rule-ax-probe.swift
    Scripts/qa-zc061008-signed-preflight.sh
    Scripts/verify-zc-061-008-future-rule-static.sh
    docs/ZC-061-008-SIGNED-QA-RUNBOOK.md
)

fail() { print -u2 -- "FAIL: $*"; exit 1; }
normalized_lines() { sed '/^$/d' | LC_ALL=C sort -u; }
require_text() { rg -Fq "$2" "$ROOT/$1" || fail "missing contract in $1: $2"; }

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "stacked parent is unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD \
    || fail "candidate is not stacked on the required parent"

expected_scope="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
actual_scope="$({
    git -C "$ROOT" diff --name-only "$PARENT" --
    git -C "$ROOT" ls-files --others --exclude-standard
} | normalized_lines)"
[[ "$actual_scope" == "$expected_scope" ]] || {
    diff -u <(print -- "$expected_scope") <(print -- "$actual_scope") >&2 || true
    fail "candidate differs from the exact six-file scope"
}

for owned_path in "${EXPECTED_PATHS[@]}"; do
    [[ -f "$ROOT/$owned_path" ]] || fail "missing $owned_path"
done
for executable_path in \
    Scripts/qa-zc061008-future-rule-fixture.sh \
    Scripts/qa-zc061008-future-rule-ax-probe.swift \
    Scripts/qa-zc061008-signed-preflight.sh \
    Scripts/verify-zc-061-008-future-rule-static.sh; do
    [[ -x "$ROOT/$executable_path" ]] || fail "script is not executable: $executable_path"
done

require_text Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift "zc061008FutureRuleClassifiesOnlyLaterMatchingObservationAndIsIdempotent"
require_text Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift "zc061008RuleBoundariesDoNotOverreach"
require_text Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift "zc061008InvalidRuleSchemaFailsClosedWithoutIngestingObservation"
require_text Scripts/qa-zc061008-future-rule-fixture.sh "qualifying|pre-effective|nonmatching|removed-rule"
require_text Scripts/qa-zc061008-future-rule-fixture.sh "no duplicate future ingestion"
require_text Scripts/qa-zc061008-future-rule-fixture.sh "SQL/schema failure"
require_text Scripts/qa-zc061008-future-rule-fixture.sh "privacy leakage"
require_text Scripts/qa-zc061008-future-rule-fixture.sh "byte-exact baseline"
require_text Scripts/qa-zc061008-future-rule-ax-probe.swift "two distinct Safari Work sessions"
require_text Scripts/qa-zc061008-future-rule-ax-probe.swift "Historical records are unchanged"
require_text Scripts/qa-zc061008-signed-preflight.sh "$PARENT"
require_text Scripts/qa-zc061008-signed-preflight.sh 'case "--once"'
require_text docs/ZC-061-008-SIGNED-QA-RUNBOOK.md '"$AGENT_EXECUTABLE" --once'
require_text docs/ZC-061-008-SIGNED-QA-RUNBOOK.md 'run_phase qualifying 2'
require_text docs/ZC-061-008-SIGNED-QA-RUNBOOK.md 'assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"'
require_text docs/ZC-061-008-SIGNED-QA-RUNBOOK.md "Never invent or display a Research classification."

zsh -n "$ROOT/Scripts/qa-zc061008-future-rule-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc061008-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-061-008-future-rule-static.sh"
swiftc -frontend -parse "$ROOT/Tests/ZoidCoachAppTests/ZC061008FutureRuleJourneyTests.swift"
swift "$ROOT/Scripts/qa-zc061008-future-rule-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc061008-future-rule-fixture.sh" self-test
"$ROOT/Scripts/qa-zc061008-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-061-008 exact scope, syntax, fixture, AX, preflight, privacy, schema, and restoration contracts"
