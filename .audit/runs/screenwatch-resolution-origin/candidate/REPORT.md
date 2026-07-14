# ZC-049-003 Screenwatch Resolution Origin Candidate

## Scope

This candidate closes the durable resolution-origin gap for Screenwatch-driven gaming prompts.
It does not change prompt presentation, notification authorization, tracker status, or signed runtime state.

## Base and candidate

- Canonical base: `ac2fabda7d8231d7e7001c59af0bd9ab3536d20b`.
- Source candidate before evidence commit: `22c4e05`.
- Migration 44 remains the canonical Calendar plan operation ledger.
- Migration 45 adds nullable, constrained `resolution_origin` and `resolution_reason` columns to `prompt_episodes`.

## Behavior

- Explicit user dismissal persists `user` and `explicit_dismissal`.
- Screenwatch evidence withdrawal persists `system` and `screenwatch_evidence_invalid`.
- Only that exact system and reason pair is excluded from same-session deduplication, the daily intervention count, and the latest-created cooldown gate.
- Legacy rows with null resolution metadata remain conservative and continue to enforce session deduplication, cooldown, and daily caps.
- A later system reconciliation cannot relabel an already completed user dismissal.
- Existing missing, stale, future-dated, negative-age, 180-second boundary, 181-second boundary, unresolved prompt, and notification reconciliation behavior remains based on the same dismissed state.

## Exact source and test files

- `Sources/ZoidCoachCore/PromptInbox.swift`
- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Sources/ZoidCoachInfrastructure/PromptInboxStore.swift`
- `Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift`
- `Tests/ZoidCoachAppTests/BaselineObservationTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `Tests/ZoidCoachAppTests/PromptInboxTests.swift`

## Verification

- Focused five-test recovery contract: 5 of 5 passed.
- Relevant migration, PromptInbox, GamingDrift, and adjacent prompt suite: 79 of 79 passed.
- Release build: passed in 81.61 seconds.
- Swift syntax parsing: passed for the original seven changed Swift files before compilation.
- Diff whitespace validation: passed.

The broader suite found a stale assertion that expected schema version 38 in `BaselineObservationTests`.
The assertion now follows `AutonomousDatabaseMigrator.currentVersion`, its rebuilt focused test passed, and the final 79-test rerun passed.

## Durable evidence

- `focused-tests-skip-build-full.log` records the five focused tests.
- `relevant-suite-final-full.log` records the final 79-test pass.
- `release-build-full.log` records the release build.

## Risks and remaining E2E acceptance

- This candidate has no signed-app runtime evidence yet.
- A fresh verifier should install an exact signed package from the integrated candidate, seed one active gaming session and one unresolved prompt, make Screenwatch evidence invalid, and confirm the prompt and its pending or delivered notification are withdrawn.
- The verifier should restore fresh evidence for the same session and confirm exactly one replacement prompt appears despite a daily cap of one and an active cooldown.
- The verifier should explicitly dismiss that replacement, repeat the evidence invalidation and recovery cycle, and confirm no prompt returns because user dismissal still owns deduplication, cooldown, and cap semantics.
- The verifier should relaunch the app and helper between withdrawal and recovery to prove the origin and reason survive process restart.
- The verifier should inspect the local database only as supporting evidence after proving the user-visible flow.
