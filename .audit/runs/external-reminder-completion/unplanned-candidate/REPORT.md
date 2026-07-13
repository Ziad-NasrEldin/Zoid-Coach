# Unplanned External Reminder Completion Candidate

## Scope

This candidate addresses `ZC-021-002` without changing tracker status.

It closes the signed usability gap where an unplanned active task could disappear after its Apple Reminder was completed externally.

## Root cause

The completion lifecycle could preserve a visible row only when a previous Today snapshot still contained that task.

If execution state survived but the prior Today row did not, the agent completed the backend interval without enough row metadata to present the durable completion reason.

## Change

`ReminderSnapshotStore` can now load the retained source record for one identifier, including completed records.

`TodayDashboardAgent` uses that source record to distinguish completion from deletion, preserve the source title, close the active execution, and reconstruct one completed row with `appleReminderCompleted` when no previous Today row exists.

The completed row is saved in the canonical Today snapshot and remains visible after agent restart.

A Reminder-source completion history entry observed after the active interval began is also treated as a durable completion tombstone.

This prevents a completed Reminder that is deleted before Today refresh from being mislabeled as deleted.

Today does not insert a second completion history row when EventKit synchronization already recorded that completion.

## Verification

- The new regression test failed before the implementation because `completed.taskRows` was empty.
- `externallyCompletingUnplannedActiveReminderRestoresReasonWithoutPriorTodaySnapshot` now passes.
- `externallyCompletingActiveAppleReminderEndsSessionWithDurableReason` continues to pass.
- `externallyCompletedReminderHistoryIsNotRecordedTwiceByTodayRefresh` passes.
- `completedThenDeletedReminderUsesDurableCompletionHistory` passes.
- `swift build -c release` passes.

## Remaining acceptance

A verifier should cherry-pick this candidate onto the latest authoritative root and repeat the signed ready-state journey.

The expected visible result is one stopped completed row with `Ended because the Apple Reminder was completed` after refresh and relaunch while another eligible Reminder remains usable.
