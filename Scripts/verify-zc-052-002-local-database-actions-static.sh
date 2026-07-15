#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="361093b4a088c19eee927eaab2b58a40fb3b4c27"
PRODUCT_CANDIDATE="0dce73882fbbca08aab8f39038205a47cb856cf2"

OWNED_PATHS=(
  "Scripts/fixtures/zc-052-002-local-database-actions.json"
  "Scripts/qa-zc052002-local-database-actions-ax-probe.swift"
  "Scripts/qa-zc052002-local-database-actions-fixture.sh"
  "Scripts/qa-zc052002-signed-preflight.sh"
  "Scripts/verify-zc-052-002-local-database-actions-static.sh"
  "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift"
  "Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift"
  "Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift"
  "docs/ZC-052-002-SIGNED-QA-RUNBOOK.md"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

normalized_lines() {
  sed '/^$/d' | LC_ALL=C sort -u
}

assert_contains() {
  local file="$1"
  local text="$2"
  rg -Fq "$text" "$ROOT/$file" || fail "missing required contract in $file: $text"
}

verify_scope() {
  local expected actual tooling
  [[ "$(git -C "$ROOT" rev-parse "HEAD^")" == "$PRODUCT_CANDIDATE" ]] \
    || fail "tooling tip must descend directly from the reviewed product candidate"
  [[ "$(git -C "$ROOT" rev-parse "$PRODUCT_CANDIDATE^")" == "$BASE" ]] \
    || fail "reviewed product candidate must descend directly from canonical base"
  [[ -z "$(git -C "$ROOT" rev-list --min-parents=2 "$BASE..HEAD")" ]] \
    || fail "candidate lineage contains a merge commit"
  expected="$(printf '%s\n' "${OWNED_PATHS[@]}" | normalized_lines)"
  actual="$(git -C "$ROOT" diff --name-only "$BASE..HEAD" | normalized_lines)"
  [[ "$actual" == "$expected" ]] || fail "candidate differs from the exact nine-file owned scope"
  tooling="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r HEAD | normalized_lines)"
  [[ "$tooling" == "$(printf '%s\n' \
    Scripts/fixtures/zc-052-002-local-database-actions.json \
    Scripts/qa-zc052002-local-database-actions-ax-probe.swift \
    Scripts/qa-zc052002-local-database-actions-fixture.sh \
    Scripts/qa-zc052002-signed-preflight.sh \
    Scripts/verify-zc-052-002-local-database-actions-static.sh \
    docs/ZC-052-002-SIGNED-QA-RUNBOOK.md | normalized_lines)" ]] \
    || fail "tooling commit contains product or unrelated files"
  [[ -z "$(git -C "$ROOT" status --porcelain=v1 --untracked-files=all)" ]] \
    || fail "candidate worktree is not clean"
}

run_self_test() {
  [[ "${#OWNED_PATHS[@]}" == 9 ]] || fail "owned scope count changed"
  [[ "$(printf '%s\n' "${OWNED_PATHS[@]}" | normalized_lines | wc -l | tr -d ' ')" == 9 ]] \
    || fail "owned scope contains duplicates"
  ! printf '%s\n' "${OWNED_PATHS[@]}" | rg -qi '(tracker|registry|backlog|\.lavish)' \
    || fail "protected path entered owned scope"
  "$ROOT/Scripts/qa-zc052002-local-database-actions-fixture.sh" --self-test >/dev/null
  swift "$ROOT/Scripts/qa-zc052002-local-database-actions-ax-probe.swift" --self-test >/dev/null
  "$ROOT/Scripts/qa-zc052002-signed-preflight.sh" --self-test >/dev/null
  echo "PASS: ZC-052-002 static verifier scope and nested self-tests"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

cd "$ROOT"
verify_scope

assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" 'statusLabel = "READ-ONLY SAFETY"'
assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" 'statusLabel = "ACTIONS UNAVAILABLE"'
assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" '"Plan, start, pause, switch, complete, or reschedule tasks"'
assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" '"Save settings, coaching responses, or gaming adjustments"'
assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" '"Correct, note, skip, or confirm a review"'
assert_contains "Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift" 'No database repair or deletion is performed by this check.'
assert_contains "Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift" 'source-health.local-database.retry'
assert_contains "Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift" 'It does not repair, migrate, or delete the database.'
assert_contains "Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift" 'func readableOutdatedSchemaExplainsReadOnlySafetyAndRestartRecovery()'
assert_contains "Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift" 'func unavailableStorageNamesBlockedActionsAndOffersANonDestructiveRetry('
assert_contains "Scripts/qa-zc052002-local-database-actions-fixture.sh" 'restored exact original database bundle bytes'
assert_contains "Scripts/qa-zc052002-local-database-actions-ax-probe.swift" 'private database fixture content leaked through Accessibility'
assert_contains "docs/ZC-052-002-SIGNED-QA-RUNBOOK.md" 'Do not mark ZC-052-002 fully usable'

expected_schema="$(jq -r '.expectedSchemaVersion' Scripts/fixtures/zc-052-002-local-database-actions.json)"
source_schema="$(sed -nE 's/.*currentVersion = ([0-9]+).*/\1/p' Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift | head -n1)"
[[ "$expected_schema" == "$source_schema" ]] \
  || fail "fixture schema $expected_schema differs from product schema $source_schema"

swiftc -parse \
  Sources/ZoidCoachApp/LocalDatabaseAvailabilityPresentation.swift \
  Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift \
  Tests/ZoidCoachAppTests/LocalDatabaseAvailabilityPresentationTests.swift
swiftc -parse Scripts/qa-zc052002-local-database-actions-ax-probe.swift
swift test --filter LocalDatabaseAvailabilityPresentationTests
swift test --skip-build --filter LocalSystemDiagnostics
git diff --check "$BASE..HEAD"
run_self_test
echo "PASS: ZC-052-002 product copy, UI wiring, focused tests, fixture safety, AX privacy, and exact lineage"
