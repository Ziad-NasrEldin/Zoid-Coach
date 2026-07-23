# Post-cap drift review candidate report

## Scope

This candidate implements `ZC-035-009` and `ZC-035-010` without changing the shared tracker or claiming full end-to-end acceptance.

## End-user behavior

When an otherwise eligible gaming-drift episode is suppressed because the local-day behavior prompt cap is already exhausted, Zoid 666 records the episode locally without creating another prompt or notification.

Repeated agent cycles update the same continuing session instead of adding duplicate review rows.

The Daily Review shows one restrained `PROMPT CAP REACHED` summary with the number of later episodes, total observed minutes, largest episode, and involved applications.

The review explains that the activity was recorded without another interruption and is shown only in the review.

No post-cap drift summary is added to Today, the menu bar, notifications, or Settings.

## Persistence

Migration 39 adds `quiet_drift_episodes` with one row per local day and gaming-session start epoch.

The first qualifying observation time is retained while the latest epoch and observed minutes advance idempotently.

The ledger stores application names and aggregate timing only, without window titles, URLs, screenshots, inferred intent, or moral labels.

## Focused proof

- The configured daily-cap journey produced two accountability prompts, suppressed a third distinct session, recorded one quiet episode, and updated that same row from ten to eleven minutes without duplication.
- The Daily Review loaded two quiet episodes into a factual aggregate, preserved application order, remained free of invented coaching prompts, survived store restart, and stayed scoped to the matching local day.
- Migration 39 applied alone over a version-38 database, accepted a valid ledger row, and the clean migration path applied all 39 migrations exactly once.
- The focused four-test command passed after the migration-version correction.
- The strengthened idempotent growth test passed independently after the final assertion change.
- `git diff --check` passed.

## Independent verifier plan

1. Rebase the candidate onto the latest authoritative root and resolve migration 39 if another additive migration landed first.
2. Run the focused migrator, gaming-drift, and Daily Review tests once on the rebased candidate.
3. Package and install one exact signed QA build under the serialized runtime lease.
4. Seed a completed baseline, an incomplete priority task, a cap of one, one delivered gaming prompt, and a later distinct eligible gaming session.
5. Confirm no second prompt or notification appears when the cap is exhausted.
6. Extend the same later session and confirm the ledger remains one row with increasing observed minutes.
7. Open the current-day Review through the signed UI and confirm the `PROMPT CAP REACHED` card is readable, factual, keyboard reachable, and absent from Today.
8. Restart the app and helper, reopen the same review, and confirm the summary is unchanged and no duplicate prompt was delivered.
9. Update tracker, registry, and Lavish only after the signed journey passes.

## Files

- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Sources/ZoidCoachCore/DailyReview.swift`
- `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
