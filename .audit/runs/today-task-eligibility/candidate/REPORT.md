# Today task eligibility candidate

## Outcome

The Today available-task queue no longer exposes every incomplete future Reminder as if it were actionable today.
It includes overdue, due-today, and undated incomplete tasks while excluding unselected future tasks.

## End-to-end behavior

- Overdue incomplete Reminders remain available.
- Reminders due at any time on the current local day remain available.
- Incomplete Reminders without a due date remain available for intentional carry-in.
- Future incomplete Reminders stay out of the available queue unless the user selected them into the daily plan.
- A selected future task remains visible in the planned task rows.
- The agent applies eligibility using the policy timezone before persisting the canonical Today snapshot.
- The app fallback applies the same eligibility rule when a canonical agent snapshot is not yet available.
- Completed-task and planned-task exclusions remain intact.

## Verification

- `swift test --filter todayQueueIncludesOverdueTodayAndUndatedButExcludesUnselectedFutureTasks` passed.
- `swift test --filter unplannedTaskStartIsVisiblePersistsAndNeverInventsAPlanViolation` passed.
- The focused fixture covers overdue, due-today at 23:30, undated, future, and manually selected future tasks in one snapshot.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim installed Today UI or restart proof.
A fresh verifier should seed all five date cases in signed QA, confirm only overdue, today, and undated appear as available, confirm the selected future task remains in the plan, restart the app and helper, and verify the exact same queue.
