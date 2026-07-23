# Dark appearance claim

This isolated lane starts from authoritative commit `dc280675`.

## Scenario

- `ZC-056-005` - Use dark appearance with sufficient contrast.

## Owned files

- `Sources/ZoidCoachApp/Design/SumiTheme.swift`
- The forced-light appearance modifier only in `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/SumiThemeTests.swift`
- `.audit/runs/dark-appearance/candidate/*`

The lane will let the app follow the user's macOS appearance and provide contrast-tested light and dark Sumi-Ink semantic colors.
It will not touch active offline-work entry, launch-at-login, root, runtime installation, the tracker, registry, backlog, Lavish, or any other Dashboard behavior.
