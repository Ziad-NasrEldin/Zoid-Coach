# ZC-052-006 Failed Database Upgrade Recovery Candidate

## Scope

This candidate protects readable prior data when a schema upgrade fails after partially applying pending migration versions.
It changes only generic migration orchestration and does not alter any migration definition or Daily Review behavior.
It does not change the authoritative scenario tracker or registry.

## End-user behavior

Before upgrading an existing local database, Zoid 666 now creates a consistent SQLite snapshot that includes committed WAL rows.
If any pending migration fails, the migrator restores that complete pre-upgrade snapshot into the live database before returning an error.
Recovery verifies both the exact previous schema version and `PRAGMA integrity_check` before saying the prior data is readable.
The retained error explains that the user can restart with the previous app version or install a corrected update.
If recovery itself cannot be verified, the error refuses to claim success and reports the recovery failure.
The snapshot remains beside the database for independent recovery evidence.

## Changed files

- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift`
- `Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift`
- `docs/impl/666-BACKLOG.md`

## Verification

- `swift test --filter failedUpgradeRestoresReadablePreUpgradeDataAndAHealthyRestartCanContinue` passed.
- The test creates a schema-v1 SQLite database with a readable source-health row, applies migration 2, injects a failure before migration 3, and confirms automatic restoration to schema v1 with no migration-2 table.
- The restored user row remains readable and `PRAGMA integrity_check` returns `ok`.
- A subsequent healthy migrator restart completes the available upgrade and preserves the same row with integrity `ok`.
- The existing `recoveryBackupIncludesCommittedWalRowsAndRemainsReadable` test passes, preserving WAL snapshot coverage.
- `swift build -c release` passed with exit code 0.

## Authoritative baseline note

The broader migration-filter run currently has 13 pre-existing expectation failures because the authoritative source contains migrations through 42 while `AutonomousDatabaseMigrator.currentVersion` is 41 and several tests still expect version 38.
This candidate does not change those migration definitions or Daily Review expectations because they are outside the accepted lane scope.

## Independent acceptance remaining

An independent verifier must copy a representative signed-QA database into an isolated run root, install a deliberately failing migration build, confirm the pre-upgrade snapshot and restored readable data, restart the previous signed app against the restored copy, then install a corrected build and verify the same estimates, plans, prompts, and task sessions after app and helper relaunch.
