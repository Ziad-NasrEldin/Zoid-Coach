# Unfinished Daily Review Resume Candidate

## Scenarios

- `ZC-040-005` - Resume an unfinished review after restarting the app.
- `ZC-053-008` - Restart with an unfinished review and resume it.

## Implemented Behavior

- The review store discovers the most recently edited review that has not been confirmed.
- Discovery uses the persisted canonical database, so the unfinished state survives app and store reconstruction.
- Daily Review shows an in-progress notice when the unfinished review is already selected.
- Daily Review shows an explicit Resume action when the unfinished review belongs to another day.
- Resume selects the saved source day, reloads its persisted sessions and corrections, and confirms restoration to the user.
- Confirming the review removes it from unfinished-review discovery.
- Every Daily Review mutation refreshes the resume state so the notice remains accurate without another app launch.

## Focused Verification

- `swift test --package-path /private/tmp/zoid-666-impl-followup-e2e --filter DailyReviewTests`
- Result: passed on 2026-07-13.
- The restart-focused test creates a correction, reconstructs `DailyReviewStore` from the same database, proves both the unfinished marker and corrected classification survive, confirms the review, and proves the marker disappears.
- `git diff --check`
- Result: passed on 2026-07-13.

## Independent Verifier Plan

- Rebase or integrate the candidate onto the current authoritative root.
- Run the focused `DailyReviewTests` suite.
- Launch the built app with a disposable canonical database containing an unconfirmed corrected review.
- Open Daily Review on another day and verify the unfinished notice and Resume action are visible and accessible.
- Activate Resume and verify the source day and corrected session are restored.
- Quit and relaunch before confirmation and verify the prompt remains available.
- Confirm the restored review and verify the unfinished notice no longer appears after relaunch.
