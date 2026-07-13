# Prompt Task Block Candidate Claim

Scenario ownership: `ZC-034-011`, with shared end-user coverage for `ZC-015-009` and `ZC-018-009`.

This lane makes a coaching prompt's Mark blocked action collect a meaningful reason, persist the blocked task and revised plan, and resolve the coaching decision only after the task mutation is accepted.

Owned product files:

- `Sources/ZoidCoachApp/PromptTaskBlockState.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/PromptTaskBlockStateTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`

Owned evidence and backlog files:

- `.audit/runs/prompt-task-block/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the scenario registry, Lavish artifacts, notification coordination or relevance files, prompt storage, task execution storage, XPC implementation, or task-reschedule state.
