# Default coaching pause duration claim

This isolated lane starts from authoritative commit `e614916`.

The higher ready onboarding journey requires the root runtime lease, notification fallback is already implemented and awaiting signed verification, schedule onboarding is fully delivered, and the remaining gaming-policy model lives in the blocked Today surface.

This lane therefore claims the highest coherent unimplemented Settings behavior that is disjoint from `AutonomousPlan` and Today files.

## Scenario

- `ZC-045-007` - Change the default coaching-pause duration.

## Owned files

- Default-pause policy modeling only in `Sources/ZoidCoachCore/UserPolicy.swift`.
- Default-pause Settings draft only in `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`.
- Default-pause conflict handling only in `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`.
- Default-pause Settings control only in `Sources/ZoidCoachApp/Views/SettingsView.swift`.
- Default-pause menu-bar behavior only in `Sources/ZoidCoachApp/MenuBarCoachingPauseController.swift`.
- Default-pause menu-bar presentation only in `Sources/ZoidCoachApp/MenuBarCoachView.swift`.
- Focused default-pause tests in `Tests/ZoidCoachAppTests/DefaultCoachingPauseDurationTests.swift`.
- Candidate evidence under `.audit/runs/default-coaching-pause/candidate/`.

## Boundaries

This lane does not touch root, runtime installation, tracker, registry, backlog, Lavish, `AutonomousPlan`, AppModel, Dashboard, or any Today source.

Legacy policies must retain the current indefinite menu-bar pause behavior.

The configured default affects the menu-bar quick pause only, while Settings keeps its explicit one-hour, until-tomorrow, and indefinite actions.
