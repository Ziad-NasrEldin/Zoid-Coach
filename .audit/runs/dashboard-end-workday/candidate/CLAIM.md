# Dashboard end-workday claim

This isolated lane starts from authoritative commit `adb226b`.

The higher ready onboarding and notification items require signed runtime verification, schedule onboarding is already fully delivered, and the remaining gaming-policy slice overlaps the active Settings policy surface.

This lane therefore claims the first coherent not-implemented end-user action that is disjoint from the default-pause Settings and menu-bar files.

## Scenario

- `ZC-013-010` - End the workday from the dashboard.

## Owned files

- Dashboard end-workday presentation only in `Sources/ZoidCoachApp/Views/DashboardView.swift`.
- Dashboard end-workday state and command coordination only in new `Sources/ZoidCoachApp/DashboardEndWorkdayFlow.swift`.
- Focused flow tests in new `Tests/ZoidCoachAppTests/DashboardEndWorkdayFlowTests.swift`.
- Candidate evidence under `.audit/runs/dashboard-end-workday/candidate/`.

## Boundaries

This lane does not touch root, runtime installation, tracker, registry, backlog, Lavish, Settings, menu-bar, default-pause policy, `AutonomousPlan`, or shared agent command implementation.

The control appears only for a currently active task, requires destructive confirmation, rechecks the active task before mutation, preserves completion state and tracked time, and navigates to Reviews only after the durable end-day command succeeds.
