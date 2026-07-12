# Manual Local Task Candidate Evidence

## Scope

- Candidate branch: `codex/manual-local-task`.
- Integration baseline: `61eff8e`.
- Implementation commits: `eac9441` and `eb0866b`.
- Primary scenario: `ZC-051-001`, continue manual planning after Reminders access is denied or revoked.
- Supporting scenario: `ZC-002-008`, use manual local planning while Reminders access is unavailable.

## End-user flow implemented

- Today always exposes a `NEW LOCAL TASK` action in the full task inventory, including when Reminders reports an unavailable state.
- The creation sheet explains that the task remains on this Mac and is not silently written to Apple Reminders.
- The user supplies a required title, optional notes, a five-to-480-minute focus estimate, and whether to add the task directly to today's plan.
- Saving crosses the existing authenticated agent XPC boundary through an `AgentMutationCommand`.
- The agent owns the write, records the source as `local`, and can append it idempotently to today's durable plan.
- A failed or ambiguous response preserves the exact task identifier, payload, and day for a safe retry.
- External Reminder synchronization preserves local tasks and Reminder-list policy filtering does not apply to the local source lane.
- A local task can be started through the existing Today task controls.
- Completing a local task records task history and removes it from Today without queuing any Apple Reminders mutation.
- The completed state remains absent from active and unplanned inventory after agent restart.

## Focused proof

- `swift test --filter agentOwnedLocalTaskCreationIsIdempotentDurableAndPartOfTodaysPlan` passed.
- `swift test --filter localTaskControllerTrimsDraftAndPreservesItsIdentityAcrossRetry` passed.
- `swift test --filter localTaskCompletionIsDurableAndNeverMutatesAnExternalReminder` passed.
- `swift test --filter completingLocalTaskStaysLocalRecordsHistoryAndSurvivesRestart` passed.
- `git diff --check` passed before both commits.

## Verification boundary

- The Calendar verifier owned the full-suite, release-build, signed-package, and runtime lease during this candidate batch.
- This lane deliberately did not run those shared gates.
- A fresh verifier must run the integrated full suites and click through create, restart, start, complete, and second restart in the installed signed-QA app before the tracker can mark the scenarios fully implemented.

## Files

- `Sources/ZoidCoachApp/LocalTaskCreationController.swift`
- `Sources/ZoidCoachApp/Views/LocalTaskCreationView.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachCore/AgentMutationCommand.swift`
- `Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift`
- `Sources/ZoidCoachInfrastructure/AgentOwnedStateStore.swift`
- `Sources/ZoidCoachInfrastructure/ReminderSnapshotStore.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Tests/ZoidCoachAppTests/LocalTaskCreationControllerTests.swift`
- `Tests/ZoidCoachAppTests/SourceSnapshotStoreTests.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift`

## Rollback

- Revert `eb0866b` first.
- Revert `eac9441` second.
- No schema migration was added, and existing local fallback tasks remain readable.
