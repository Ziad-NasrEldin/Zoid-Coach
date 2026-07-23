# ZC-008-016 gaming unlock verification

## Scope

This verifier started from authoritative commit `b84fb0f4dfa2e25e36a78915cfc332eade14c4b5` in a fresh isolated worktree.
The verification covered the end-user Today journey for seeing the task that owns the locked gaming reward and moving that condition to another planned task.

## Failure reproduced

The first signed two-reminder journey exposed the accepted plan through `TodayDashboardCommandOverview.dayMap` and `TodayPlanTaskRow`.
The existing gaming-unlock presentation was wired only to `DashboardView.PlannedReminderRow`, which was not the row the user reached in the signed Today journey.
The reachable Day Map showed only `MAKE PREPARE LAUNCH BRIEF THE MAIN OBJECTIVE` and exposed neither the unlock-condition label nor a safe reassignment action.

## Repair

Commit `5b33f68e1fe33089f397f6bb44a4a6b3f20f64c8` passes the current gaming status into the reachable `TodayPlanTaskRow`.
The main task now shows `GAMING UNLOCK - COMPLETE THIS TASK FOR 15 MIN`.
A non-main task with a locked reward exposes stable action identifier `today.plan.<task-id>.make-main`, the visible title `MAKE MAIN + GAMING UNLOCK`, and the accessibility help `Moves both today's main objective and the one-time gaming reward condition to this task.`
The action requires an explicit alert with Cancel and `Move unlock condition` before it invokes the existing persisted `makeMain` path.
Disabled and already-earned reward states preserve the ordinary direct `MAKE MAIN` behavior.

## Deterministic verification

`swift test --filter GamingUnlockConditionPresentation` passed with process exit 0 after the repair.
The selected Swift Testing run covered the original presentation cases and the new reachable Today control cases.
The new cases prove the locked main label, non-main action title, confirmation requirement, consequence copy, and unchanged behavior after the reward is disabled or earned.
`swift build -c release` passed with process exit 0.

## Signed native verification

An isolated signed QA runtime was installed from clean repair commit `5b33f68e1fe33089f397f6bb44a4a6b3f20f64c8` with two normalized Reminder fixtures.
The native app drafted a two-task plan and displayed the plan approval surface with one main objective.
After acceptance, native Accessibility inspection of the reachable Day Map found `2 PLANNED BLOCKS` and the exact label `GAMING UNLOCK - COMPLETE THIS TASK FOR 15 MIN` on the main task.
The non-main task exposed enabled action identifier `today.plan.qa-gaming-main.make-main` with the exact privacy-safe consequence help `Moves both today's main objective and the one-time gaming reward condition to this task.`
The runtime was stopped at the shared disk-safety cap before the verifier could inspect the opened confirmation alert, exercise Cancel, confirm the move, relaunch, or complete both tasks.
No claim is made for those unobserved signed steps.

## Cleanup

The signed QA runtime was uninstalled and its isolated QA root, install root, and manifest were removed.
The verifier removed only its own `.build`, recovering `1,082,523,648` bytes.
Free disk after cleanup settled at `2,592,718,848` bytes.

## Current classification

The recommended status is `Touches remaining`.
The control is now present in the actual end-user Today journey and its deterministic behavior is covered, but full qualification still requires signed native proof of Cancel, confirmed movement, single-main and relaunch persistence, old-task no reward, new-main exactly-once reward, and the privacy or Unknown presentation.
