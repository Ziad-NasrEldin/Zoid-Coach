import Foundation
import SQLite3
import Testing
@testable import ZoidCoachInfrastructure

@Test
func cleanDatabaseAppliesEveryOrderedMigrationExactlyOnce() throws {
    let databaseURL = temporaryDatabaseURL("clean-migrations")
    defer { removeDatabaseFiles(at: databaseURL) }
    let migrator = AutonomousDatabaseMigrator(databaseURL: databaseURL)

    let first = try migrator.migrate()
    let second = try migrator.migrate()

    #expect(first.previousVersion == 0)
    #expect(first.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(first.appliedVersions == Array(1...AutonomousDatabaseMigrator.currentVersion))
    #expect(second.appliedVersions.isEmpty)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM schema_migrations;") == AutonomousDatabaseMigrator.currentVersion)
    #expect(try tableExists(databaseURL, "domain_events"))
    #expect(try tableExists(databaseURL, "action_commands"))
    #expect(try tableExists(databaseURL, "prompt_episodes"))
    #expect(try tableExists(databaseURL, "quiet_drift_episodes"))
    #expect(try tableExists(databaseURL, "processing_checkpoints"))
    #expect(try columnExists(databaseURL, table: "source_tasks", column: "source_kind"))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "estimate_is_uncertain"))
    try execute(databaseURL, "INSERT INTO source_tasks(source_id, title, updated_at) VALUES ('legacy-default', 'Legacy default', '2026-01-01T00:00:00Z');")
    #expect(try scalarText(databaseURL, "SELECT source_kind FROM source_tasks WHERE source_id = 'legacy-default';") == "reminders")
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'source_tasks_kind_idx';") == 1)
    #expect(throws: (any Error).self) {
        try execute(databaseURL, "INSERT INTO source_tasks(source_id, title, updated_at, source_kind) VALUES ('invalid-kind', 'Invalid', '2026-01-01T00:00:00Z', 'unknown');")
    }
}

@Test
func migration39AddsRestartSafeQuietDriftLedger() throws {
    let databaseURL = temporaryDatabaseURL("v39-quiet-drift")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (38, '2026-07-13T00:00:00Z');
    """)

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(39...AutonomousDatabaseMigrator.currentVersion))
    #expect(try tableExists(databaseURL, "quiet_drift_episodes"))
    try execute(databaseURL, "INSERT INTO quiet_drift_episodes(local_day, session_started_epoch, latest_observed_epoch, application, observed_minutes, recorded_at_utc, updated_at_utc) VALUES ('2026-07-13', 100, 700, 'Steam', 11, '2026-07-13T10:00:00Z', '2026-07-13T10:00:00Z');")
    #expect(try scalarInt(databaseURL, "SELECT observed_minutes FROM quiet_drift_episodes WHERE local_day = '2026-07-13';") == 11)
}

@Test
func migration38AddsEstimateUncertaintyWithoutChangingExistingPlanRows() throws {
    let databaseURL = temporaryDatabaseURL("v38-estimate-confidence")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (37, '2026-07-13T00:00:00Z');
    CREATE TABLE daily_plan_entries (
        day_key TEXT NOT NULL,
        reminder_id TEXT NOT NULL,
        rank INTEGER NOT NULL,
        is_main_objective INTEGER NOT NULL,
        estimate_minutes INTEGER,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(day_key, reminder_id)
    );
    INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at)
    VALUES ('2026-07-13', 'existing', 1, 1, 30, '2026-07-13T00:00:00Z');
    """)

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(38...AutonomousDatabaseMigrator.currentVersion))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "estimate_is_uncertain"))
    #expect(try scalarInt(databaseURL, "SELECT estimate_is_uncertain FROM daily_plan_entries WHERE reminder_id = 'existing';") == 0)
    #expect(try scalarInt(databaseURL, "SELECT estimate_minutes FROM daily_plan_entries WHERE reminder_id = 'existing';") == 30)
}

