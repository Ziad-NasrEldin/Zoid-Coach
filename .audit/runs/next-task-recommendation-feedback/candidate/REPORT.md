# Next-task recommendation feedback candidate report

## Candidate scope

- `ZC-015-006` now has a direct `Not now` action on the current next-task recommendation.
- `ZC-015-007` now has a direct `Wrong priority` action.
- `ZC-015-008` now has a direct `Too large` action.
- This is candidate implementation evidence and does not promote the authoritative tracker.

## End-user behavior

- All three feedback choices are visible beside the recommended task rather than hidden in Settings.
- Each choice has a stable accessibility identifier and an explanatory accessibility hint.
- The controls disable while one response is saving.
- The surface shows saving progress, a durable-success explanation, or a truthful failure and recovery message.
- `Not now` selects another ready task for 30 minutes and then allows the original task to become eligible again.
- `Wrong priority` selects another ready task for the rest of the policy-local day.
- `Too large` selects another ready task for the rest of the policy-local day without inventing a task split.
- Starting the recommendation remains available and visually separate from feedback.

## Persistence and safety

- Feedback travels through the authenticated background-agent mutation boundary.
- The agent stores feedback as a local domain event in the existing canonical database schema.
- Request identifiers are idempotent and conflicting replays are rejected.
- The agent rejects stale or future-dated feedback commands outside a five-minute boundary.
- Recommendation selection reads durable feedback before ranking ready tasks.
- A restarted agent restores the feedback and selects the same eligible alternative.
- A failed mutation leaves the current recommendation active and tells the user to check Agent source health.
- A successful mutation followed by a refresh failure reports that feedback was saved and asks the user to refresh Today.

## Focused evidence

- `swift test --filter RecommendationFeedbackTests` passed 4 tests on 13 July 2026.
- The tests cover all three encoded choices, 30-minute and local-day suppression boundaries, idempotent replay, conflicting replay rejection, mutation-router persistence, alternate selection, and agent-restart restoration.
- `swift test --filter TodayDashboardAgentTests` passed 12 of 13 tests.
- Its unrelated `unplannedTaskStartIsVisiblePersistsAndNeverInventsAPlanViolation` fixture failed with the pre-existing `PromptInboxStoreError.invalidDraft`, and the same exact failure reproduced in the untouched menu-bar candidate worktree.
- `swift build -c release --product ZoidCoach` completed successfully.
- `swift build -c release --product ZoidCoachAgent` completed successfully.
- The release build emitted only pre-existing warnings in `CodexJobCoordinator.swift` and `VoiceAudioEngine.swift`.
- `git diff --check` completed successfully.

## Independent verifier plan

1. Rebase or cherry-pick this candidate onto authoritative revision `db7db53` or its successor.
2. Build, sign, install, and launch a fresh QA application and helper from that exact revision.
3. Seed at least three ready planned tasks with stable distinct priorities and sizes.
4. Confirm that Today displays the expected first recommendation and all three feedback choices.
5. Activate `Not now` with the keyboard and confirm visible progress, success copy, and a different recommendation.
6. Relaunch the app and helper inside the 30-minute window and confirm that the temporary choice remains active.
7. Advance the deterministic QA clock beyond 30 minutes and confirm that the original task can become eligible again.
8. Activate `Wrong priority` and confirm that another task remains selected through app and helper restarts on the same local day.
9. Advance across the policy-local day boundary and confirm that the task can become eligible again.
10. Activate `Too large` and confirm that another recommendation appears without changing the task estimate, completion, blocked, or plan state.
11. Stop or disconnect the helper, activate a feedback choice, and confirm that the original recommendation remains with actionable failure copy.
12. Inspect keyboard focus order, VoiceOver labels, accessibility hints, progress state, success state, and error state.

## Promotion boundary

- Keep all three scenarios at their existing tracker statuses until the signed installed-app verifier completes the plan above.
- Promotion requires durable agent mutation, truthful visible state, restart persistence, local-day behavior, failure recovery, and keyboard and accessibility proof.
