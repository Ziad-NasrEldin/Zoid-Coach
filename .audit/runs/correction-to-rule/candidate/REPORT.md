# Correction-to-rule candidate evidence

## Scope

This batch implements the missing adaptation half of ZC-064-010.
It lets a person correct a daily-review session and deliberately apply that app classification to future Screenwatch activity.

## End-user behavior

- Each activity-session row offers an explicit "Use this app classification for future activity" control.
- The preview names the app, target classification, replacement behavior, and the promise that historical observations remain unchanged.
- Work, Gaming, and Distracting can become future app rules.
- Idle and Unknown remain observation states and cannot become unsafe lasting defaults.
- Applying the correction and future rule is one local database transaction.
- An active rule is visible beside every matching app session.
- Reviews includes an always-visible future-rules ledger, so a rule can be found and removed even when the selected day no longer contains its source app.
- A replacement is append-only and takes effect only for observations at or after its effective time.
- Removing a rule uses a confirmation dialog and an append-only tombstone.
- Removal restores the normal Settings policy for future observations while preserving prior corrections and already-ingested classifications.
- Stable accessibility identifiers cover the toggle, preview, active state, remove action, and apply action.

## Persistence and recovery proof

- Migration 34 adds the append-only app_classification_correction_rules event table and ordered lookup index.
- Restart proof reopens DailyReviewStore, recovers the latest rule, and preserves the corrected historical session.
- Replacement proof records two rule events and resolves the latest event without mutating the first.
- Removal proof records a third tombstone event, hides the rule from the current-rule list, and leaves the historical correction unchanged.
- Invalid future classifications fail before the transaction writes either a correction or a rule.
- Screenwatch proof ingests one observation after rule activation as Work, removes the rule, ingests another observation as the normal Unknown policy result, and retains the first observation as Work.

## Commands

- swift test --filter "(futureClassificationRule|reviewCorrectionRule|migration34)"
- swift test --filter migration
- swift test --filter DailyReview
- swift test --filter ScreenwatchArchive
- git diff --check

All focused commands passed.

## Shared-gate boundary

The source-write recovery lane owned the repository-wide full-suite, release-build, and signed-QA runtime leases while this candidate was built.
This lane did not contend for those shared gates.
A fresh verifier should run the visible signed-QA correction, replacement, relaunch, future-ingestion, and removal journey after integration.
