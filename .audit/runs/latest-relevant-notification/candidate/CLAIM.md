# Latest Relevant Notification Candidate Claim

Scenario ownership: `ZC-038-007` and the notification-replacement portion of `ZC-033-011`.

This lane ensures a newly accepted prompt notification removes older notifications from the same relevance group while every unresolved prompt remains available in the Today dashboard.

Owned product files:

- `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`
- `Sources/ZoidCoachInfrastructure/PromptNotificationRelevance.swift`

Owned focused test files:

- `Tests/ZoidCoachAppTests/PromptNotificationRelevanceTests.swift`

Owned evidence and backlog files:

- `.audit/runs/latest-relevant-notification/candidate/`
- `docs/impl/666-BACKLOG.md`

This lane does not own root or runtime state, the scenario tracker, the scenario registry, Lavish artifacts, prompt storage, notification settings UI, prompt action routing, prompt task-reschedule files, or unrelated notification categories.
