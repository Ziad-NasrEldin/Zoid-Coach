# Reminder reschedule sync claim

This isolated lane starts from authoritative commit `c885dc7`.

The higher ready onboarding and notification items require signed runtime verification, schedule onboarding is already delivered, and the remaining gaming-policy work overlaps active Settings policy files.

This lane claims the first not-implemented task-lifecycle scenario that is disjoint from the menu-bar Start files.

## Scenario

- `ZC-020-009` - See a clear pending-sync warning if rescheduling fails.

## Owned files

- Reschedule mutation command only in `Sources/ZoidCoachCore/AgentMutationCommand.swift`.
- Reschedule sync presentation state only in new `Sources/ZoidCoachCore/ReminderRescheduleSyncState.swift`.
- Explicit reschedule enqueue only in `Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift`.
- Reschedule mutation and sync-state composition only in `Sources/ZoidCoachApp/AppModel.swift`.
- Reschedule sync ledger and reschedule-sheet copy only in `Sources/ZoidCoachApp/Views/DashboardView.swift`.
- Focused new reschedule sync tests and narrow affected router tests.
- Candidate evidence under `.audit/runs/reminder-reschedule-sync/candidate/`.

## Boundaries

This lane does not touch root, runtime installation, tracker, registry, backlog, Lavish, menu-bar, shared action execution, completion sync, or unrelated Dashboard controls.

The local deferral remains durable even when Apple Reminders rejects the due-date write.

The UI must distinguish queued, retrying, rejected, unavailable, and confirmed source states without claiming success early.
