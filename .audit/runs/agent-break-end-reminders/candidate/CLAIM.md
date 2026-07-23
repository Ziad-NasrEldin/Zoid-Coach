# Agent-owned break-end reminder claim

- Authoritative baseline: `bc16f7e743c96aeddf3ab15f8ed4c287e8d2337e`.
- Branch: `codex/agent-break-end-reminders`.

## Scenario ownership

- `ZC-028-006` - Receive a break-end reminder.
- `ZC-054-003` - Receive break-end reminders.

## File ownership

- `Sources/ZoidCoachInfrastructure/AcceptedBreakReminderService.swift`.
- `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`.
- `Sources/ZoidCoachInfrastructure/DeterministicOSFixtureAdapters.swift` only for fixture cancellation parity.
- `Sources/ZoidCoachAgent/AgentMain.swift`.
- `Tests/ZoidCoachAppTests/AcceptedBreakReminderServiceTests.swift`.
- `Tests/ZoidCoachAppTests/PromptNotificationCoordinatorTests.swift` only for the accepted-break notification seam.
- Candidate evidence under `.audit/runs/agent-break-end-reminders/candidate/`.

## Boundaries

This lane owns only agent-side restart-safe scheduling, stable replacement, and cancellation of accepted-break end reminders.
It does not modify Settings, `UserPolicy`, gaming drift, coaching pause controls, the root runtime, tracker, registry, Lavish, or shared installed state.
