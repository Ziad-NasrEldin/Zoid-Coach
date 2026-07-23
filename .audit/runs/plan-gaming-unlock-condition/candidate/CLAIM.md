# Plan Gaming Unlock Condition Claim

## Scope

- Scenario: `ZC-008-016`, Change the gaming unlock condition.
- Base: authoritative `15c5464`.
- Branch: `codex/plan-gaming-unlock-condition`.
- Worktree: `/private/tmp/zoid-666-plan-gaming-unlock-condition`.

## Owned files

- `Sources/ZoidCoachApp/GamingUnlockConditionPresentation.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/GamingUnlockConditionPresentationTests.swift`
- `.audit/runs/plan-gaming-unlock-condition/candidate/CLAIM.md`
- `.audit/runs/plan-gaming-unlock-condition/candidate/REPORT.md`
- `docs/impl/666-BACKLOG.md`

## Acceptance

When a one-time gaming reward is still locked, the daily-plan editor identifies the exact main objective whose completion unlocks it.
The end user can choose another planned task, see that both Main and the reward condition will move, confirm deliberately, and rely on the existing durable main-objective mutation and completion reward path.
Tracker, registry, Lavish, packaging, and installed runtime are outside this candidate lane.