@Test
func versionTwoFixtureUpgradesWithoutLosingExistingPlanOrSourceHistory() throws {
    let databaseURL = temporaryDatabaseURL("v2-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (1, '2026-01-01T00:00:00Z'), (2, '2026-01-01T00:00:01Z');
    CREATE TABLE source_checkpoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        state TEXT NOT NULL,
        detail TEXT NOT NULL,
        evidence TEXT NOT NULL,
        checked_at TEXT NOT NULL
    );
    INSERT INTO source_checkpoints(source_id, state, detail, evidence, checked_at)
    VALUES ('reminders', 'Healthy', '24 tasks', 'fixture', '2026-01-01T00:00:00Z');
    CREATE TABLE daily_plan_entries (
        day_key TEXT NOT NULL,
        reminder_id TEXT NOT NULL,
        rank INTEGER NOT NULL,
        is_main_objective INTEGER NOT NULL,
        estimate_minutes INTEGER,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(day_key, reminder_id)
    );
    INSERT INTO daily_plan_entries(day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at)
    VALUES ('2026-01-01', 'task-1', 1, 1, 45, '2026-01-01T00:00:00Z');
    CREATE TABLE reminder_list_order (list_id TEXT PRIMARY KEY, position INTEGER NOT NULL, updated_at TEXT NOT NULL);
    """)

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.previousVersion == 2)
    #expect(result.appliedVersions == Array(3...AutonomousDatabaseMigrator.currentVersion))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM source_checkpoints WHERE source_id = 'reminders';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM daily_plan_entries WHERE reminder_id = 'task-1';") == 1)
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "selection_reason"))
    #expect(try columnExists(databaseURL, table: "source_tasks", column: "source_hash"))
}

@Test
func behaviorClassificationMigrationFreezesLegacyRecords() throws {
    let databaseURL = temporaryDatabaseURL("behavior-classification-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE behavior_records (
        source_day TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        time_label TEXT NOT NULL,
        app_name TEXT NOT NULL,
        window_title TEXT NOT NULL,
        url TEXT NOT NULL,
        has_screenshot INTEGER NOT NULL,
        screenshot_path TEXT,
        ingested_at TEXT NOT NULL,
        PRIMARY KEY (source_day, epoch)
    );
    CREATE TABLE gaming_reward_ledger (
        day_key TEXT NOT NULL,
        task_id TEXT NOT NULL,
        policy_version INTEGER NOT NULL,
        applied_at TEXT NOT NULL,
        PRIMARY KEY(day_key, task_id, policy_version)
    );
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at)
    VALUES
        ('2026-07-10', 1, '09-00-00', 'Xcode', '', '', 0, '2026-07-10T09:00:00Z'),
        ('2026-07-10', 2, '09-00-05', 'Steam', '', '', 0, '2026-07-10T09:00:05Z');
    """)
    for version in 1...19 {
        try execute(databaseURL, "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');")
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(20...AutonomousDatabaseMigrator.currentVersion))
    #expect(try scalarText(databaseURL, "SELECT classification FROM behavior_records WHERE app_name = 'Xcode';") == "work")
    #expect(try scalarText(databaseURL, "SELECT classification FROM behavior_records WHERE app_name = 'Steam';") == "gaming")
    #expect(try scalarInt(databaseURL, "SELECT SUM(classification_policy_version) FROM behavior_records;") == 0)
}

