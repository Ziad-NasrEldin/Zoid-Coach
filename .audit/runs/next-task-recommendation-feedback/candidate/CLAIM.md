# Next-task recommendation feedback claim

- Authoritative baseline: `ef4de54`.
- Branch: `codex/next-task-recommendation-feedback`.

## Scenarios

- `ZC-015-006` - Choose `Not now` for a next-task recommendation.
- `ZC-015-007` - Say the recommendation has the wrong priority.
- `ZC-015-008` - Say the recommended task is too large.

## Owned files

- `Sources/ZoidCoachCore/RecommendationFeedback.swift`.
- Recommendation-feedback command only in `Sources/ZoidCoachCore/AgentMutationCommand.swift`.
- `Sources/ZoidCoachInfrastructure/RecommendationFeedbackStore.swift`.
- Recommendation filtering only in `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`.
- Recommendation-feedback routing only in `Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift`.
- Recommendation-feedback dependency wiring only in `Sources/ZoidCoachAgent/AgentMain.swift`.
- Recommendation-feedback state and action only in `Sources/ZoidCoachApp/AppModel.swift`.
- Recommendation-feedback controls only in `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`.
- Focused recommendation-feedback tests and candidate evidence.

## Boundaries

This lane does not touch menu-bar coaching pause files, explicit-Unknown estimate behavior, database migrations, root, runtime, tracker, registry, backlog, or Lavish files.
The verifier must prove each feedback choice in a signed installed app, durable recommendation change, truthful failure recovery, restart persistence, and keyboard and accessibility usability before tracker promotion.
