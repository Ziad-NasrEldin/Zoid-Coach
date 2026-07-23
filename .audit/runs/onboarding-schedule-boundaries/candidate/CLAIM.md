# Onboarding schedule boundaries claim

## Baseline

- Authoritative baseline: `6cf0b83`
- Branch: `codex/schedule-window-validation`

## Scenarios

- `ZC-005-007` - Configure a flexible work window.
- `ZC-005-008` - Configure quiet hours.

## Files

- `Sources/ZoidCoachApp/Onboarding/OnboardingCoordinator.swift`
- `Sources/ZoidCoachApp/Onboarding/OnboardingDependencies.swift`
- `Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`
- `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`
- Candidate evidence under `.audit/runs/onboarding-schedule-boundaries/candidate/`.

## Boundaries

This lane does not touch prompt actions, prompt feedback, runtime installation, tracker, registry, Lavish, or root.