@Test
func versionTwentyThreePurgesRetiredSurfaceResponsesAndCreatesBackup() throws {
    let databaseURL = temporaryDatabaseURL("retired-surface-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE prompt_responses (
        id TEXT PRIMARY KEY,
        prompt_id TEXT NOT NULL,
        action_token TEXT NOT NULL UNIQUE,
        res TEXT NOT NULL,
        surface TEXT NOT NULL,
        responded_at_utc TEXT NOT NULL
    );
    CREATE TABLE gaming_reward_ledger (
        day_key TEXT NOT NULL,
        task_id TEXT NOT NULL,
        policy_version INTEGER NOT NULL,
        applied_at TEXT NOT NULL,
        PRIMARY KEY(day_key, task_id, policy_version)
    );
    INSERT INTO prompt_responses(id, prompt_id, action_token, res, surface, responded_at_utc) VALUES
        ('response-1', 'prompt-1', 'token-1', 'accept_plan', char(97, 116, 111, 108, 108), '2026-07-10T00:00:00Z'),
        ('response-2', 'prompt-2', 'token-2', 'accept_plan', 'dashboard', '2026-07-10T00:01:00Z'),
        ('response-3', 'prompt-3', 'token-3', 'accept_plan', 'notification', '2026-07-10T00:02:00Z');
    """)
    for version in 1...22 {
        try execute(databaseURL, "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');")
    }

    let result = try AutonomousDatabaseMigrator(
        databaseURL: databaseURL,
        now: { Date(timeIntervalSince1970: 1_752_153_600) }
    ).migrate()
    defer {
        if let backupURL = result.backupURL { removeDatabaseFiles(at: backupURL) }
    }

    #expect(result.appliedVersions == Array(23...AutonomousDatabaseMigrator.currentVersion))
    #expect(result.backupURL != nil)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM prompt_responses;") == 2)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM prompt_responses WHERE surface = 'dashboard';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM prompt_responses WHERE surface = 'notification';") == 1)
    let backupURL = try #require(result.backupURL)
    #expect(try scalarInt(backupURL, "SELECT COUNT(*) FROM prompt_responses;") == 3)
}

@Test
func versionTwentyFourPreservesLegacyGamingRewardsAsFifteenMinutes() throws {
    let databaseURL = temporaryDatabaseURL("gaming-reward-minutes-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE gaming_reward_ledger (
        day_key TEXT NOT NULL,
        task_id TEXT NOT NULL,
        policy_version INTEGER NOT NULL,
        applied_at TEXT NOT NULL,
        PRIMARY KEY(day_key, task_id, policy_version)
    );
    CREATE UNIQUE INDEX gaming_reward_one_per_day_policy
    ON gaming_reward_ledger(day_key, policy_version);
    INSERT INTO gaming_reward_ledger(day_key, task_id, policy_version, applied_at)
    VALUES ('2026-07-10', 'priority', 1, '2026-07-10T12:00:00Z');
    """)
    for version in 1...23 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(24...AutonomousDatabaseMigrator.currentVersion))
    #expect(try columnExists(databaseURL, table: "gaming_reward_ledger", column: "reward_minutes"))
    #expect(try scalarInt(databaseURL, "SELECT reward_minutes FROM gaming_reward_ledger;") == 15)
    #expect(try tableExists(databaseURL, "policy_mutation_receipts"))
}

@Test
func versionTwentyFiveCreatesPolicyMutationReceiptsExactlyOnce() throws {
    let databaseURL = temporaryDatabaseURL("policy-mutation-receipts-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(
        databaseURL,
        "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);"
    )
    for version in 1...24 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let migrator = AutonomousDatabaseMigrator(databaseURL: databaseURL)
    let first = try migrator.migrate()
    let second = try migrator.migrate()

    #expect(first.appliedVersions == Array(25...AutonomousDatabaseMigrator.currentVersion))
    #expect(second.appliedVersions.isEmpty)
    #expect(try tableExists(databaseURL, "policy_mutation_receipts"))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM schema_migrations WHERE version = 25;") == 1)
}

@Test
func versionTwentySevenRebrandsPersistedPromptSummaries() throws {
    let databaseURL = temporaryDatabaseURL("brand-summary-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE prompt_episodes (
        id TEXT PRIMARY KEY,
        summary TEXT NOT NULL
    );
    INSERT INTO prompt_episodes(id, summary)
    VALUES ('old', 'Meeting details are available in Zoid Coach.'),
           ('neutral', 'No product name here.');
    """)
    for version in 1...26 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(27...AutonomousDatabaseMigrator.currentVersion))
    #expect(try scalarText(databaseURL, "SELECT summary FROM prompt_episodes WHERE id = 'old';")
        == "Meeting details are available in Zoid 666.")
    #expect(try scalarText(databaseURL, "SELECT summary FROM prompt_episodes WHERE id = 'neutral';")
        == "No product name here.")
}

@Test
func dailyReviewMigrationAppliesAfterBrandMigrationWithoutChangingBehaviorEvidence() throws {
    let databaseURL = temporaryDatabaseURL("daily-review-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE behavior_records (
        source_day TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        app_name TEXT NOT NULL,
        classification TEXT,
        PRIMARY KEY(source_day, epoch)
    );
    INSERT INTO behavior_records(source_day, epoch, app_name, classification)
    VALUES ('2026-07-10', 1783663200, 'Cursor', 'work');
    """)
    for version in 1...27 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.previousVersion == 27)
    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(result.appliedVersions == Array(28...AutonomousDatabaseMigrator.currentVersion))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM behavior_records;") == 1)
    #expect(try tableExists(databaseURL, "daily_reviews"))
    #expect(try tableExists(databaseURL, "daily_review_corrections"))
    #expect(try tableExists(databaseURL, "offline_work_entries"))
}

