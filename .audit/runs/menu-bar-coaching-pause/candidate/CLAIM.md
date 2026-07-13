# Menu bar coaching pause claim

- Authoritative baseline: `83703e9b`.
- Branch: `codex/menu-bar-coaching-pause`.

## Scenarios

- `ZC-023-004` - See a paused state while coaching is paused.
- `ZC-023-009` - Pause coaching from the menu bar.

## Owned files

- `Sources/ZoidCoachApp/MenuBarCoachingPauseController.swift`.
- Coaching-pause state only in `Sources/ZoidCoachApp/MenuBarCoachState.swift`.
- Coaching-pause controls only in `Sources/ZoidCoachApp/MenuBarCoachView.swift`.
- Focused menu pause tests in `Tests/ZoidCoachAppTests/MenuBarCoachTests.swift`.
- Candidate evidence under `.audit/runs/menu-bar-coaching-pause/candidate/`.

## Boundaries

This lane does not touch explicit-Unknown estimate files, database migrations, PromptInbox, GamingDrift, root, runtime, tracker, registry, backlog, or Lavish files.
The verifier must prove signed menu-bar pause, app and helper restart persistence, intervention suppression, continued Today access, and resume before tracker promotion.
