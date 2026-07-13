# Local task reschedule confirmation claim

This isolated lane starts from authoritative commit `8435671`.

Higher ready work requires serialized runtime proof or overlaps configurable intentional-override settings/runtime, so this disjoint lane continues priority 14.

## Scenarios

- `ZC-020-008` - Reschedule a task only after confirming the new date.
- `ZC-034-010` - Reschedule the task.

## Owned files

- `Sources/ZoidCoachApp/TaskRescheduleState.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/TaskRescheduleStateTests.swift`
- `.audit/runs/task-reschedule-date/candidate/*`
- The isolated backlog claim and handoff rows only.

This lane implements an explicit future-date review before changing the local daily plan and clearly separates that local plan move from Apple Reminder due-date synchronization.
It will not touch intentional-override settings/runtime, shared runtime, tracker, registry, or Lavish.
