# Learned Estimate Suggestions Claim

## Baseline

- Authoritative baseline: `0a7bbaf1ab9ee5da2511d672be70493aca4ac75a`.
- Branch: `codex/impl-next-e2e`.

## Scenario Ownership

- `ZC-012-001` - See a suggested estimate based on similar completed tasks when enough history exists.
- `ZC-012-002` - See how many similar tasks support the suggestion.
- `ZC-012-003` - See the historical duration range behind the suggestion.
- `ZC-012-004` - Understand when the evidence is uncertain.
- `ZC-012-005` - Accept the suggested estimate.
- `ZC-012-006` - Keep the original estimate instead.
- `ZC-012-007` - Enter a different estimate.
- `ZC-012-008` - Avoid receiving a confident suggestion when tracking coverage or sample size is insufficient.
- `ZC-012-009` - Avoid having an advisory estimate silently replace the user's estimate.

## File Ownership

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/LearningAggregateStore.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/Views/LearnedEstimateSuggestionView.swift`
- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Tests/ZoidCoachAppTests/LearnedEstimateSuggestionTests.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift`
- Candidate evidence under `.audit/runs/learned-estimate-suggestions/candidate/`.
- `docs/impl/666-BACKLOG.md`

## Boundaries

This lane does not touch Settings, configurable review-time controls, Review Reminder files, root runtime, tracker, registry, or Lavish.

The existing learning threshold, immutable historical samples, daily-plan estimate mutation path, and user-entered estimate controls remain authoritative.
