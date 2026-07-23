# Coach-prompt accepted break claim

## Baseline

- Authoritative baseline: `3439bba`
- Branch: `codex/accepted-break-flow`

## Scenarios

- `ZC-028-003` - Start an accepted break from a coach prompt.
- `ZC-028-005` - Avoid receiving drift prompts during an accepted break.

## Files

- `Sources/ZoidCoachInfrastructure/PromptResponseEffectRouter.swift`
- `Tests/ZoidCoachAppTests/PromptResponseEffectRouterTests.swift`
- Candidate evidence under `.audit/runs/prompt-accepted-break/candidate/`.

## Boundaries

This lane does not touch coaching-cap Settings, GamingDrift implementation or tests, AppModel, Dashboard, tracker, registry, Lavish, root, or runtime installation.
