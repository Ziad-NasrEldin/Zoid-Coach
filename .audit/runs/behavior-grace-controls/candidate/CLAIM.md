# Behavior grace controls claim

## Baseline

- Authoritative baseline: `369c755`
- Branch: `codex/impl-next-e2e-batch`

## Backlog routing

Backlog priority 4 is a signed-runtime proof slice, while this implementation lane is prohibited from using the shared runtime.

Backlog priority 7 is also awaiting signed Notification Center and repaired-response proof.

Backlog priorities 8 and 9 already have their original onboarding controls and core budget values implemented, while their remaining acceptance work either requires signed proof or overlaps the current Dashboard mutation lane.

This lane therefore claims the first coherent missing implementation group within priority 15.

## Scenario ownership

- `ZC-027-001` - Preserve a configurable task-start grace before normal drift coaching.
- `ZC-027-002` - Preserve a configurable grace after waking, unlocking, or returning from idle.
- `ZC-027-003` - Keep sustained high-confidence gaming able to bypass the task-start grace.
- `ZC-045-006` - Change the task-start grace period in Settings.

## File ownership

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachCore/UserPolicy.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/UserPolicyTests.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- Candidate evidence under `.audit/runs/behavior-grace-controls/candidate/`.
- This backlog claim and final delivered-batch entry.

## Boundaries

This lane does not touch AgentMutation, AppModel, Dashboard views, rescheduling, root, runtime installation, tracker, registry, or Lavish.
