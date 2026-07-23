# Daily review deferral candidate report

## Scope

This candidate implements `ZC-040-004` without changing the authoritative tracker, registry, Lavish report, runtime fixtures, Today dashboard, or QA ready-state tooling.

## User behavior

An unfinished Review now offers `REVIEW TOMORROW` beside Confirm and Skip.
Choosing it persists a future deferral and explains that every local activity record, task outcome, correction, and note remains available.
The unfinished-review banner stays quiet before the due time, including after restart.
After the due time, the exact saved review returns automatically without requiring a migration or manual repair.
The Review page shows the deferred-until time and offers `RESUME REVIEW NOW` for an early return.
Confirm and Skip clear any outstanding deferral.

## Automated proof

- `swift test --filter "deferredReviewKeepsEvidenceHiddenUntilDueAndReturnsAfterRestart|deferredReviewCanBeResumedEarlyAndRejectsPastDates|dailyReviewControllerExplainsDeferralAndRestoresTheReviewOnResume|migration42AddsRestartSafeDailyReviewDeferral"` passed with four tests.
- `swift build -c release` passed.
- `git diff --check` passed.

The focused persistence journey creates observed activity, saves a classification and task correction, defers the review, restarts the store before the due time, and verifies that the prompt remains quiet while the corrected evidence is unchanged.
It restarts again after the due time and verifies that the review returns with the same correction.
A separate journey proves future-time validation and early Resume, while the controller test proves the user-facing success copy and state transition.
Migration proof upgrades a version-41 daily review row to the nullable version-42 deferral field without changing the row.

## Remaining acceptance

A fresh verifier must use Review Tomorrow in the signed installed app, relaunch before and after the due boundary, inspect the preserved corrections and notes, exercise Resume Now, and confirm stable focus and accessibility before the authoritative tracker advances.
