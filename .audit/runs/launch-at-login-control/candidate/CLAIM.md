# Launch at login control claim

This isolated lane starts from authoritative commit `1c9d546`.

## Scenario

- `ZC-044-001` - Enable or disable launch at login.

## Owned files

- `Sources/ZoidCoachApp/Services/AgentLaunchService.swift`
- `Sources/ZoidCoachApp/Services/AgentLifecycleController.swift`
- `Sources/ZoidCoachApp/Views/AgentLifecycleView.swift`
- `Tests/ZoidCoachAppTests/AgentLaunchServiceTests.swift`
- `Tests/ZoidCoachAppTests/AgentLifecycleControllerTests.swift`
- `.audit/runs/launch-at-login-control/candidate/*`

The lane will make the user's launch-at-login choice explicit and reversible even when the registered helper has a missing or stale heartbeat.
It will preserve local plans, reviews, and history when launch at login is disabled.
It will not touch root, runtime installation, the tracker, registry, backlog, Lavish, keyboard task controls, or new command files.
