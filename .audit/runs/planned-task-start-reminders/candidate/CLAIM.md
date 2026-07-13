# Planned Task-Start Reminders Claim

## Baseline

- Authoritative baseline: `08f929a`.
- Branch: `codex/planned-task-start-reminders`.

## Scenario

- `ZC-054-002` - Receive planned task-start reminders.

## Files

- `Sources/ZoidCoachInfrastructure/AgentPlanScheduler.swift`.
- `Sources/ZoidCoachInfrastructure/ActionCommandExecutor.swift` only if replacement correctness requires it.
- `Tests/ZoidCoachAppTests/AgentPlanSchedulerTests.swift`.
- `Tests/ZoidCoachAppTests/ActionCommandExecutorTests.swift` only if replacement correctness requires it.
- Candidate evidence under `.audit/runs/planned-task-start-reminders/candidate/`.

## Boundaries

This lane does not touch menu-bar break or end-day files, PromptInbox, prompt response routing, gaming drift, root, runtime installation, tracker, registry, or Lavish.
