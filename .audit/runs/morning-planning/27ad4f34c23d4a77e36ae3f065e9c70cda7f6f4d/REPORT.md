# Morning Planning Invitation Candidate Evidence

## Scope

- `ZC-006-003` through `ZC-006-009` cover manual planning, snooze, return, temporary dismissal, explicit unplanned state, manual unplanned task start, and pre-choice drift suppression.
- `ZC-010-001` through `ZC-010-006` cover explicit planning skip, limited unplanned mode, available-task visibility, unplanned task start, truthful behavior language, and same-day return to planning.
- `ZC-010-007` is excluded because the separate daily-review lane owns end-of-day review behavior.

## Implemented End-User Behavior

- Today always exposes a low-pressure `Your day is still open` invitation before the configured time when the day has no plan.
- The invitation offers Plan Now and Work Unplanned without implying failure or escalating coaching.
- A delivered planning prompt offers Accept, Plan Now, Snooze 15 Minutes, and Dismiss For Now.
- Snooze and temporary dismissal resolve the current prompt once, hide the deferred follow-up from Today, persist the recovery time, and create one restart-safe follow-up.
- The background agent presents a due follow-up once and cancels it if a plan was created before the recovery time.
- Explicitly skipped planning persists as limited unplanned mode and keeps the Reminder inventory and behavior totals visible.
- Limited unplanned copy explicitly says that Zoid 666 will not claim activity violated a plan that does not exist.
- Every available Reminder has a separate Start control that begins tracking without silently adding or approving a daily plan.
- An active unplanned task becomes the visible active task, remains outside the plan and main objective, and survives agent restart.
- The planning state keeps drift interventions disabled until the user explicitly starts unplanned work.
- The user can return to planning at any time through Plan Now.

## Automated Acceptance

- Three planning-service tests prove snooze, dismissal, deferred visibility, due-once recovery, restart persistence, explicit unplanned persistence, and the drift gate.
- One agent journey proves skip, available inventory, manual unplanned start, truthful plan state, active-task visibility, and restart recovery.
- Notification contract and QA fixture action-matrix tests prove the new PLAN_READY actions without changing the onboarding test-prompt whitelist.
- The complete four-worker Swift suite passed 473 tests in 5 suites.
- The registry and evidence suite passed all 41 Python tests.
- The release build passed.
- Signed-QA packaging and package, LaunchAgent, Mach-service, signing-identity, designated-requirement, and embedded clean-build-identity verification passed for `zoid-coach-27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d-clean`.

## Visible Signed-QA Inspection

- The clean signed-QA app opened Today with two deterministic Work reminders.
- The visible accessibility tree exposed the low-pressure unplanned banner, the drift-suppression explanation, Plan Now, Work Unplanned, and a stable Start Without Planning control for each Reminder.
- The visible app correctly rendered `2 AVAILABLE` and the two Reminder titles without creating a plan.
- The mutation click could not be accepted as installed end-to-end proof because another concurrent lane owned the single QA Mach-service registration and the isolated package deliberately did not replace that helper.
- The failed shared-helper call left the prior state visible and showed a recoverable error instead of claiming success.
- A fresh verifier must obtain the QA runtime lease, register this exact candidate helper, and click through snooze, relaunch, due return, dismissal, unplanned start, relaunch, and Plan Now before tracker integration.

## Verdict

The implementation, persistence, recovery, package, and visible control surfaces are complete as a candidate.
Tracker advancement remains with the root integrator after one isolated installed-helper click-through.
