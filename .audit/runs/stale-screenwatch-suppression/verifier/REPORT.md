# ZC-049-003 Stale Screenwatch Suppression Verification

## Verdict

Candidate `34bc412d01a518e5b6f480215e3ab61485e3350e` is accepted at the deterministic service, notification-fixture, agent-composition, privacy, and isolated release-build layers.

The signed installed runtime journey remains pending the serialized QA runtime lease.

The candidate must not yet be described as proving recovery of a previously withdrawn same-session episode because the current persistent prompt model cannot distinguish a system withdrawal from a user dismissal.

## Verified Candidate Diff

The candidate changes exactly these production and focused-test files:

- `Sources/ZoidCoachAgent/AgentMain.swift`
- `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`
- `Tests/ZoidCoachAppTests/PromptNotificationCoordinatorTests.swift`

The verifier transplanted the candidate onto authoritative base `da1d82244fcc69f2230d0f4eedfbc79c18985290` as `1a7e962c3f7d8df9298406fe9380bc113a988fbe` in a fresh isolated worktree.

## Evidence

`swift test --scratch-path /private/tmp/zoid-666-verify-zc-049-003-build --filter GamingDriftPromptServiceTests` passed all 20 tests.

That suite proves no observation suppresses the intervention, future-dated evidence suppresses it, an observation exactly 180 seconds old remains eligible, an observation 181 seconds old suppresses it, unresolved stale gaming prompts are dismissed, fresh evidence can restore eligibility when no previous episode owns the decision, and restart, cooldown, response-pause, and daily-cap behavior remain enforced.

`swift test --scratch-path /private/tmp/zoid-666-verify-zc-049-003-build --filter resolvedPromptReconciliationCancelsDeliveredAndPendingNotificationsWithoutTouchingUnresolvedDecisions` exited successfully.

That focused test proves delivered and pending gaming notifications are removed after their prompt resolves, an unrelated unresolved plan notification remains, and private window-title and URL data do not enter notification identifiers, titles, or bodies.

Static composition inspection proves the watch loop calls `GamingDriftPromptService.produce`, then expires due prompts, then calls `PromptNotificationCoordinator.reconcilePromptNotifications` on every loop.

Startup also replays pending prompt effects and reconciles prompt notifications before continuing agent work.

Therefore a stale Screenwatch observation dismisses the queued prompt first and the same agent loop removes any pending or delivered notification whose prompt is no longer unresolved.

`swift build -c release --scratch-path /private/tmp/zoid-666-verify-zc-049-003-release` exited successfully.

The isolated release output contains a 25 MB `ZoidCoach` executable and an 11 MB `ZoidCoachAgent` executable.

## Recovery Semantics Finding

`GamingDriftPromptService.dismissUnresolvedGamingDriftPrompts()` calls `PromptInboxStore.dismiss(promptID:)` for system invalidation.

The same store operation is used for user dismissal.

Both paths persist only `state = dismissed`, release the decision key into the same `resolved:<episode-id>:<decision-key>` shape, and write no response or resolution reason.

The existing database therefore has no durable fact that can safely distinguish a system-withdrawn invalid-evidence episode from a user-dismissed episode after restart.

Re-enabling the same decision key based only on `dismissed` would weaken user dismissal, cooldown, and daily-cap guarantees, so the verifier made no such change.

The minimal future foundation is either a durable resolution-origin and resolution-reason column on `prompt_episodes`, or a prompt-resolution event table, plus a store API such as `withdraw(promptID:reason:)` that is distinct from `dismiss(promptID:)`.

Only episodes durably marked as withdrawn for invalid or stale evidence should be eligible for a later fresh-evidence decision.

User dismissals and all response, cooldown, and daily-cap records must remain authoritative.

## Remaining Signed Acceptance

Under the exclusive signed-QA runtime lease, install this exact verifier revision against an isolated QA root.

Use a deterministic clock and Screenwatch fixture without changing the Mac clock or production Screenwatch data.

Show a queued gaming-drift prompt and notification from evidence at or inside the 180-second boundary.

Advance the fixture one second beyond the boundary, let the helper complete a watch loop, and prove the prompt disappears from Today and the pending or delivered notification disappears while an unrelated notification remains.

Relaunch both app and helper and prove the withdrawn prompt and notification do not resurrect.

Cleanly unregister the helper and remove the isolated QA app and data root before releasing the runtime lease.
