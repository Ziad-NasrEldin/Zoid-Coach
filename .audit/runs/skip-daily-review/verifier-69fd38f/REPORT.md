# ZC-040-006 Skip Review verification

## Scope

This verifier started from authoritative commit `69fd38fcbb4969063abe1532d5dbaae9ad733cd8` in a fresh isolated worktree.
The canonical scenario registry still labels `ZC-040-006` as `Not implemented`, but that label does not reflect the implementation already present in this commit.

## Static end-user behavior inspection

The Review screen visibly offers `SKIP REVIEW` only while the selected review is neither deferred, skipped, nor confirmed.
Activating it opens a destructive confirmation titled `Skip this daily review?`.
The confirmation explains that no review conclusions will be confirmed and that local activity, corrections, and notes remain available.
The dialog provides both `SKIP REVIEW AND CLOSE DAY` and `KEEP REVIEW OPEN` actions.
The Skip button has the stable accessibility identifier `reviews.skip` and an accessibility hint that describes the confirmation and consequence.
After a successful skip, the Review screen displays a dated `SKIPPED` state with the stable accessibility identifier `reviews.skipped`.
The skipped-state copy explains that the day is closed without confirmed conclusions, evidence and corrections remain available, and a later edit reopens the review.

## Persistence inspection

The store saves skip and confirmation as mutually exclusive outcomes.
Skipping clears any prior deferral, which prevents a deferred review from returning later.
Unfinished-review discovery excludes skipped reviews.
Edits to review evidence or the personal note clear the skipped state and place the review back in the unfinished queue.
The existing focused test proves corrected evidence survives skip and store reconstruction, the unfinished prompt stays cleared, and a later personal-note edit reopens the review.

## Additional focused proof

The verifier added `repeatedSkipClearsDeferralWithoutLosingReviewEvidenceAcrossRestart` to `Tests/ZoidCoachAppTests/DailyReviewTests.swift`.
The test exercises a review with a correction, task attachment, personal note, and active deferral.
It invokes Skip twice and requires a stable skipped outcome, no confirmation, no deferral, preserved evidence, no unfinished prompt, and the same outcome after reconstructing the store.

## Verification state

The first baseline test build reached app linking but failed in Apple's code-signing subsystem while the volume had approximately 545 MiB free.
The focused test then compiled, but package-test linking failed with `ld: write() failed, errno=28 (No space left on device)`.
The verifier removed only this worktree's generated `.build` directory and recovered approximately 358 MiB.
After the volume recovered above the orchestrator's 2 GiB rebuild threshold, `swift test --filter repeatedSkipClearsDeferralWithoutLosingReviewEvidenceAcrossRestart` passed.
The full `swift test --filter DailyReviewTests` selection passed.
The `swift build -c release` build completed successfully.
No assertion failure or product-code build failure was observed.

## Classification

The exact current canonical status is `Not implemented`, and its audit note is stale.
The recommended implementation status is `Touches remaining` because the complete visible and persisted path and green deterministic build proof are present, while this fresh verifier still needs signed installed end-to-end proof.
The scenario must not be promoted to `Fully implemented` until the signed installed app proves visible Skip and Cancel behavior, the dated skipped state, evidence preservation, correct return to Today, app and helper relaunch persistence, non-resurrection of the unfinished or deferred prompt, and later-edit reopening.

## Remaining steps

Acquire the serialized signed-runtime lease and execute the installed Review journey without modifying shared runtime state outside that lease.
