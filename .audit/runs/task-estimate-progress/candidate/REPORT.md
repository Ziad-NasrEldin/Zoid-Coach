# Task Estimate Progress Candidate Evidence

## Scope

This batch implements ZC-018-001, ZC-018-003, and ZC-037-004.
The batch remains isolated from the authoritative tracker, registry, Lavish artifact, root branch, release build, and installed runtime.

## End-to-end behavior

An active or paused primary focus now shows tracked minutes and estimated minutes together.
The same progress is visible on the corresponding active or paused Today task row.
The progress bar is bounded visually while its factual percentage can exceed 100 percent.
The status states are Not started, remaining time in estimate, Estimate reached, and minutes over estimate.
The language describes elapsed time without judging the user or treating an estimate as a deadline.
Every progress surface has one complete accessibility summary and a stable accessibility identifier.
Ready, completed, blocked, deferred, and rescheduled rows do not show a misleading live-progress bar.

## Persistence and recovery

The view derives progress from the canonical `TodayTaskRow.elapsedMinutes` and `TodayTaskRow.estimateMinutes` snapshot fields.
Elapsed time remains owned by `TaskExecutionStore` activity intervals and the estimate remains owned by the persisted daily plan.
No duplicate progress persistence or migration was added.
The focused restart test starts a task, closes the store, reopens the same SQLite database, reconstructs 25 elapsed minutes, and produces the same 42 percent progress state.
Defensive normalization prevents corrupt negative elapsed values or a zero estimate from causing invalid percentages or geometry.

## Focused verification

`swift test --filter TaskEstimateProgress` passed five Swift Testing scenarios on 2026-07-13.
The tests cover not-started, underway, nearing-estimate, reached-estimate, over-estimate, invalid persisted inputs, and database reopen recovery.
`swift build --target ZoidCoachApp` passed on 2026-07-13.
`git diff --check` passed on 2026-07-13.

## Remaining acceptance boundary

This candidate requires independent verification after rebasing onto the final authoritative integration tip.
The tracker statuses must not change until verification confirms the built app and interactive Today surfaces.
