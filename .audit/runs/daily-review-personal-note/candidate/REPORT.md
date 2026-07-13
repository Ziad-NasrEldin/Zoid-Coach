# Daily Review Personal Note Candidate Report

Scenario: `ZC-042-008`.

Candidate status: implementation complete and ready for independent signed review verification.

## End-User Journey Implemented

- Every daily review now includes a dedicated Personal note editor.
- The copy states that the note remains local and is not treated as observed behavior, a hypothesis, or a learned fact.
- The user can add, update, or clear one note of up to 1,000 characters for the selected day.
- Notes are trimmed before persistence and empty notes are stored as absent rather than blank data.
- Saving a note reopens a previously confirmed review so the updated review must be confirmed deliberately.
- The note persists across day changes, restart, and unfinished-review restoration.
- Saving or clearing a note never changes behavior observations, totals, corrections, or offline-work entries.
- Stable accessibility identifiers cover the section, editor, and save action.
- Migration 40 adds the bounded nullable field without rewriting existing review rows.

## Focused Proof

- `swift test --filter personalReviewNoteTrimsPersistsReopensAndClearsWithoutChangingEvidence` passed on 13 July 2026.
- `swift test --filter migration40AddsBoundedPersonalReviewNoteWithoutChangingExistingRows` passed on 13 July 2026.
- Focused proof covers trimming, persistence, relaunch, clearing, review reopening, evidence preservation, length rejection, and existing-row migration.
- The debug test build compiled the changed Core, infrastructure, app, and tests.
- `swift build -c release` passed on 13 July 2026.

## Independent Verifier Plan

1. Open a populated signed-QA daily review and record the observed and actual totals.
2. Add a personal note, save it, and verify the local-only boundary copy remains visible.
3. Confirm the review, edit the note, and verify the review reopens for confirmation.
4. Change review days and return to verify the exact note is restored only for its source day.
5. Relaunch and verify the note and unfinished-review state remain durable.
6. Clear the note and verify the section returns to an empty editor without changing any totals.
7. Enter more than 1,000 characters and verify saving is blocked without data loss.

The tracker and registry should not promote this scenario until the signed add, edit, confirm, relaunch, clear, and evidence-preservation sequence passes.
