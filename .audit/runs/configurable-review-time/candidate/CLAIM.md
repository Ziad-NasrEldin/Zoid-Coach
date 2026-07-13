# Configurable Review Time Candidate Claim

Scenario ownership: `ZC-040-001`.

This lane makes the daily end-of-day review reminder time explicitly configurable and usable from Settings through notification scheduling.

Owned product files:

- `Sources/ZoidCoachCore/UserPolicy.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachInfrastructure/ReviewReminderService.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/UserPolicyTests.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/ReviewReminderServiceTests.swift`

Owned evidence and backlog files:

- `.audit/runs/configurable-review-time/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own runtime state, the scenario tracker, the claims registry, Lavish artifacts, Daily Review views, motion files, or `AgentMain.swift`.
