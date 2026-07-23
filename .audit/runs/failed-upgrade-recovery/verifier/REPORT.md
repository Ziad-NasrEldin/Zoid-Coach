# ZC-052-006 Failed Database Upgrade Recovery Verification

## Decision

The recovery implementation is accepted for integration, but ZC-052-006 remains Blocked from verification.
Automated integration evidence now proves safe pre-upgrade snapshots, exact restoration after a mid-upgrade failure, preserved prior data, database integrity, a healthy later restart, and truthful failure when restoration itself cannot complete.
The remaining blocker is the installed signed-QA failure and restart journey required for full end-user acceptance.

## Independent review

The verifier transplanted candidate commit `de0e12d0cc644434df80e1dc7aa9fc5a6fa20335` onto authoritative commit `36992399667bc3a7db0979ffa86761e373b78f09` as a single clean commit.
The candidate commit changed only the generic migrator, its focused tests, and its candidate report.
The migrator snapshots every existing database before any pending migration, restores the snapshot on failure, verifies the exact previous schema version and `PRAGMA integrity_check`, retains the snapshot, and reports recovery guidance without claiming success when restore verification fails.

## Verification evidence

- `failedUpgradeRestoresReadablePreUpgradeDataAndAHealthyRestartCanContinue` passed against a real temporary SQLite database.
- The test applies migration 2, injects failure before migration 3, restores schema version 1, removes the partially applied table, preserves the prior source-health row, and returns `ok` from `PRAGMA integrity_check`.
- A subsequent healthy migrator run completes all current migrations and preserves the same prior row.
- `recoveryBackupIncludesCommittedWalRowsAndRemainsReadable` passed and proves committed WAL rows are present in the readable snapshot.
- `failedUpgradeDoesNotClaimRecoveryWhenTheSnapshotCannotBeRestored` passed after the verifier deliberately removed the snapshot before restore.
- The failed-restore test requires explicit `.recovery(...)` state and proves the message never says that previous readable data was restored.
- All 24 tests selected by `swift test --filter AutonomousDatabaseMigratorTests` passed after the verifier corrected the pre-existing schema-version consistency drift.
- `swift build -c release` completed with exit code 0.

## Schema-version consistency repair

The authoritative migrator already contained migration 42 while `currentVersion` remained 41 and older assertions stopped at version 38.
This made the relevant migration suite fail and could make local diagnostics report a healthy schema-42 database against an incorrect expected version 41.
The verifier changed `currentVersion` to 42 and made migration-range assertions follow the declared current version.
This repair is separate from the candidate recovery behavior and the complete migration suite is now green.

## Signed-QA boundary

The verifier prepared an isolated ready-state root at `/private/tmp/zoid-666-failed-upgrade-e2e` and attempted to seed it with the unsigned release agent.
The runtime correctly refused fixture OS access with `QA OS fixtures require a signed QA app or agent with the embedded QA run root` before migration.
The verifier stopped there, did not bypass the signing boundary, did not touch production data, and released the serialized runtime lease.

## Remaining acceptance work

A future verifier must package and install a deliberately failing clean signed-QA build against an isolated schema-41 database containing representative estimates, plans, prompts, and task sessions.
The visible app must show truthful read-only recovery guidance while the restored database remains readable and integral.
The verifier must then install a corrected signed build while preserving the isolated root, relaunch the app and helper, and prove the same data plus schema 42 remain available without duplication or loss.
