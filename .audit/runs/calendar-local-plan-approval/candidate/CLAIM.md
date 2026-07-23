# Calendar Local Plan Approval Claim

## Scope

- Scenario: `ZC-046-009`, Continue using Zoid 666 while offline.
- Backlog slice: meeting-aware planning and Calendar boundaries.
- Base: authoritative `07ffb22`.
- Branch: `codex/calendar-local-plan-approval`.
- Worktree: `/private/tmp/zoid-666-calendar-local-plan-approval`.

## Owned files

- `Sources/ZoidCoachApp/CalendarPlanApprovalState.swift`
- `Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Tests/ZoidCoachAppTests/CalendarPlanApprovalStateTests.swift`
- `.audit/runs/calendar-local-plan-approval/candidate/CLAIM.md`
- `.audit/runs/calendar-local-plan-approval/candidate/REPORT.md`
- `docs/impl/666-BACKLOG.md`

## Acceptance

When Calendar availability cannot be read, the end user can deliberately accept the reviewed local plan without requesting Calendar or Reminder writes.
The app persists a truthful zero-write receipt, restores the same reviewed tasks after restart, and retains the existing Calendar repair path.
Tracker, registry, Lavish, packaging, and installed runtime are outside this candidate lane.
