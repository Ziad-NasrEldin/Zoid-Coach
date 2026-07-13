# Reminder reschedule sync candidate report

## Scope

This candidate implements scenario `ZC-020-009`, which gives the user an honest Apple Reminders sync state after rescheduling a task.

The reviewed reschedule sheet now explains that the selected future date changes local planning and requests the same Apple Reminder due date.

The local deferral remains the source of truth for Zoid 666 planning and is preserved when the external write fails.

After local deferral, an external Reminder task queues one explicit `setReminderDueDate` command through the agent-owned action outbox.

A later date supersedes an older pending due-date command for the same Reminder instead of allowing obsolete writes to race.

Local-only tasks skip Apple Reminders mutation and state clearly that no source sync is required.

Today now exposes a separate Reminders Reschedule Sync ledger for deferred tasks with stable task-specific accessibility identifiers.

The ledger distinguishes queued, retrying, rejected, unavailable, and confirmed source states.

Queued and retrying states say that the local date is already safe while Apple Reminders confirmation remains outstanding.

Rejected and unavailable states never remove the local planning date or history and provide direct Reminders repair guidance.

Confirmed is shown only after the action ledger records a succeeded due-date command, so the UI does not claim source success early.

An enqueue failure leaves the local selection intact and exposes a clear global warning that Apple Reminders sync was not queued.

## Automated evidence

`swift test --filter ReminderRescheduleSyncStateTests` passed all 3 focused tests.

The focused tests cover phase mapping and safety copy, isolation from completion and unrelated-task actions, explicit due-date command creation, durable desired-date persistence, stable command identity, and superseding a prior pending date.

`swift test --filter 'TaskRescheduleStateTests|ActionOutboxStoreTests|ActionCommandExecutorTests|LocalTaskCreationControllerTests'` passed all 29 affected regression tests.

`swift build -c release` completed successfully.

`git diff --check` completed successfully.

## Verifier plan

The verifier should rebase this candidate onto authoritative commit `369c755` or the newer authoritative tip.

The verifier should rerun the focused and affected automated tests after the rebase.

The verifier should acquire the runtime lease and install a signed QA build with deterministic Reminders access.

The verifier should reschedule an external Reminder task, cancel once, then confirm a future local date and verify that Today removes it from current capacity while the sync ledger shows Pending rather than success.

The verifier should inspect the action outbox and confirm one explicit-user due-date command with the exact selected date.

The verifier should revoke Reminders access before execution and confirm that the ledger changes to Rejected while the local future date and task history remain intact after app and helper restart.

The verifier should restore Reminders access, choose a newer date, and confirm that the new command supersedes the obsolete pending date and Apple Reminders receives only the latest value.

The verifier should confirm that the ledger changes to Confirmed only after the source write succeeds.

The verifier should reschedule a local-only task and confirm that no Apple Reminders command or failure warning is created.

The verifier should disconnect the helper before confirmation and verify that the local deferral remains visible with the explicit could-not-queue warning.

The verifier should inspect the accessibility tree for the reviewed sheet copy, pending ledger, rejected safety message, exact task and date, and confirmed state.

The tracker should change only after the signed runtime proof is captured.
