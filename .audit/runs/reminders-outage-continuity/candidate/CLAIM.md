# Reminders outage continuity claim

This isolated lane starts from authoritative commit `5ae9b32`.

Priority 4 requires the serialized signed runtime, so this non-runtime implementation lane pulls priority 5.

## Scenarios

- `ZC-051-001` - Continue manual planning after Reminders access is denied or revoked.
- `ZC-051-004` - Keep local estimates, active sessions, and plan state while sync is unavailable.

## Owned files

- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachApp/RemindersContinuityState.swift`
- `Tests/ZoidCoachAppTests/RemindersOutageContinuityTests.swift`
- `.audit/runs/reminders-outage-continuity/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will make outage continuity explicit in Today and prove that a denied or failed Reminders refresh does not erase the local plan, estimate, active session, or locally created work across restart.
It will not touch gaming policy, EventKit production state, the shared runtime, tracker, registry, or Lavish artifact.
