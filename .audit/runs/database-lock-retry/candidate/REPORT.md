# ZC-052-005 Temporary Local Database Lock Recovery Candidate

## Scope

This candidate implements bounded recovery for a temporary SQLite lock at the durable action-outbox write boundary.
It does not change the authoritative scenario tracker or registry.

## End-user behavior

When another local connection temporarily holds the database write lock, the outbox now retries the immediate transaction after the normal SQLite busy timeout instead of immediately rejecting the queued user action.
Only SQLite busy and locked results are retried.
A persistent lock exhausts the finite retry schedule and returns the existing write failure, so the product still fails closed and never waits indefinitely.
The successful retry uses the original atomic and idempotent enqueue path, so it cannot create a second action merely because the database was briefly locked.

## Changed files

- `Sources/ZoidCoachInfrastructure/ActionOutboxStore.swift`
- `Tests/ZoidCoachAppTests/ActionOutboxStoreTests.swift`
- `docs/impl/666-BACKLOG.md`

## Verification

- `swift test --filter "outboxRetriesAWriteAfterATemporaryDatabaseLockClears|outboxStopsRetryingWhenADatabaseLockPersists"` passed.
- `swift test --filter outbox` passed.
- `swift build -c release` passed with exit code 0.

The temporary-lock test opens a real second SQLite connection, begins an exclusive transaction, submits the enqueue on a detached task, releases the lock after the first attempt, and confirms exactly one durable command.
The persistent-lock test holds the exclusive transaction through the complete bounded schedule and confirms the store returns `ActionOutboxStoreError`.

## Independent acceptance remaining

An independent verifier must exercise the installed signed QA app with a controlled database lock, perform a visible mutation that routes through the action outbox, release the lock, verify the visible success state and durable outbox record, relaunch the app and helper, and verify the result persists.
