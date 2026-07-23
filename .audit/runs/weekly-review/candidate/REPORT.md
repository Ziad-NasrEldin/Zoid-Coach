# Weekly Review Candidate Evidence

## Scope

This batch implements `ZC-043-001` through `ZC-043-016` and advances the durable coverage prerequisite in `ZC-063-008`.

`ZC-054-005` is intentionally excluded because truthful automatic weekly reminder delivery requires the serialized background-agent scheduling seam.

## End-User Journey

- The existing Reviews destination now includes a Weekly Review directly after the selected Daily Review.
- The review always describes the previous completed calendar week, so its dates and one-experiment identity remain stable throughout the following week.
- Fewer than three confirmed days with 30 minutes of observable coverage produces only a data-quality summary and never a strong conclusion or experiment.
- Sufficient coverage shows planned tasks, completed plan items, planned focused minutes, and an outcome rate explicitly labelled as not being a productivity score.
- Available estimate, best-work-window, corrected drift, gaming-budget, prompt follow-through, recovery uncertainty, and repeated-blocked-task patterns show sample size, date range, privacy-safe examples, confidence, and an alternative explanation.
- Daily Review classification corrections are consumed before drift and gaming minutes are aggregated.
- Exactly one experiment can exist for a review week.
- The user can edit, accept, or reject that experiment.
- Accepted experiments preserve their edited text and show next-week progress after app or store restart.

## Persistence And Migration

- Migration 31 adds only `weekly_review_experiments` and its tracking index.
- The table enforces one row per review week, bounded non-empty text, explicit proposed, accepted, or rejected state, and optional tracking-week start.
- Migration tests preserve daily reviews and prove that a duplicate experiment for the same week is rejected.

## Automated Proof

- `swift test --filter WeeklyReview` passes five focused tests.
- `swift test --filter AutonomousDatabaseMigrator` passes the focused migration suite.
- The tests cover limited evidence, sufficient evidence, outcomes, transparent patterns, one-experiment idempotency, correction-aware drift, validation, edit, accept, reject, tracking progress, and restart persistence.
- `git diff --check` passes.

## Pending Independent Acceptance

- The root-owned full-suite and runtime lease prevented this lane from running the final full Swift suite, release build, or signed-QA click-through concurrently.
- A fresh verifier must run the full suite and release build, seed limited and sufficient weekly fixtures, open Reviews in the signed QA app, inspect evidence expansion, edit and accept the one experiment, relaunch, confirm tracking, reject it, and confirm the rejected state after another relaunch.
- The authoritative tracker, registry, and Lavish report remain untouched until that independent acceptance passes.
