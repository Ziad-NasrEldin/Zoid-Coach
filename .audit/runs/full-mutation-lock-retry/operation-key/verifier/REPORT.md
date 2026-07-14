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
The focused atomic local-Reminder crash-window regression passes.
The focused QA-root pending-operation isolation regression passes.
The combined operation, mutation, relaunch, lock, XPC-client, task-history, Reminder-completion, and raw-cardinality selections pass.
Migration 43 and clean ordered migration coverage pass, including preservation of existing task history and a Calendar event identifier.
The previously reported `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` baseline failure passes on the authoritative verifier base and remains separate from this candidate.
The production release build passes.
No package, installed-app, native accessibility, lock, or lost-reply runtime probe has run in this verifier lane yet.
The scenario remains `Partially implemented` until the signed temporary-lock, persistent-lock, and Calendar-preservation lost-reply journeys are completed.

## Pending Proof

- Package and install an isolated signed-QA app.
- Verify a visible task mutation succeeds exactly once after a temporary exclusive database lock is released.
- Verify a persistent exclusive lock fails with truthful last-confirmed-state copy and no operation or side effect.
- Verify relaunch after a simulated lost reply returns the stored task result without duplicate raw effects.
- Verify the Calendar approval lost-reply journey preserves its durable command identities and displays a receipt consistent with the durable outbox state.

## Current Verdict

The candidate plus verifier repairs pass the automated source acceptance boundary but are not yet fully usable end to end.

## Partial Signed Acceptance

The exact verifier tip was packaged in release mode as an installed signed-QA app using `/private/tmp/zoid-666-operation-key-signed` and `/private/tmp/zoid-666-operation-key-install`.
The ready-state window exposed `111` native accessibility content nodes and the real Today controls.

The initial fixture Reminder inventory circle routed through the separate generic Reminder action command rather than `TodayDashboardAgent.apply`.
It produced one successful `completeReminder` outbox action but no task-mutation operation row, so it was rejected as proof for the durable operation-key path.

The verifier then created the visible local task `Temporary lock acceptance`, started it through the task-activity XPC path while a real exclusive SQLite lock was released within the bounded interval, and saw the visible `Task started.` confirmation.
The verifier completed the same visible task during a second temporary exclusive lock and saw the task disappear, the gaming budget advance from `60m` to `75m`, and `Task completion is queued for Reminders sync.`
The final completion operation had one completed operation row, exactly six completion receipts, one completed history row, one reward row, one learning sample, and one final Today snapshot row.
The local-task path intentionally produced zero action-outbox rows because local tasks do not write Apple Reminders.
The visible Reminders-sync confirmation is therefore inaccurate for a local task and remains an end-user copy defect outside the durable-operation repair.
The installed app and QA helper were restarted, and the completed start and completion operation IDs plus the raw completion cardinalities remained in the database.
The relaunched Today surface retained the `75m` rewarded budget and no ready planned task.

The persistent-lock attempt was inconclusive.
The visible `Persistent lock acceptance` start operation completed and the task became active, which means the external lock had released before that user mutation reached the guarded write boundary.
It did not produce the required truthful failure state or zero-partial-row proof and must not be counted as persistent-lock acceptance.

The deterministic signed Calendar fixture existed, but the runtime cap elapsed before a committed-command lost-reply and receipt journey could begin.
No Calendar result is claimed.
The signed run also did not simulate a lost XPC reply while the client operation identity was pending, so client-side pending-ID persistence remains covered only by the automated isolated-UserDefaults regression.

Signed evidence is preserved in `runtime/ready.png`, `runtime/temporary-lock-success.png`, `runtime/final-before-cleanup.png`, and `runtime/acceptance.sqlite`.
The signed app, QA helper, LaunchAgent, install directory, and QA run root were removed at the runtime cap.
No isolated runtime process or LaunchAgent remains.

## Signed Status Recommendation

Keep `ZC-052-005` at `Partially implemented`.
The temporary-lock task-activity path and relaunch persistence are now visibly and durably proven for a local task, but the required external-Reminder outbox cardinality, persistent-lock failure boundary, pending-client lost-reply relaunch, and Calendar receipt reconciliation remain unverified.

## Signed Copy Repair

The signed run exposed an inaccurate app confirmation after local task completion.
The AppModel confirmation mapping now recognizes the established `local:user:` task identity and reports `Local task completed on this Mac.` without mentioning a queue, sync, or Reminders.
External Reminder completion continues to report the truthful pending state as `Task completion is pending Reminders sync.`
Focused public-interface tests cover both messages.
The focused tests and release build remain pending the serialized build lease.
