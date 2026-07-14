# ZC-049-003 Stale Screenwatch Suppression Verification

## Verdict

Candidate source `34bc412d01a518e5b6f480215e3ab61485e3350e` is accepted at the deterministic service, notification-fixture, agent-composition, privacy, isolated release-build, and conservative signed-builder evidence layers.

The complete signed stale-to-fresh-to-stale recovery journey remains unproven.

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

## Signed Builder Evidence

The builder supplied `fresh.png`, `stale.png`, a canonical QA database, and deterministic OS fixture state under `/private/tmp/zc049003-evidence/`.

The candidate source identity is `34bc412d01a518e5b6f480215e3ab61485e3350e`.

The signed package build identity was not preserved in the evidence bundle, so this report does not invent a clean-build identifier or bind the screenshots to one.

The privacy-safe screenshots are preserved under `.audit/runs/stale-screenwatch-suppression/signed-builder/`.

`fresh.png` is a readable 2584 by 1744 signed-app window capture with SHA-256 `45ddb5b782f2408b6c8518e5c02677d96c8cb46a4497e7061155cfdf2491b1f5`.

It visibly shows Zoid 666 Build 8 on Today, a completed 7 of 7 day baseline, and no behavior prompt in the visible surface.

No private window title or URL is visible in the screenshot.

`stale.png` is a 202 by 240 window thumbnail with SHA-256 `1a79c2abbc503d15e5f879f34c3601962d083195ca20d5290cd46e595418cba0`.

It is retained only as low-resolution provenance and is not used to claim readable UI state.

The raw database has SHA-256 `0680fdaf45499d9fbbb689f3b616f2a5694752db8ca10c29cb82c5a14e7a6a75`.

Independent aggregate inspection found exactly one `GAMING_DRIFT` episode in `dismissed` state, zero unresolved prompt episodes, zero prompt responses, and one notification-delivery row.

The OS fixture state has SHA-256 `40759626e80674183555ae90d3ffe10a00bfe9c7137e3cd515f7512a69459178`.

Its audit records a successful `cancel-identifiers` notification operation after scheduling and delivery operations.

Its remaining notification state contains two `DAILY_REVIEW` notifications, one `WEEKLY_REVIEW` notification, and one `ZCQA_UNRELATED` notification, with no `GAMING_DRIFT` notification.

Those aggregate facts support signed withdrawal and unrelated-notification preservation without exposing notification content.

The raw database and fixture state were intentionally not committed because their prompt payloads may contain private title or URL fixture values.

The older signed missing-source verifier independently recorded zero total and unresolved prompts before and after an installed app relaunch.

Together these artifacts support conservative signed withdrawal, relaunch non-resurrection, and privacy evidence, but they do not prove same-session fresh-evidence recovery after a system withdrawal.

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

Under a future exclusive signed-QA runtime lease, install an exact clean verifier revision against an isolated QA root and preserve its package build identity.

Use a deterministic clock and Screenwatch fixture without changing the Mac clock or production Screenwatch data.

Show a queued gaming-drift prompt and notification from evidence at or inside the 180-second boundary.

Advance the fixture one second beyond the boundary, let the helper complete a watch loop, and prove the prompt disappears from Today and the pending or delivered notification disappears while an unrelated notification remains.

Relaunch both app and helper and prove the withdrawn prompt and notification do not resurrect.

Cleanly unregister the helper and remove the isolated QA app and data root before releasing the runtime lease.
