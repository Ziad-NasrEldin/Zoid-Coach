# Active-task context claim

## Baseline

- Authoritative baseline: `f46cad3`
- Branch: `codex/fresh-after-time-zone`
- Worktree: `/private/tmp/zoid-666-fresh-after-time-zone`

## Scenarios

- `ZC-018-004` - See whether the current computer context appears aligned, uncertain, or mismatched.
- `ZC-018-005` - Read neutral alignment language rather than judgmental productivity labels.

## Claimed files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardTests.swift`
- `.audit/runs/active-task-context/candidate/*`

This lane will derive an honest active-task context assessment from the freshest classified Screenwatch observation, preserve uncertainty when evidence is absent or stale, and show neutral end-user copy in Today.
It will not touch Settings, shared runtime, tracker, registry, backlog, or Lavish.
