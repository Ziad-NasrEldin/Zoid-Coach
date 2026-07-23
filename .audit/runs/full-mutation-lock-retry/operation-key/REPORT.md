# ZC-052-005 durable task-mutation operation key

## Scope

This repair replaces whole-mutation replay with a durable operation ledger and step receipts for task activity commands.
It starts from authoritative integration commit `b84fb0f4dfa2e25e36a78915cfc332eade14c4b5`.
It does not change Calendar offline semantics or the separate planned-block count refresh behavior.

## User-visible contract

- One user gesture receives one durable operation ID before the XPC call.
- The operation ID and original request timestamp survive an app relaunch through persisted client state.
- A lost reply or transient database lock can retry the same operation without repeating completed durable effects.
- A completed operation returns its stored `TodaySnapshot` receipt.
- A pending failure remains pending and preserves the last confirmed state instead of claiming rollback.
- A validation failure is terminal and returns the original validation diagnostic.
- A changed block reason creates a new user operation instead of mutating an existing operation's meaning.

## Durable storage

Migration 43 adds `task_mutation_operations` and `task_mutation_steps`.
The operation row stores the operation ID, task ID, command, request fingerprint, original timestamp, state, diagnostic, and completed snapshot receipt.
The step table has a composite primary key over operation ID and step.
`task_history.operation_id` has a partial unique index so raw storage, not only the read model, rejects duplicate history effects.
Task execution writes its side effects and `execution` receipt in the same SQLite transaction.

## Covered steps

- `execution`
- `plan-promotion`
- `reminder-completion`
- `outbox`
- `history`
- `reward`
- `learning`
- `today-snapshot`

Action outbox writes retain their existing deterministic idempotency key.
Local Reminder completion, plan promotion, reward ledger writes, learning sample writes, and final Today snapshot persistence retain their existing idempotent storage contracts and are guarded by durable step receipts.

## Focused evidence

The smallest ledger and XPC relaunch tracers pass.
The full focused operation-store slice passes after correcting a test fixture to create local tasks through `createLocal`.
For injected failure after each of `execution`, `reminder-completion`, `history`, `reward`, `learning`, and `today-snapshot`, relaunch and retry with the same operation ID completed successfully.
Each completion failpoint finished with exactly one raw completed history row, one estimate learning sample, one priority reward row, and one completed operation row.
The external Reminder outbox failpoint finished with exactly one raw action command, one completed history row, and one completed operation row.
The plan-promotion failpoint finished with exactly one raw blocked pause event.
Key-conflict, terminal-validation, atomic execution-receipt, raw history uniqueness, operation relaunch, and client relaunch tests pass.
Terminal validation clears the persisted client operation identity so a corrected user gesture receives a new operation ID.
Persistent-lock coverage proves zero operation, outbox, and history writes before the bounded busy error.
Temporary-lock coverage proves exactly one completed operation, outbox command, and history row after retry.
Migration 43 focused coverage and the affected migration regression selection pass after setting `AutonomousDatabaseMigrator.currentVersion` to 43.
The combined operation, Today dashboard, XPC, and client selection passed 62 of 63 tests.
The sole failure was the unrelated `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` baseline regression with `TaskExecutionStoreError.write`.
This candidate does not change `TodayDashboardAgent.snapshot` or `TaskExecutionStore.pauseForDeletedReminder`.
The same failure is documented on untouched authoritative source in `.audit/runs/external-reminder-completion/verifier/REPORT.md` and its candidate report.
The broader store and migration selection initially exposed the candidate-owned `currentVersion` mismatch, which was fixed, and its affected migration rerun passes.
The unrelated `BaselineObservationTests.migration37AddsNonDestructiveBaselineLedgerAfterCorrectionRules` expectation still hard-codes migration 38 and was not changed.
`swift build -c release` passes.

## Candidate handoff

The candidate is ready for a fresh independent two-axis verifier.
The candidate commit SHA is recorded in the handoff message because the report is part of that commit.
