# Dashboard end-workday candidate report

## Scope

This candidate implements scenario `ZC-013-010`, which lets the user end the active workday directly from Today.

Today now shows a fixed End Workday and Review action whenever a task is actively tracking.

The action is hidden when there is no active task and disabled in read-only safety mode.

The surrounding copy explains that tracked time is preserved, the task is not completed, and the next step is today's review.

The action requires a destructive confirmation that names the exact active task.

After confirmation, the flow fetches a fresh agent snapshot and refuses the command if the active task changed.

The flow sends the existing durable `pauseForEndOfDay` command only after the freshness check passes.

Success requires the agent response to show that the same task is paused with the `endingWorkday` reason and is no longer active.

An unchanged or malformed response is treated as a failure and never navigates away from Today.

After confirmed success, Today refreshes and the app opens Reviews.

Failure and stale-confirmation states remain on Today with actionable, non-destructive copy.

The button, hint, and result state have stable accessibility identifiers and explicit VoiceOver language.

## Automated evidence

`swift test --filter DashboardEndWorkdayFlowTests` passed all 3 focused tests.

The focused tests cover successful durable pause confirmation, exact task and command identity, preserved-time copy, stale active-task refusal with zero mutation, and invalid agent-response refusal.

`swift test --filter 'EndWorkdayReviewControllerTests|TodayDashboardAgentTests'` passed all 19 affected regression tests.

`swift build -c release` completed successfully.

`git diff --check` completed successfully.

## Verifier plan

The verifier should rebase this candidate onto the latest authoritative tip.

The verifier should rerun the focused and affected automated tests after the rebase.

The verifier should acquire the runtime lease and install a signed QA build.

The verifier should confirm that Today shows no end-workday action when no task is active.

The verifier should start a task, confirm that the fixed action appears with the exact active task context, and cancel the confirmation without changing the task.

The verifier should reopen confirmation, change the active task through another surface before confirming, and verify that the stale action is refused with zero end-day mutation.

The verifier should confirm the action for the current active task and verify that its timer stops, elapsed time remains unchanged, its state becomes paused with the end-workday reason, and it is not completed.

The verifier should verify that Reviews opens only after the durable agent result is confirmed and that the current-day review contains the preserved tracked time.

The verifier should restart both the app and helper and confirm that the task remains paused for the end of the workday and the review remains available.

The verifier should disconnect the helper, retry from a fresh active state, and confirm that Today stays visible with the active task unchanged and repair guidance shown.

The verifier should use VoiceOver or the accessibility tree to confirm the action label, preservation hint, destructive confirmation, and failure message.

The tracker should change only after the signed runtime proof is captured.
