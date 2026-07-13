# Coaching limits Settings claim

## Baseline

- Authoritative baseline: `de84238`
- Branch: `codex/contextual-classification`

## Scenarios

- `ZC-045-003` - Change the daily prompt cap.
- `ZC-045-005` - Change cooldowns.

## Files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachCore/UserPolicy.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- Candidate evidence under `.audit/runs/coaching-limits-settings/candidate/`.

## Boundaries

This lane does not touch local rescheduling, AppModel, Dashboard, Daily Review, tracker, registry, Lavish, root, or runtime installation.
