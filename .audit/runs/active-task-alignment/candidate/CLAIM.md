# Active-task time comparison claim

This isolated lane starts from authoritative commit `b31b45d685850bcddbab5f269999f8462b231b32`.

## Scenario

- `ZC-024-008` - See active-task elapsed time separately from aligned time.

## Owned files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardTests.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift`
- `.audit/runs/active-task-alignment/candidate/*`
- The matching delivered-batch entry in `docs/impl/666-BACKLOG.md`

This lane adds a truthful active-focus comparison between cumulative task elapsed time and Screenwatch-observed work-classified time from the current active session.
It explicitly states that observed alignment is a signal rather than proof that the activity matched the task.
It does not touch Settings, gaming drift, Daily Review, the tracker, registry, Lavish, runtime, or root integration.
