# Learned Rule Reset Verification

## Durability blocker fixed

The candidate loaded active rules and appended removal tombstones one at a time in separate writes.
A failure or concurrent update between writes could leave only part of the requested reset applied.

The verifier replaced the loop with one `BEGIN IMMEDIATE` append-only transaction.
One `INSERT ... SELECT` appends a removal tombstone for every rule that is active at the transaction boundary.
Commit failure is reported, rollback is attempted on every incomplete path, and the exact SQLite change count drives the user-visible result.

## Preserved behavior

Historical correction records, task attachments, and review totals are never rewritten.
The reset remains idempotent when no active rules exist.
The control remains hidden in the empty state.
The destructive confirmation explains future-policy fallback and historical preservation before mutation.

## Proof

- `swift test --filter DailyReviewTests` passed after the transactional fix.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance boundary

The single package/install attempt exited without creating an installed app, registering a QA helper, mutating the shared runtime, or emitting diagnostic output.
No retry was performed under the package-once and UI cap.

The signed two-rule creation, cancel, confirmed reset, exact count, and relaunch journey remains unverified.
The mapped tracker scenario remains conservative.
