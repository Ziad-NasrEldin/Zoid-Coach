# Gaming observation mode claim

This isolated lane starts from authoritative commit `d82121f`.

Higher ready work requires serialized runtime proof, so this disjoint implementation lane pulls priority 9.

## Scenario

- `ZC-029-001` - Observe gaming without applying a budget.

## Owned files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- Focused Settings, dashboard, and gaming-drift tests.
- `.audit/runs/gaming-observation-mode/candidate/*`

The lane will add a persisted observation-only gaming mode that keeps factual used minutes visible while removing budgets, unlock claims, and behavior prompts.
It will not touch rules-only Daily Review, runtime, tracker, registry, or Lavish.
