# Active Commitment Visibility Candidate Claim

Scenario ownership:

- `ZC-017-001` - Start an open-ended work session.
- `ZC-037-001` - See the active task in the Today dashboard.
- `ZC-059-007` - See the selected task become active everywhere.
- `ZC-062-004` - Continue manually tracking the active task.

Owned production files:

- `Sources/ZoidCoachApp/ActiveCommitmentPresentation.swift`
- `Sources/ZoidCoachApp/MenuBarCoachState.swift`
- `Sources/ZoidCoachApp/MenuBarCoachView.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`

Owned tests and evidence:

- `Tests/ZoidCoachAppTests/ActiveCommitmentPresentationTests.swift`
- `Tests/ZoidCoachAppTests/MenuBarCoachTests.swift`
- `.audit/runs/active-commitment-visibility/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane will make the active commitment's task identity, open-ended or bounded timing contract, tracked duration, and manual Pause or Complete controls explicit and consistent in Today and the menu bar.

This lane does not own `AppModel.swift`, prompt inbox files, `GamingDriftPromptService.swift`, shared tracker or registry files, the Lavish artifact, root runtime state, or signed-QA installation.
