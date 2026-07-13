# Temporary local database lock recovery verification

## Result

`ZC-052-005` remains Partially implemented.
The bounded outbox retry is a valid low-level foundation, but it does not yet recover a complete user mutation under a real lock on the shared local database.

## Verified lineage

- Candidate source commit: `931355f9271cbff81242dd655b8ab561d3df7190`.
- Candidate verifier commit: `116b7c3ad54a108916549f6db23072439f0c0aab`.
- Non-lock verifier test commit: `821c7b2a4a5811bca946766ca40cf4d72b76808b`.
- Signed build identity: `zoid-coach-116b7c3ad54a108916549f6db23072439f0c0aab-clean`.
- Installed app: `/private/tmp/zoid-666-db-lock-install/Zoid 666 QA E2E.app`.
- Isolated root: `/private/tmp/zoid-666-db-lock-runtime`.

## Passing foundation

The focused tests use a real second SQLite connection and prove that ActionOutboxStore retries SQLite busy and locked results, inserts exactly once after a temporary lock clears, and fails within the configured bound when a lock persists.
The broader outbox test group passed.
An added schema-failure test configures two one-second retry delays, removes the action table, and proves the non-lock failure returns in under half a second instead of entering the lock retry schedule.
One release QA package completed, deep signing passed, and the exact registered helper ran from the installed app.
The native signed probe showed Today in a non-minimized 1180 by 760 window with 111 accessibility nodes.

## Signed end-to-end blocker

A real second SQLite connection held an exclusive lock on the isolated canonical database while the visible user completed `Verify the ready-state journey`.
The lock was released inside the candidate's default retry bound.
The app reported `Task action failed. The task change could not be saved. The last confirmed state is still shown. Try again after checking Agent source health.`
The database contained zero `completeReminder` commands for the task.
The task completion path writes task and history state before it reaches ActionOutboxStore, so an upstream write fails before the new outbox retry can preserve the user action.

Calendar plan confirmation exposed a second usability mismatch.
After a temporary lock cleared, its four distinct expected outbox commands were each durably present exactly once and later reached succeeded state, but the signed approval sheet still reported `NOTHING WAS WRITTEN` and told the user that the background agent could not queue Calendar blocks.
The durable result therefore exists while the visible receipt falsely reports failure.

## Evidence

- `signed-ready-state.png` shows the installed signed ready-state surface.
- `temporary-lock-user-failure.png` shows the visible task action failure after the temporary lock release.
- Database inspection confirmed zero completion enqueue for the failed task mutation and one row per Calendar-plan action type and entity pair.

## Required next lane

Move temporary-lock retry to the full user mutation transaction boundary so task, history, prompt, and outbox writes recover as one operation.
Reconcile the Calendar confirmation reply with the durable enqueue result so success is never displayed as `NOTHING WAS WRITTEN`.
Then repeat temporary release, persistent lock, non-lock failure, exactly-once processing, helper restart, foreground relaunch, native accessibility, and pixel acceptance before promotion.