@Test
func weeklyReviewMigrationAddsOneExperimentPerReviewWeekWithoutChangingReviewHistory() throws {
    let databaseURL = temporaryDatabaseURL("weekly-review-migration")
    defer { removeDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    try execute(databaseURL, "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES ('2026-07-05', 'accepted', '2026-07-05T18:00:00Z', '2026-07-05T18:00:00Z');")

    #expect(try tableExists(databaseURL, "weekly_review_experiments"))
    try execute(databaseURL, """
    INSERT INTO weekly_review_experiments(
        id, review_week_start, title, instruction, measurement, state, tracking_week_start, updated_at_utc
    ) VALUES (
        'weekly-1', '2026-06-29', 'Protect focus', 'Start with the main task.',
        'Compare aligned work.', 'proposed', NULL, '2026-07-06T00:00:00Z'
    );
    """)
    #expect(throws: (any Error).self) {
        try execute(databaseURL, """
        INSERT INTO weekly_review_experiments(
            id, review_week_start, title, instruction, measurement, state, tracking_week_start, updated_at_utc
        ) VALUES (
            'weekly-duplicate', '2026-06-29', 'Duplicate', 'Do it.',
            'Measure it.', 'proposed', NULL, '2026-07-06T00:00:00Z'
        );
        """)
    }
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '2026-07-05';") == 1)
}

