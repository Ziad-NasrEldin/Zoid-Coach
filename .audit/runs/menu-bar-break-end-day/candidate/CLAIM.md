# Menu Bar Break And End-Of-Day Claim

## Baseline

- Authoritative baseline: `f9edd27`.
- Branch: `codex/menu-bar-break-end-day`.

## Scenarios

- `ZC-023-008` - Start a break from the menu bar.
- `ZC-023-010` - End the workday from the menu bar.

## Files

- `Sources/ZoidCoachApp/MenuBarCoachState.swift`.
- `Sources/ZoidCoachApp/MenuBarCoachView.swift`.
- `Tests/ZoidCoachAppTests/MenuBarCoachTests.swift`.
- Candidate evidence under `.audit/runs/menu-bar-break-end-day/candidate/`.

## Boundaries

This lane does not touch PromptInbox, prompt response routing, gaming drift, Today dashboard, root, runtime installation, tracker, registry, or Lavish.
