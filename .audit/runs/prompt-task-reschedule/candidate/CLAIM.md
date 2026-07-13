# Prompt Task Reschedule Candidate Claim

Scenario ownership: `ZC-034-010`.

This lane makes a coaching prompt's Reschedule action open a reviewed future-date flow, persist the local plan change, queue the matching Apple Reminders due-date mutation, and only then resolve the prompt.

Owned product files:

- `Sources/ZoidCoachApp/TaskRescheduleState.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/TaskRescheduleStateTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`

Owned evidence and backlog files:

- `.audit/runs/prompt-task-reschedule/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the claims registry, Lavish artifacts, bounded-sprint recommendation files, prompt storage, task-execution storage, or XPC implementation.
