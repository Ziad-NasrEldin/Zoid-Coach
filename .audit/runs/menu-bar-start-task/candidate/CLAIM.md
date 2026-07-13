# Menu-bar task start claim

This isolated lane starts from authoritative commit `d618680`.

The higher ready onboarding and notification items require signed runtime verification, schedule onboarding is already delivered, and remaining gaming-policy work overlaps Settings policy files.

This lane claims the first tracker scenario still marked not implemented that is disjoint from the active Today end-workday Dashboard files.

## Scenario

- `ZC-016-002` - Start a task from the menu bar.

## Owned files

- Start-command freshness and durable-result validation only in `Sources/ZoidCoachApp/MenuBarCoachView.swift`.
- Focused menu start tests only in `Tests/ZoidCoachAppTests/MenuBarCoachTests.swift`.
- Candidate evidence under `.audit/runs/menu-bar-start-task/candidate/`.

## Boundaries

This lane does not touch root, runtime installation, tracker, registry, backlog, Lavish, Today Dashboard files, AppModel, task persistence, or shared agent command implementation.

The existing menu presentation remains authoritative.

This batch closes the end-to-end safety gap by rechecking that the same task is still the current ready recommendation before starting it, accepting success only when the returned durable snapshot makes that exact task active, and preserving the last confirmed state on stale or malformed results.
