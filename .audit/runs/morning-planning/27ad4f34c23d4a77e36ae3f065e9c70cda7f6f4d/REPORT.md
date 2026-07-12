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
- The background agent presents a due follow-up once even when a draft proposal already exists, because a draft is not mistaken for an accepted plan.
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

## Independent Signed Acceptance

- The fresh verifier rebased the candidate onto the authoritative app-classification tip and used the exact installed signed QA app, dedicated LaunchAgent, Mach service, and isolated runtime root.
- The installed Today surface rendered two deterministic Work reminders, the explicit unplanned day state, Plan Now, Work Unplanned, and Start Without Planning for both reminders.
- The canonical PLAN_READY decision rendered Review Plan, Accept Plan, Snooze 15 Min, Work Unplanned, and Dismiss For Now.
- Clicking Snooze removed the decision without escalation and, after package replacement and relaunch, visibly restored `PLANNING SNOOZED` with its exact return time.
- The signed run exposed and fixed a real end-to-end defect where an existing draft proposal cancelled the due invitation and hid the snoozed state.
- A focused time-shift advanced the persisted snooze to its due instant, the signed helper presented it once, and relaunch visibly restored the complete invitation and all recovery actions.
- Focused morning-planning, notification-contract, fixture-action, unplanned-task, and restart tests passed after the correction.
- The registry and evidence suite passed all 42 Python tests.
- The release build completed successfully; its only output was pre-existing Swift concurrency and deprecation warnings outside this slice.
- The earlier candidate full run remains the completed 473-test four-worker proof; the fresh full runner was terminated after sampling showed only the idle Swift Testing main run loop and no active test stack.
- The verifier conservatively did not claim signed Dismiss, Work Unplanned, Start Without Planning, or skip-then-plan mutations after the orchestration stop instruction.

## Verdict

Snooze, restart-safe snoozed state, due-once return, explicit unplanned visibility, and available-task visibility are fully proven end to end.
The remaining controls advance only to Touches remaining until their signed mutations are completed.
