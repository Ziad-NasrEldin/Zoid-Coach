# Planned Task-Start Reminders Candidate Report

## Scope

This batch owns `ZC-054-002` from baseline `08f929a`.

It changes only plan scheduling, notification execution replacement behavior, focused tests, and candidate evidence.

## End-User Behavior

Every accepted scheduled focus block now creates one durable `TASK_START` notification command for the exact block start.

The notification uses a stable day-and-task identifier, names the planned task, and tells the user to open Today to begin or revise the plan.

Optional, deferred, unscheduled, and automation-paused tasks do not receive a task-start reminder because reminders are emitted only for the scheduler's accepted blocks.

The notification command is included in the same acceptance command receipt as Calendar and Reminder mutations.

Replanning the same task supersedes the prior pending command and retains one current reminder command with the revised block time.

The notification executor now resubmits the stable identifier rather than treating an already-pending request as current, allowing macOS and QA adapters to replace obsolete time or copy safely.

## Focused Proof

`AgentPlanSchedulerTests` passed before the final replacement journey was added, and the new `plannedTaskStartReminderSchedulesAndReplacesThroughTheDurableExecutor` test passes independently.

The scheduler proof verifies the exact task, category, stable identifier, title, body, block start, command receipt, and one-current-command replan behavior.

`ActionCommandExecutorTests` passes.

Its new notification test starts with an already-pending identifier and proves the executor schedules the revised desired state and records success instead of leaving stale content in place.

## Independent Verifier Plan

1. Rebase or cherry-pick the candidate onto the latest authoritative root in an isolated verifier worktree.
2. Run `AgentPlanSchedulerTests` and `ActionCommandExecutorTests` once.
3. Inspect that an accepted focus block produces exactly one stable task-start notification at its block start and that optional, deferred, or unscheduled tasks do not.
4. Replan the same task to a later block and prove one pending request remains with the revised time and copy.
5. After obtaining the runtime lease, build and install one signed isolated QA runtime.
6. Create and approve a one-task plan whose block starts within the verifier window, process the outbox, and visibly inspect the delivered task-start notification or deterministic QA notification record.
7. Restart the app and helper before delivery, then prove the same single reminder remains scheduled and no duplicate appears.
8. Update tracker, registry, backlog, and Lavish only from the verifier lane based on signed evidence.
