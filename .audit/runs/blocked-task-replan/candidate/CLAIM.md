# Blocked-task replan claim

## Baseline

- Authoritative baseline: `292f34f`
- Branch: `codex/fresh-after-notification-preference`
- Worktree: `/private/tmp/zoid-666-fresh-after-notification-preference`

## Scenarios

- `ZC-019-010` - Replan after an important task becomes blocked.
- `ZC-034-011` - Mark the task blocked.

## Claimed files

- `Sources/ZoidCoachInfrastructure/AutonomousPlanStore.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift`
- `.audit/runs/blocked-task-replan/candidate/*`

This lane will preserve the user's blocker reason, durably replace a blocked main objective with the next usable planned commitment, and explain the resulting plan change in Today.
It will not touch notification preference policy or coordination, Settings, shared runtime, tracker, registry, backlog, or Lavish.
