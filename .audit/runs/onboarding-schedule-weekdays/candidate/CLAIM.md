# Onboarding schedule weekdays claim

This isolated lane starts from authoritative commit `069022e`.

## Scenario ownership

- `ZC-005-007` - Configure a flexible work window.
- `ZC-005-008` - Configure quiet hours.

## File ownership

- `Sources/ZoidCoachApp/Onboarding/OnboardingCoordinator.swift`
- `Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`
- `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`
- Candidate evidence under `.audit/runs/onboarding-schedule-weekdays/candidate/`.

## Boundaries

This lane adds user-selectable work weekdays, explicit overnight schedule summaries, exact validation, persistence, and focused proof inside onboarding only.
It does not touch Gaming Observation Mode files, root, runtime installation, tracker, registry, Lavish, Settings, Today, or shared QA state.
