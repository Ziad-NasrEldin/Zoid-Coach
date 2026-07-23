# Gaming policy Settings claim

## Baseline

- Authoritative baseline: `781f9ee00fd9da2d545050e79138f743e78cadc9`
- Branch: `codex/reminders-recovery-batch`

## Scenario ownership

- `ZC-029-002` - Set a daily gaming budget.
- `ZC-029-003` - Unlock gaming after selected priority tasks are completed.
- `ZC-029-008` - Set the base available minutes.

## File ownership

- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- Focused new Settings gaming-policy tests if needed.
- Candidate evidence under `.audit/runs/gaming-policy-settings/candidate/`.

## Boundaries

This lane does not touch plan-preview metrics, Dashboard plan surfaces, root runtime, tracker, registry, Lavish, or shared installation state.
The existing gaming policy schema and runtime budget engine remain authoritative.
