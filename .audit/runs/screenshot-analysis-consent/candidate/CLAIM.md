# Screenshot analysis consent candidate claim

## Scenarios

- `ZC-003-009` - Choose whether screenshot analysis may be used for genuinely ambiguous situations.
- `ZC-045-012` - Enable or disable screenshot analysis.

## Owned files

- `Sources/ZoidCoachApp/Onboarding/OnboardingCoordinator.swift`
- `Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Sources/ZoidCoachAgent/AgentMain.swift`
- `Sources/ZoidCoachInfrastructure/ScreenwatchArchive.swift`
- `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`
- `Tests/ZoidCoachAppTests/ScreenwatchArchiveTests.swift`
- `Tests/ZoidCoachAppTests/PromptResponseEffectRouterTests.swift`
- `.audit/runs/screenshot-analysis-consent/candidate/*`

## Boundaries

This lane owns explicit screenshot-analysis consent, its policy mutation during Screenwatch onboarding, matching Settings explanation, agent enforcement proof, focused tests, and candidate evidence.
It will not touch Today behavior evidence, daily or weekly review, prompt behavior, tracker, registry, backlog, shared runtime, root, or Lavish.
