# ZC-052-005 full mutation lock retry candidate

## Scope

This candidate follows the signed database-lock verifier blocker without changing the scenario tracker, registry, shared backlog, migrations, package composition, or runtime.
It moves temporary-lock recovery to the complete Today task mutation call boundary and reconciles a lost Calendar scheduling acknowledgement from the durable local action ledger.

## Task mutation recovery

TodayDashboardAgent now checks write availability before the durable task mutation begins.
The check retries only while a real second SQLite connection still reports `SQLITE_BUSY` or `SQLITE_LOCKED` and uses the bounded 100, 300, and 600 millisecond default schedule.
If a competing lock appears after the preflight, the complete idempotent task mutation call is replayed only while the database still proves that a write lock exists.
A persistent lock returns a truthful bounded `The local database is still busy` failure while preserving the last confirmed state.
A validation or other non-lock failure never enters the retry delays.

The red integration test starts a real Reminder-backed task, holds an exclusive lock from a second connection, begins the visible completion mutation, releases the lock inside the retry bound, and requires one completed execution state, one history row, and one `completeReminder` command.
The test failed before the candidate and now passes.
A second real-lock test holds the exclusive transaction through a short injected retry schedule and proves bounded failure with no history or outbox partial completion.
A non-lock validation test configures two one-second delays and proves the error returns in under half a second.

## Calendar acknowledgement recovery

CalendarPlanApprovalState records the exact queue-request time before calling the agent.
If the XPC reply is lost after the command set commits, the existing action-ledger refresh can recover only commands created after that request for the exact reviewed tasks.
Recovery requires every reviewed task to have the durable Calendar reconciliation, start notification, and Reminder priority command set before the receipt is accepted.
An optional due-date command is included when present.
The app then shows ledger-confirmed success instead of the false `NOTHING WAS WRITTEN` state.

The red state test supplies the four committed commands observed in signed verification while the approval is still queueing with no receipt.
It failed before the candidate and now produces one applied four-command receipt.

## Verification

- `swift test --filter "temporaryDatabaseLockRetriesTheCompleteUserMutationExactlyOnce|persistentDatabaseLockFailsWithinTheMutationRetryBoundWithoutPartialCompletion|nonLockMutationFailureDoesNotEnterTheDatabaseRetrySchedule|recoversCommittedScheduleWhenTheReplyIsLost"` passed.
- `swift test --filter CalendarPlanApprovalState` passed.
- `swift build -c release` passed.
- `git diff --check` passed.

## Existing unrelated test failure

`deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` still fails with `TaskExecutionStoreError.write` during its snapshot reconciliation.
To isolate causality, TodayDashboardAgent.swift was temporarily restored byte-for-byte to authoritative commit `36992399667bc3a7db0979ffa86761e373b78f09` while the new tests were made compile-compatible.
The same test failed at the same snapshot step with the same `.write` error, proving this candidate did not introduce it.
The authoritative TodayDashboardAgent implementation was then replaced with the candidate and all temporary diagnostics were removed.

## Independent acceptance remaining

An independent verifier should package the integrated candidate once and repeat the signed temporary completion lock, persistent lock, non-lock failure, Calendar lost-reply recovery, exactly-once processing, helper restart, foreground relaunch, native accessibility, and pixel sequence.
