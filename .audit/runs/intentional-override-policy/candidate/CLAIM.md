# Intentional Override Policy Claim

## Owned scenarios

- `ZC-029-013` - Set the intentional-override cooldown.
- `ZC-036-003` - Avoid another equivalent prompt during the override window.
- `ZC-036-008` - Receive normal coaching again after the override expires if conditions still apply.

## File ownership

- `Sources/ZoidCoachCore/TodayDashboard.swift` for the backward-compatible GamingPolicy field only.
- `Sources/ZoidCoachCore/UserPolicy.swift` for bounded validation only.
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift` for the Gaming Allowance card only.
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/intentional-override-policy/candidate/`
- `docs/impl/666-BACKLOG.md`

## Boundary

This lane does not touch Today task eligibility, task rows, plan controls, root, runtime, tracker, registry, or Lavish.
