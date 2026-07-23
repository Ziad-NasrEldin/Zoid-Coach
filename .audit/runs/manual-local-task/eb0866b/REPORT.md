# Manual Local Task Verification Evidence

## Scope

- Verified branch: `codex/verify-manual-local-task`.
- Integrated baseline: `7a14b54`.
- Implementation commits: `eac9441` and `eb0866b`.
- Signed-probe and accessibility commits: `0a23b80` and `b9d3f45`.
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

## Independent signed verification

- `python3 -m unittest discover -s Tests -p "test_*.py"` passed.
- `python3 Scripts/scenario_registry.py validate` passed with exactly 666 scenarios.
- `swift build -c release` passed on the integrated Calendar baseline.
- `Scripts/verify-qa-manual-local-task-xpc.sh` passed in a freshly packaged and installed signed-QA app.
- The signed probe created the local task through XPC, replayed the exact command idempotently, restarted the agent, started the task, completed it, restarted again, and verified durable completion history plus zero Apple Reminders outbox mutation.
- The installed signed-QA UI showed Reminders as Not Connected and still exposed New Local Task.
- The empty-title state kept Create Local Task disabled.
- Entering a title enabled the action, saving closed the sheet, and the task immediately appeared as Today's main objective and in capacity calculations.
- The AX pass found that a parent identifier initially masked every field-specific identifier.
- Commit `b9d3f45` removed that parent collision, and the rebuilt signed app then exposed distinct `local-task-title`, `local-task-notes`, `local-task-estimate`, `local-task-add-to-today`, and `local-task-save` controls.
- A full Swift invocation was terminated after an unrelated pre-existing suite hang held the SwiftPM lock for more than five minutes.
- All affected focused Swift suites passed, while the next integration owner retained responsibility for the serialized full-suite gate.

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
