# Skip daily review candidate report

## Scope

This candidate implements `ZC-040-006` without changing the authoritative tracker, scenario registry, Lavish report, runtime fixtures, Today task lifecycle, or notification Settings.

## User behavior

An unconfirmed Daily Review now offers `SKIP REVIEW` beside confirmation.
The action opens a destructive confirmation that explains no conclusions will be confirmed and that local activity, corrections, and notes remain available.
After approval, the review shows a dated `SKIPPED` state and the unfinished-review prompt clears.
Skipping never uses the confirmed timestamp and never deletes evidence.
A later correction or personal-note edit clears the skipped state and returns the review to the unfinished queue.

## Persistence

Migration 41 adds the nullable `skipped_at_utc` field without rewriting review or behavior evidence.
The store saves confirmation and skipping as mutually exclusive outcomes.
The skipped outcome survives a new store instance and remains excluded from unfinished-review discovery until a later edit reopens it.

## Automated proof

- `swift test --filter skippedReviewClosesDayWithoutLosingEvidenceAndLaterEditReopensIt` passed.
- `swift test --filter DailyReviewTests` passed.
- `swift build -c release` passed.
- `git diff --check` passed.

The focused journey corrects an observed session, verifies the unfinished prompt, skips the review, and confirms the correction remains while confirmation stays empty.
It restarts the store, verifies the same skipped time and evidence, then edits the personal note and confirms the review reopens with its evidence intact.

## Remaining acceptance

A fresh verifier must exercise Cancel and Skip through the signed installed Review UI.
The verifier must confirm the visible skipped state, missing unfinished banner after relaunch, preserved evidence, and later-edit reopening before the authoritative tracker advances.