@Test
func recoveryBackupIncludesCommittedWalRowsAndRemainsReadable() throws {
    let databaseURL = temporaryDatabaseURL("wal-backup")
    defer { removeDatabaseFiles(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    try execute(databaseURL, "PRAGMA journal_mode=WAL; INSERT INTO settings(key, value_json, policy_version, updated_at_utc) VALUES ('backup-proof', '{}', 1, '2026-07-10T00:00:00Z');")

    let backupURL = try AutonomousDatabaseMigrator(
        databaseURL: databaseURL,
        now: { Date(timeIntervalSince1970: 1_752_153_600) }
    ).createRecoveryBackup()
    defer { removeDatabaseFiles(at: backupURL) }

    #expect(try scalarInt(backupURL, "SELECT COUNT(*) FROM settings WHERE key = 'backup-proof';") == 1)
    #expect(try scalarText(backupURL, "PRAGMA integrity_check;") == "ok")
}

@Test
func failedUpgradeRestoresReadablePreUpgradeDataAndAHealthyRestartCanContinue() throws {
    let databaseURL = temporaryDatabaseURL("failed-upgrade-recovery")
    let fixedNow = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z"))
    let backupURL = databaseURL.deletingPathExtension()
        .appendingPathExtension("backup-20260714-000000.sqlite")
    defer {
        removeDatabaseFiles(at: databaseURL)
        removeDatabaseFiles(at: backupURL)
    }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (1, '2026-01-01T00:00:00Z');
    CREATE TABLE source_checkpoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        state TEXT NOT NULL,
        detail TEXT NOT NULL,
        evidence TEXT NOT NULL,
        checked_at TEXT NOT NULL
    );
    INSERT INTO source_checkpoints(source_id, state, detail, evidence, checked_at)
    VALUES ('screenwatch', 'healthy', 'readable-before-upgrade', '{}', '2026-07-13T23:00:00Z');
    """)
    let failing = AutonomousDatabaseMigrator(
        databaseURL: databaseURL,
        now: { fixedNow },
        beforeApplyingMigration: { version in
            if version == 3 { throw InjectedMigrationFailure() }
        }
    )

    #expect(throws: AutonomousDatabaseMigrationError.upgradeRolledBack(3)) {
        try failing.migrate()
    }

    #expect(FileManager.default.fileExists(atPath: backupURL.path))
    #expect(try scalarInt(backupURL, "SELECT MAX(version) FROM schema_migrations;") == 1)
    #expect(try scalarText(backupURL, "SELECT detail FROM source_checkpoints WHERE source_id = 'screenwatch';") == "readable-before-upgrade")
    #expect(try scalarText(backupURL, "PRAGMA integrity_check;") == "ok")
    #expect(try scalarInt(databaseURL, "SELECT MAX(version) FROM schema_migrations;") == 1)
    #expect(try !tableExists(databaseURL, "daily_plan_entries"))
    #expect(try scalarText(databaseURL, "SELECT detail FROM source_checkpoints WHERE source_id = 'screenwatch';") == "readable-before-upgrade")
    #expect(try scalarText(databaseURL, "PRAGMA integrity_check;") == "ok")

    let healthyRestart = try AutonomousDatabaseMigrator(
        databaseURL: databaseURL,
        now: { fixedNow.addingTimeInterval(1) }
    ).migrate()

    #expect(healthyRestart.currentVersion >= 3)
    #expect(try tableExists(databaseURL, "daily_plan_entries"))
    #expect(try scalarText(databaseURL, "SELECT detail FROM source_checkpoints WHERE source_id = 'screenwatch';") == "readable-before-upgrade")
    #expect(try scalarText(databaseURL, "PRAGMA integrity_check;") == "ok")
    if let healthyBackupURL = healthyRestart.backupURL {
        removeDatabaseFiles(at: healthyBackupURL)
    }
}

@Test
func failedUpgradeDoesNotClaimRecoveryWhenTheSnapshotCannotBeRestored() throws {
    let databaseURL = temporaryDatabaseURL("failed-upgrade-recovery-fails-closed")
    let fixedNow = try #require(ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z"))
    let backupURL = databaseURL.deletingPathExtension()
        .appendingPathExtension("backup-20260714-000000.sqlite")
    defer {
        removeDatabaseFiles(at: databaseURL)
        removeDatabaseFiles(at: backupURL)
    }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (1, '2026-01-01T00:00:00Z');
    """)
    let failing = AutonomousDatabaseMigrator(
        databaseURL: databaseURL,
        now: { fixedNow },
        beforeApplyingMigration: { version in
            if version == 3 {
                try FileManager.default.removeItem(at: backupURL)
                throw InjectedMigrationFailure()
            }
        }
    )

    do {
        _ = try failing.migrate()
        Issue.record("Expected the migration and recovery to fail.")
    } catch let error as AutonomousDatabaseMigrationError {
        guard case let .recovery(version, message) = error else {
            Issue.record("Expected an explicit recovery failure, got \(error).")
            return
        }
        #expect(version == 3)
        #expect(message.contains("pre-upgrade snapshot"))
        #expect(!error.localizedDescription.contains("restored the previous readable data"))
    }
}

private struct InjectedMigrationFailure: Error {}

private func temporaryDatabaseURL(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("zoid-coach-\(label)-\(UUID().uuidString).sqlite")
}

private func removeDatabaseFiles(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}

private func execute(_ url: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw TestDatabaseError.open }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw TestDatabaseError.sql(String(cString: sqlite3_errmsg(database)))
    }
}

private func scalarInt(_ url: URL, _ sql: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw TestDatabaseError.open }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TestDatabaseError.sql("prepare") }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw TestDatabaseError.sql("row") }
    return Int(sqlite3_column_int(statement, 0))
}

private func scalarText(_ url: URL, _ sql: String) throws -> String {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw TestDatabaseError.open }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TestDatabaseError.sql("prepare") }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw TestDatabaseError.sql("row") }
    return String(cString: value)
}

private func tableExists(_ url: URL, _ table: String) throws -> Bool {
    try scalarInt(url, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)';") == 1
}

