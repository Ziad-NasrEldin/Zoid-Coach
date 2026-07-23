# Unfinished daily review resume claim

## Baseline

- Authoritative baseline: `9fad08e`
- Branch: `codex/impl-followup-e2e`

## Backlog routing

Backlog priorities 4 and 7 are signed-runtime proof slices rather than missing implementation.

Backlog priority 8 already has its onboarding schedule controls implemented and is awaiting remaining acceptance evidence.

Backlog priorities 9 and 15 overlap the separately owned grace-control Settings, Gaming Policy, and Gaming Drift files.

Backlog priority 16 has no unclaimed Calendar or meeting scenario in the authoritative 666 registry.

The next coherent unimplemented end-user group is durable unfinished Daily Review discovery and resume.

## Scenario ownership

- `ZC-040-005` - Resume an unfinished review after restarting the app.
- `ZC-053-008` - Restart with an unfinished review and resume it.

## File ownership

- `Sources/ZoidCoachCore/DailyReview.swift`
- `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- Focused controller tests if a separate test file is needed.
- Candidate evidence under `.audit/runs/unfinished-review-resume/candidate/`.
- This backlog claim and final delivered-batch entry.

## Boundaries

This lane does not touch Settings, Gaming Policy, Gaming Drift, AgentMutation, AppModel, Dashboard, rescheduling, root, runtime installation, tracker, registry, or Lavish.
