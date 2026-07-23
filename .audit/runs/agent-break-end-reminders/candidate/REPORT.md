# Agent-owned break-end reminders candidate

## Scope

This candidate implements `ZC-028-006` and `ZC-054-003` as one restart-safe end-user reminder flow.
It leaves Settings, `UserPolicy`, gaming drift, coaching pause controls, the authoritative tracker, registry, Lavish, root runtime, and installed state unchanged.

## Delivered behavior

- The background agent reconciles accepted breaks in both its continuous loop and one-shot execution path.
- A persisted accepted break schedules `Break complete` for the exact stored break boundary.
- A helper restart after the boundary schedules one immediate recovery reminder instead of silently losing the promise.
- The notification body names the task and uses neutral copy that does not describe the break as failure or drift.
- The notification identifier includes the task and durable break start time, so repeated agent loops and helper restarts do not duplicate the same break reminder.
- A later break for the same task replaces obsolete reminder identities without being blocked by a previous delivered reminder.
- Resuming a task whose latest pause was an accepted break cancels all pending or delivered reminders for that task.
- The deterministic QA notification adapter now supports the same prefix-scoped cancellation semantics as the real notification center.

## Focused verification

- `swift test --filter AcceptedBreakReminderServiceTests` passed with exact-boundary, restart replay, missed-boundary recovery, fixture replacement, copy, and cancellation coverage.
- `swift test --filter AcceptedBreakLifecycleTests` passed.
- `swift test --filter PromptNotificationCoordinatorTests` passed.
- `git diff --check` passed.

## Independent verifier plan

1. Rebase this candidate onto the latest authoritative root.
2. Run `AcceptedBreakReminderServiceTests`, `AcceptedBreakLifecycleTests`, and `PromptNotificationCoordinatorTests` once.
3. Package and install one isolated signed QA runtime.
4. Start a task through Today, choose a 15-minute break, and verify exactly one scheduled `Break complete` fixture notification with the named task and exact boundary.
5. Restart the helper before the boundary and verify no second notification is created.
6. Resume early through Today and verify the scheduled notification is removed.
7. Start a second break, restart the helper after deterministically advancing beyond the boundary, and verify exactly one immediate reminder remains visible.
8. Replay the helper and verify notification count and identity remain unchanged.
9. Update the tracker only if the installed flow is completely usable end to end.
