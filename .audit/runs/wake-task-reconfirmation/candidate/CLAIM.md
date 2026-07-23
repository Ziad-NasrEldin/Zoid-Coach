# Active-task wake reconfirmation claim

- Authoritative baseline: `9df31e01d7db26dc65e1737c6368fab8bef1596c`.
- Branch: `codex/wake-task-reconfirmation`.

## Scenarios

- `ZC-053-002` - Wake after a short lock and see timing follow the configured policy.
- `ZC-053-003` - Wake after a long sleep and be asked whether the task is still active.
- `ZC-053-004` - Avoid accumulating aligned time while no telemetry exists.

## Owned files

- `Sources/ZoidCoachApp/WakeTaskReconfirmationController.swift`.
- `Sources/ZoidCoachApp/Views/WakeTaskReconfirmationView.swift`.
- The app-activation integration hook only in `Sources/ZoidCoachApp/ZoidCoachApp.swift`.
- `Tests/ZoidCoachAppTests/WakeTaskReconfirmationControllerTests.swift`.
- Candidate evidence under `.audit/runs/wake-task-reconfirmation/candidate/`.

## Boundaries

This lane does not touch Today dashboard views, Daily Review, AppModel, menu bar files, Settings, tracker, registry, backlog, Lavish, root, or any shared runtime installation.
The verifier must prove the signed installed app's long-absence sheet and both user outcomes before any tracker promotion.
