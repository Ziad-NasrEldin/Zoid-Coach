# Local task reschedule confirmation candidate

## Scope

- `ZC-020-008` - Reschedule a task only after confirming the new date.
- `ZC-034-010` - Reschedule the task.

## End-user result

Reschedule no longer changes task state immediately from the More menu.
It opens a reviewed sheet naming the task, defaults to tomorrow, and requires confirmation of a future local planning date.
The sheet states that the task leaves today's capacity but the Apple Reminder due date is not changed.
Cancel leaves the plan untouched.
Confirm reuses the durable daily-plan deferral path and stale tasks fail with an explicit refresh instruction.
Date input, confirmation, validation error, and sheet have stable task-specific accessibility identifiers.

## Evidence

- Candidate implementation: `a069230`.
- `swift test --filter TaskRescheduleStateTests` passed Cairo late-night tomorrow default, same-day rejection, and future-date local-midnight normalization.
- `swift test --filter DailyPlanRevisionTests` passed durable deferral, capacity exclusion, blocked/deferred state, restart, and revision-history coverage.
- `git diff --check` passed.

## Verifier plan

A fresh verifier should rebase onto the authoritative root and run the two focused groups once.
In signed QA, open a task's Reschedule sheet, cancel once, choose a later date and confirm, verify it leaves today's capacity without changing the Reminder due date, then restart app and helper and confirm the exact deferred date persists.
The root, runtime, tracker, registry, and Lavish artifact remain untouched by this implementation lane.
