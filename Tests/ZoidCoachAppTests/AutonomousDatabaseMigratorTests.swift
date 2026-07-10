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
    #expect(try tableExists(databaseURL, "processing_checkpoints"))
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
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, ingested_at)
    VALUES
        ('2026-07-10', 1, '09-00-00', 'Xcode', '', '', 0, '2026-07-10T09:00:00Z'),
        ('2026-07-10', 2, '09-00-05', 'Steam', '', '', 0, '2026-07-10T09:00:05Z');
    """)
    for version in 1...19 {
        try execute(databaseURL, "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), '2026-01-01T00:00:00Z');")
    }

    let result = try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()

    #expect(result.appliedVersions == [20, 21])
    #expect(try scalarText(databaseURL, "SELECT classification FROM behavior_records WHERE app_name = 'Xcode';") == "work")
    #expect(try scalarText(databaseURL, "SELECT classification FROM behavior_records WHERE app_name = 'Steam';") == "gaming")
    #expect(try scalarInt(databaseURL, "SELECT SUM(classification_policy_version) FROM behavior_records;") == 0)
}

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
