# ZC-052-005 Durable Operation-Key Verification

## Candidate And Isolation

The verifier started from authoritative commit `27f034a779aef110a93942a51b25d71643a0c0d3` in `/private/tmp/zoid-666-verify-operation-key`.
Candidate commit `acea7c04032037b7c6716c250091da6a6fbe304a` was transplanted without other candidate commits as verifier commit `d286ea6`.
The candidate does not overlap the active gaming lane's `TodayDashboardCommandOverview` source or tests.

## Source Review

Migration 43 adds the operation ledger, per-step receipt table, and operation-key uniqueness for task history without destructive operations.
The migration verifier now retains a pre-existing Calendar event identifier alongside task history while migration 43 is applied.
Task execution commits its effect and `execution` receipt in one SQLite transaction.
Task history uses a raw partial unique index over operation ID and state.
The action outbox retains its existing deterministic idempotency key.
Plan promotion, reward insertion, learning samples and aggregates, and Today snapshot persistence retain idempotent storage behavior and are checked with raw cardinality assertions after relaunch.
Completed operations return their stored final Today snapshot instead of replaying the mutation.
Terminal validation persists a terminal operation result and allows a corrected user gesture to receive a new operation ID.
The lock retry boundary is bounded and persistent locks stop before an operation or user-visible effect is created.

## Independent Blockers Found And Repaired

The candidate's original failpoint observer ran only after a step receipt was written.
That did not prove the crash window between local Reminder completion and its receipt.
The original local completion path could append a second raw `source_task.local_completed` event if the process stopped after the side effect but before the receipt.
The verifier moved local Reminder completion into `TaskMutationOperationStore`, where the source-task update, deterministic operation-ID domain event, and `reminder-completion` receipt commit in one SQLite transaction.
The store now serializes its shared SQLite connection, formatter, encoder, and decoder with a recursive lock.
The verifier regression reopens the operation store, repeats the same operation ID, and requires exactly one raw local-completion event and one receipt.

The candidate's runtime convenience initializer originally persisted pending task mutations in `UserDefaults.standard`.
That leaked signed-QA operation identity outside the isolated run-root defaults suite.
The initializer now uses `runtimeEnvironment.makeUserDefaults()`.
The verifier regression requires relaunch within one QA root to reuse the operation ID and a second QA root to receive a different ID.

## Raw Exactly-Once Assertions

The completion relaunch matrix now checks one execution state, one local Reminder completion event, one history row, one learning sample, one reward row, one Today snapshot row, one completed operation, and the exact six expected receipts.
The block relaunch path checks one blocked pause event, one plan revision, one Today snapshot row, and the exact three expected receipts.
The external Reminder relaunch path checks one outbox command, one history row, and one completed operation.

## Verification State

Source review and `git diff --check` pass.
No test, build, package, installed-app, native accessibility, lock, or lost-reply runtime probe has run in this verifier lane yet because another verifier holds the serialized build lease.
The scenario remains `Partially implemented` until automated proof passes and the signed temporary-lock, persistent-lock, and Calendar-preservation lost-reply journeys are completed.

## Pending Proof

- Run focused migration, operation-store, task-execution, history, XPC endpoint, XPC client, Today agent, and related store tests under the serialized build lease.
- Run the relevant broader regression groups and a release build.
- Package and install an isolated signed-QA app.
- Verify a visible task mutation succeeds exactly once after a temporary exclusive database lock is released.
- Verify a persistent exclusive lock fails with truthful last-confirmed-state copy and no operation or side effect.
- Verify relaunch after a simulated lost reply returns the stored task result without duplicate raw effects.
- Verify the Calendar approval lost-reply journey preserves its durable command identities and displays a receipt consistent with the durable outbox state.

## Current Verdict

The candidate plus verifier repairs are source-complete but are not yet fully usable end to end.
