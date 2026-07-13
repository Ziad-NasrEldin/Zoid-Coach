# Explicit unknown task estimates claim

- Authoritative baseline: `6cf2cd779cc6181d1b665c41db8df9ea63d31e90`.
- Branch: `codex/explicit-unknown-estimates`.

## Scenarios

- `ZC-011-008` - Select `Unknown` when an estimate cannot be made confidently.
- `ZC-011-009` - See the conservative placeholder assigned to an unknown estimate.
- `ZC-011-010` - Understand that the placeholder is uncertain.
- `ZC-011-012` - Require every committed task to have an estimate or an explicit `Unknown` choice before approval.

## Owned files

- `Sources/ZoidCoachCore/AgentMutationCommand.swift` only for persisted estimate confidence.
- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift` only for the additive confidence column.
- `Sources/ZoidCoachInfrastructure/AgentOwnedStateStore.swift` only for estimate-confidence plan persistence.
- `Sources/ZoidCoachApp/Services/EventStore.swift` only for estimate-confidence plan persistence.
- Estimate selection and approval methods only in `Sources/ZoidCoachApp/AppModel.swift`.
- Estimate controls only in `Sources/ZoidCoachApp/Views/DashboardView.swift`.
- Estimate controls only in `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`.
- `Sources/ZoidCoachApp/PlanningCapacityState.swift`.
- `Sources/ZoidCoachApp/CalendarPlanApprovalState.swift`.
- Estimate labels only in `Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift`.
- Focused estimate, persistence, planning-capacity, and migration tests under `Tests/ZoidCoachAppTests/`.
- Candidate evidence under `.audit/runs/explicit-unknown-estimates/candidate/`.

## Boundaries

This lane does not touch PromptInbox, GamingDrift, coaching-response, notification, root, runtime, tracker, registry, backlog, or Lavish files.
The verifier must prove signed selection, approval, restart persistence, and later replacement with a confident estimate before any tracker promotion.
