# Active offline work implementation claim

## Scenario IDs

- `ZC-022-001` Mark a task session as work completed away from the Mac.
- `ZC-022-002` Add offline work during the task session.

## Owned files

- `Sources/ZoidCoachApp/ActiveOfflineWorkEntry.swift`
- `Sources/ZoidCoachApp/Views/ActiveOfflineWorkSheet.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Tests/ZoidCoachAppTests/ActiveOfflineWorkEntryTests.swift`
- `.audit/runs/active-offline-work/candidate/CLAIM.md`
- `.audit/runs/active-offline-work/candidate/REPORT.md`

## Boundaries

This lane does not touch Agent lifecycle, launch-at-login, AppModel, AgentMain, migrations, package scripts, root, runtime, tracker, registry, backlog, or Lavish files.
The end-user flow must write through the existing Daily Review offline-work persistence boundary and keep away-from-Mac time explicitly separate from Screenwatch evidence.
