# External Apple Reminder Completion Verification

## Result

`ZC-021-002` is Partially implemented.

The backend lifecycle is durable, but the signed unplanned Today journey does not present the completion reason to the user.

## Automated proof

- `externallyCompletingActiveAppleReminderEndsSessionWithDurableReason` passed.
- `externalReminderCompletionReasonIsExplicitForTheUser` passed.
- One release package passed app and helper builds, package coherence, signing, and designated-requirement checks.
- The unrelated baseline test `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` still fails with `.write` and is recorded separately from this candidate.

## Signed journey

The isolated signed app opened Today at 1180 by 760 pixels and exposed 118 accessibility nodes before the task started.

The native controls started `qa-ready-task`, then started a 20-minute sprint.

An isolated source fixture marked the canonical Apple Reminder complete.

The synchronized database ended the active interval and sprint once at `2026-07-13T19:47:51Z`.

Exactly one Reminder-source completion history entry existed and no redundant completion command was queued.

After app relaunch, Today still loaded successfully with 120 accessibility nodes, but `taskRows` was empty.

The text `Ended because the Apple Reminder was completed` was absent at the top, middle, and bottom of the Today accessibility tree.

The fixture contained no second task, so signed continuity for another available task was not established.

## Acceptance decision

The planned-row focused test proves the intended reason and continuity behavior in code.

The common signed unplanned path silently removes the completed row, so an end user cannot understand why the active task ended.

This blocks Fully implemented and Frontend only left status.
