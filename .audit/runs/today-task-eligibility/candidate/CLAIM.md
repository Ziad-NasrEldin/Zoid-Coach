# Today task eligibility claim

## Baseline

- Authoritative baseline: `4b1960b`
- Branch: `codex/today-task-eligibility`

## Scenarios

- `ZC-007-001` - See incomplete Reminders due today.
- `ZC-007-002` - See overdue incomplete Reminders.
- `ZC-007-005` - Carry a task without a due date into today.
- `ZC-007-006` - Avoid seeing future tasks that were not selected for today.

## Files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift`
- Candidate evidence under `.audit/runs/today-task-eligibility/candidate/`.

## Boundaries

This lane does not touch Daily Review, learned-rule reset, prompt actions, tracker, registry, Lavish, root, or runtime installation.
