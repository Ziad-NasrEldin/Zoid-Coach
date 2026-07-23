# External Reminder Completion Reason UI Verification

`ZC-021-002` remains Partially implemented.

The candidate UI mapping passed its five focused regression tests and one signed QA release package.

The isolated signed runtime did not reach the externally completed task state required for end-user acceptance.

## Automated proof

- `externalReminderCompletionReasonIsExplicitForTheUser` passed.
- `externallyCompletedReminderRowUsesExplicitReasonInsteadOfGenericCompletedCopy` passed.
- `ordinaryLocalCompletionKeepsGenericCompletedCopy` passed.
- `externallyCompletingUnplannedActiveReminderRestoresReasonWithoutPriorTodaySnapshot` passed.
- `completedThenDeletedReminderUsesDurableCompletionHistory` passed.
- One QA release package passed app and helper builds, package coherence, signing, LaunchAgent, and Mach-service validation.

## Signed runtime checkpoint

- A fresh isolated two-task ready-state opened Today in a non-minimized 1180 by 760 window.
- Native accessibility controls started `qa-ready-task` and the canonical database recorded exactly one open interval.
- The isolated fixture consumed an exactly-once seed that marked `qa-ready-task` complete while leaving `qa-next-task` available.
- The installed signed app was relaunched once and Today reopened healthy with 126 accessibility nodes.
- The helper did not synchronize the completed fixture record into canonical `source_tasks` before the hard runtime cap.
- Canonical `source_tasks` still recorded `qa-ready-task` with `is_completed = 0`.
- The task interval remained open and history contained only its earlier `selected` entry.

## Acceptance decision

The runtime never created an externally ended Today row, so the exact label `Ended because the Apple Reminder was completed` could not be verified in the installed app.

This is a signed runtime-harness synchronization blocker rather than an observed failure of the candidate UI mapping.

The scenario cannot be promoted until a later signed run reaches the externally completed canonical state and proves the exact label, ordinary local `Completed` copy, durable deletion and relaunch persistence, one history entry, no duplicate completion command, and a usable next task.