private func columnExists(_ url: URL, table: String, column: String) throws -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw TestDatabaseError.open }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK, let statement else { throw TestDatabaseError.sql("prepare") }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 1) {
        if String(cString: name) == column { return true }
    }
    return false
}

private enum TestDatabaseError: Error {
    case open
    case sql(String)
}

@Test
func migration40AddsBoundedPersonalReviewNoteWithoutChangingExistingRows() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-40-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    _ = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    try execute(
        databaseURL,
        "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES ('2026-07-10', 'pending', NULL, '2026-07-10T18:00:00Z');"
    )

    #expect(try columnExists(databaseURL, table: "daily_reviews", column: "personal_note"))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '2026-07-10' AND personal_note IS NULL;") == 1)
}

@Test
func migration42AddsRestartSafeDailyReviewDeferral() throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-666-migration-42-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    INSERT INTO schema_migrations(version, applied_at) VALUES (41, '2026-07-13T00:00:00Z');
    CREATE TABLE daily_reviews (
        source_day TEXT PRIMARY KEY,
        hypothesis_state TEXT NOT NULL DEFAULT 'pending',
        confirmed_at_utc TEXT,
        updated_at_utc TEXT NOT NULL,
        skipped_at_utc TEXT,
        personal_note TEXT
    );
    INSERT INTO daily_reviews(source_day, updated_at_utc) VALUES ('2026-07-10', '2026-07-10T22:00:00Z');
    """)

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try columnExists(databaseURL, table: "daily_reviews", column: "deferred_until_utc"))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM daily_reviews WHERE source_day = '2026-07-10' AND deferred_until_utc IS NULL;") == 1)
}

@Test
func migration32CreatesRestartSafeBoundedSprintStorage() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-32-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'task_sprint_sessions';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'task_sprint_sessions_one_open';") == 1)
}

@Test
func migration33AddsAppendOnlyCompletedTaskHistoryContext() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-33-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try columnExists(databaseURL, table: "task_history", column: "title_snapshot"))
    #expect(try columnExists(databaseURL, table: "task_history", column: "source_kind"))
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'task_history_day_state';") == 1)
}

@Test
func migration34AddsDurableFutureClassificationRulesWithoutRewritingHistory() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-34-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'app_classification_correction_rules';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'app_classification_correction_rules_updated';") == 1)
}

@Test
func migration35AddsDurableDailyPlanRevisionFieldsWithoutChangingExistingRows() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-35-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "is_optional"))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "blocked_reason"))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "deferred_until_utc"))
}

@Test
func migration35ToleratesLegacyFixtureWithoutDailyPlanTable() throws {
    let databaseURL = temporaryDatabaseURL("migration-35-no-plan-table")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    """)
    for version in 1...34 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(35...AutonomousDatabaseMigrator.currentVersion))
    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try tableExists(databaseURL, "daily_plan_entries") == false)
}

@Test
func migration35CompletesPartiallyUpgradedDailyPlanTable() throws {
    let databaseURL = temporaryDatabaseURL("migration-35-partial-plan-table")
    defer { removeDatabaseFiles(at: databaseURL) }
    try execute(databaseURL, """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE daily_plan_entries (
        day_key TEXT NOT NULL,
        reminder_id TEXT NOT NULL,
        is_optional INTEGER NOT NULL DEFAULT 0
    );
    """)
    for version in 1...34 {
        try execute(
            databaseURL,
            "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');"
        )
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == Array(35...AutonomousDatabaseMigrator.currentVersion))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "is_optional"))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "blocked_reason"))
    #expect(try columnExists(databaseURL, table: "daily_plan_entries", column: "deferred_until_utc"))
}

@Test
func migration36AddsPrivacyBoundedNotificationDeliveryHistoryAfterDailyPlanRevision() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-666-migration-36-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.currentVersion == AutonomousDatabaseMigrator.currentVersion)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM schema_migrations WHERE version = 35;") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM schema_migrations WHERE version = 36;") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'notification_delivery_events';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'notification_delivery_events_recent';") == 1)
    #expect(try scalarInt(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'notification_delivery_events_request';") == 1)
}
