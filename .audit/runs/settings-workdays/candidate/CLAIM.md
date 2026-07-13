# Settings Workdays Candidate Claim

Scenario ownership: `ZC-044-002`.

This lane makes the configured workday schedule fully editable in Settings by adding explicit working-day selection alongside the existing start and end times.

Owned product files:

- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`

Owned evidence and backlog files:

- `.audit/runs/settings-workdays/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the claims registry, Lavish artifacts, Today files, Learning files, onboarding files, or policy runtime consumers.
