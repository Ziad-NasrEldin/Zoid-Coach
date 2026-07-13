# External Apple Reminder Completion Reason UI Candidate

## Scope

This candidate closes the remaining visible-copy gap for `ZC-021-002` without changing the tracker, registry, Lavish audit, or signed runtime fixtures.

## Implementation

- A completed Today row with a persisted completion reason now prefers that explicit reason over the generic Reminder synchronization status.
- An externally completed Reminder therefore displays `Ended because the Apple Reminder was completed` in the existing task-detail surface and its combined accessibility output.
- A normal local completion without a persisted external reason continues to display `Completed`.
- Existing persistence behavior remains responsible for carrying the completion source through refresh, relaunch, and source deletion.

## Focused proof

- `externalReminderCompletionReasonIsExplicitForTheUser` passed.
- `externallyCompletedReminderRowUsesExplicitReasonInsteadOfGenericCompletedCopy` passed.
- `ordinaryLocalCompletionKeepsGenericCompletedCopy` passed.
- `externallyCompletingUnplannedActiveReminderRestoresReasonWithoutPriorTodaySnapshot` passed.
- `completedThenDeletedReminderUsesDurableCompletionHistory` passed.
- `swift build -c release` passed.

## Acceptance boundary

Independent installed-app verification must still prove the exact visible and accessible phrase after external completion, relaunch, and source deletion before the authoritative scenario status changes.
