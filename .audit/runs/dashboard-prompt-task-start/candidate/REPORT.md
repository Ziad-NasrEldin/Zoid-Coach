# Dashboard Prompt Task Start Candidate

This candidate closes the visible usability gap in `ZC-016-003`.

The dashboard already sent a `startRecommendedTask` response through the canonical prompt router, applied the task start exactly once, and refreshed Today after success.

The resolved prompt disappeared without a direct confirmation that the requested task had become active.

## User behavior

- Choosing the dashboard prompt action starts the recommended task through the existing serialized agent boundary.
- The prompt response remains exactly once across dashboard and notification replay.
- Today refreshes after the accepted response so the active task state is current.
- The prompt ledger presents `<task title> is active in Today.` only after the refreshed Today snapshot confirms the requested task is active.
- VoiceOver receives the same confirmation when the acted-on prompt row disappears.
- A safe generic confirmation is used when an older prompt lacks a task title.
- Replayed or stale responses, mismatched active tasks, and other prompt actions do not receive an inaccurate task-start confirmation.
- A later inbox refresh or decision clears the confirmation so stale success is not shown.

## Verification

- `dashboardPromptStartsRecommendedTaskOnceAndProvidesVisibleOutcome` passes.
- `dashboardPromptStartOutcomeUsesHonestFallbackAndIgnoresOtherActions` passes.
- `coachingTaskActionsApplyExactDurationsAndNeverReplay` passes.
- `swift build -c release` passes.

## Remaining acceptance

An independent verifier should run the signed installed dashboard flow, press the task-start prompt action through native accessibility, and prove that one active task row and the task-named success message appear without a manual refresh.

The authoritative tracker and registry remain unchanged until that installed-app verification passes.
