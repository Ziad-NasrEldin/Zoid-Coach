# Screenwatch Ingestion Control Candidate Claim

Scenario ownership: `ZC-039-009`.

This lane adds a durable Settings control that stops new Screenwatch ingestion without deleting historical Zoid 666 records or source-owned Screenwatch files, and resumes ingestion without restart.

Owned product files:

- `Sources/ZoidCoachCore/UserPolicy.swift`
- `Sources/ZoidCoachCore/ScreenwatchIngestionControl.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachAgent/AgentMain.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/UserPolicyTests.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/ScreenwatchIngestionControlTests.swift`

Owned evidence and backlog files:

- `.audit/runs/screenwatch-ingestion-control/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the scenario registry, Lavish artifacts, AppModel, prompt task-block files, active commitment or menu files, notification coordination or relevance files, Screenwatch source files, or destructive privacy controls.
