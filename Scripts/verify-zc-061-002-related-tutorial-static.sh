#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly PARENT="a17f1c2c697b769dc80af959b2385d418d8074c8"
readonly EXPECTED_PATHS=(
    Scripts/qa-zc061002-related-tutorial-fixture.sh
    Scripts/qa-zc061002-related-tutorial-ax-probe.swift
    Scripts/qa-zc061002-signed-preflight.sh
    Scripts/verify-zc-061-002-related-tutorial-static.sh
    docs/ZC-061-002-SIGNED-QA-RUNBOOK.md
)

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

normalized_lines() {
    sed '/^$/d' | LC_ALL=C sort -u
}

require_text() {
    rg -Fq "$2" "$ROOT/$1" || fail "missing required contract in $1: $2"
}

git -C "$ROOT" cat-file -e "$PARENT^{commit}" || fail "technical-context parent commit is unavailable"
git -C "$ROOT" merge-base --is-ancestor "$PARENT" HEAD || fail "candidate is not stacked on the technical-context parent"

expected_scope="$(printf '%s\n' "${EXPECTED_PATHS[@]}" | normalized_lines)"
actual_scope="$({
    git -C "$ROOT" diff --name-only "$PARENT" --
    git -C "$ROOT" ls-files --others --exclude-standard
} | normalized_lines)"
[[ "$actual_scope" == "$expected_scope" ]] || {
    print -u2 -- "FAIL: candidate scope differs from the exact five-file contract"
    diff -u <(print -- "$expected_scope") <(print -- "$actual_scope") >&2 || true
    exit 1
}

for owned_path in "${EXPECTED_PATHS[@]}"; do
    [[ -f "$ROOT/$owned_path" ]] || fail "missing owned path: $owned_path"
done
for executable in "${EXPECTED_PATHS[@]:0:4}"; do
    [[ -x "$ROOT/$executable" ]] || fail "owned script is not executable: $executable"
done

require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "declared_context = 'technical'"
require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "declared_context IS NULL"
require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "record.epoch >= CAST(strftime('%s', interval.started_at) AS INTEGER)"
require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "lower(classification) = 'research'"
require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "privacy-safe fixture evidence"
require_text Scripts/qa-zc061002-related-tutorial-fixture.sh "verification accepted a SQL/schema failure"
require_text Scripts/qa-zc061002-related-tutorial-ax-probe.swift "active declared-technical commitment is not visible"
require_text Scripts/qa-zc061002-related-tutorial-ax-probe.swift "today.behavior-evidence.work-uncertainty.536166617269"
require_text Scripts/qa-zc061002-related-tutorial-ax-probe.swift "Research, 0 minutes"
require_text Scripts/qa-zc061002-signed-preflight.sh "$PARENT"
require_text docs/ZC-061-002-SIGNED-QA-RUNBOOK.md "Do not mark ZC-061-003 complete from this run."

zsh -n "$ROOT/Scripts/qa-zc061002-related-tutorial-fixture.sh"
zsh -n "$ROOT/Scripts/qa-zc061002-signed-preflight.sh"
zsh -n "$ROOT/Scripts/verify-zc-061-002-related-tutorial-static.sh"
"$ROOT/Scripts/qa-zc061002-related-tutorial-fixture.sh" self-test
swift "$ROOT/Scripts/qa-zc061002-related-tutorial-ax-probe.swift" --self-test
"$ROOT/Scripts/qa-zc061002-signed-preflight.sh" --self-test
git -C "$ROOT" diff --check
print -- "PASS: ZC-061-002 exact scope, syntax, fixture, AX, preflight, and runbook contracts"
