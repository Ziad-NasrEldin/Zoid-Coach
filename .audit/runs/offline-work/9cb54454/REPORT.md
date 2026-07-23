# Away-from-Mac Work Independent Acceptance

## Verified revision

- Verifier branch: `codex/offline-work-verify`.
- Verified implementation and validation tip: `9cb54454c4518d480193bfc6d46f57a0f2832dc8`.
- Signed QA root: `/private/tmp/zoid-666-offline-verify-9cb5445`.
- Installed application: `/private/tmp/zoid-666-offline-apps/Zoid 666 QA E2E.app`.

## Visible signed-QA journey

The signed application launched with its QA LaunchAgent registered from the installed app bundle.
Reviews initially showed 0 minutes for Actual Time, Screenwatch-observed, and Away from Mac.
The Add button remained disabled while both task and note were blank.
Entering task `Research proposal` and note `Client workshop` enabled Add.
Adding the default 30-minute entry changed Actual Time and Away from Mac to 30 minutes while Screenwatch-observed remained 0 minutes.
The entry appeared once with its task, note, start time, duration, Edit control, and Remove control.
Editing the same entry from 30 to 45 minutes recalculated Actual Time and Away from Mac to 45 minutes without creating a duplicate.
Terminating and reopening the signed application preserved the single corrected 45-minute entry, task, note, and separated totals.
The Remove control opened a scoped confirmation stating that only the intentional offline-work record would be removed and Screenwatch observations would remain unchanged.
The final destructive click was not issued through Computer Use because local UI deletion requires action-time user confirmation.
The store deletion test independently passed and proves that removal deletes only the selected offline entry while retaining behavior observations.

## Validation and privacy

The store rejects durations outside 1 minute through 24 hours.
The store and UI now reject blank task-plus-note input, task text over 200 characters, and note text over 1,000 characters.
The visible helper copy explains that a task or note distinguishes intentional work from missing telemetry.
The visible review copy states that missing telemetry is never inferred as work.
Window titles, URLs, screenshots, and other sensitive behavior fields were absent from the review surface.
The offline section, inputs, separated totals, Edit, Remove, validation text, and confirmation were exposed through the accessibility tree.

## Persistence and migration proof

Migration 30 is append-only after migrations 28 and 29.
The migration creates `offline_work_entries` with a positive bounded duration constraint and a day/start index.
Fresh migration tests passed for versions 27 through 30 without changing existing behavior evidence.
Create, idempotent update, restart read, review reopening, and scoped delete tests passed.

## Verification gates

- Focused DailyReview suite: 8 tests passed.
- Focused ordered migration suite: 9 tests passed.
- Candidate ordinary full Swift suite: 469 tests passed in 26.513 seconds.
- Fresh verifier full Swift attempts compiled successfully but the SwiftPM Testing helper twice remained idle on the main run loop after test execution started, including one exclusive four-worker run, so they were terminated without claiming a fresh full-suite result.
- Python scenario and evidence suite: 41 tests passed.
- Registry validation: exactly 666 scenarios with no tracker drift before the tracker update.
- Fresh release build: passed in 54.05 seconds.
- Signed-QA package, deep signing, package identity, LaunchAgent, and Mach service coherence: passed.

## Scenario disposition

- `ZC-022-003` through `ZC-022-007` are fully implemented and independently accepted.
- `ZC-022-001` and `ZC-022-002` remain not implemented because the active-task surface still has no away-from-Mac entry flow.
