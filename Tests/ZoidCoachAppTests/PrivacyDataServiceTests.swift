import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

private let privacySQLiteTransientForTests = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test
func privacyDataServiceExportsOnlyRedactedCountsAndDeletesConversationText() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-data-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let secret = "PRIVATE WHATSAPP TEXT"
    let setup = """
    INSERT INTO screenshot_artifacts
    (id, behavior_day, behavior_epoch, path, content_hash, perceptual_fingerprint, ocr_state, extractor_version, retention_until_utc, created_at_utc)
    VALUES ('artifact', '2026-07-10', 1, '/private/screenshot.png', 'hash', 'ahash:1', 'recognized', 1, '2026-08-10T00:00:00Z', '2026-07-10T00:00:00Z');
    INSERT INTO extracted_facts
    (id, artifact_id, fact_type, schema_version, confidence, encrypted_payload, evidence_hash, created_at_utc)
    VALUES ('fact', 'artifact', 'ocr_text_blocks', 1, 1, '(secret)', 'evidence', '2026-07-10T00:00:00Z');
    """
    #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let service = try PrivacyDataService(databaseURL: databaseURL)
    let exportURL = try service.exportRedactedDiagnostics(now: Date(timeIntervalSince1970: 1_800_000_000))
    let export = try String(contentsOf: exportURL, encoding: .utf8)
    #expect(!export.contains(secret))
    #expect(!export.contains("/private/screenshot.png"))
    #expect(try service.deleteExtractedConversationText() == 1)
    #expect(try service.deleteExtractedConversationText() == 0)
}

@Test
func privacyDateDeletionNeverDeletesScreenwatchOwnedSourceFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-source-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let screenshot = root.appendingPathComponent("source.jpg")
    try Data([1, 2, 3]).write(to: screenshot)
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let sql = "INSERT INTO screenshot_artifacts (id, behavior_day, behavior_epoch, path, content_hash, perceptual_fingerprint, ocr_state, extractor_version, retention_until_utc, created_at_utc) VALUES ('artifact', '2026-07-10', 1, '\(screenshot.path)', 'hash', 'ahash:1', 'recognized', 1, '2026-08-10T00:00:00Z', '2026-07-10T00:00:00Z');"
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let formatter = ISO8601DateFormatter()
    let start = try #require(formatter.date(from: "2026-07-10T00:00:00Z"))
    let end = try #require(formatter.date(from: "2026-07-11T00:00:00Z"))

    _ = try PrivacyDataService(databaseURL: databaseURL).deleteDateRange(start: start, end: end)

    #expect(FileManager.default.fileExists(atPath: screenshot.path))
}

@Test
func privacyDateDeletionRemovesCanonicalAndProjectedPlansForTheInclusiveLocalDay() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-plan-range-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let setup = """
    INSERT INTO daily_plans (id, local_day, timezone_identifier, state, capacity_minutes, usable_capacity_minutes, policy_version, generated_at_utc)
    VALUES ('delete-plan', '2026-07-12', 'Africa/Cairo', 'draft', 480, 420, 1, '2026-07-12T06:00:00Z'),
           ('keep-plan', '2026-07-13', 'Africa/Cairo', 'draft', 480, 420, 1, '2026-07-13T06:00:00Z');
    INSERT INTO daily_plan_items (id, plan_id, source_task_id, rank, estimate_minutes, estimate_confidence, reason, evidence_ids_json, is_main_objective, state)
    VALUES ('delete-item', 'delete-plan', 'task-1', 0, 30, 'high', 'test', '[]', 1, 'planned'),
           ('keep-item', 'keep-plan', 'task-2', 0, 30, 'high', 'test', '[]', 1, 'planned');
    INSERT INTO daily_plan_entries (day_key, reminder_id, rank, is_main_objective, estimate_minutes, updated_at)
    VALUES ('2026-07-12', 'task-1', 0, 1, 30, '2026-07-12T06:00:00Z'),
           ('2026-07-13', 'task-2', 0, 1, 30, '2026-07-13T06:00:00Z');
    """
    #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))
    let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))

    _ = try PrivacyDataService(databaseURL: databaseURL).deleteDateRange(start: start, end: end)

    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    func count(_ table: String, id: String) -> Int32 {
        var statement: OpaquePointer?
        let column = table == "daily_plan_entries" ? "reminder_id" : "id"
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM \(table) WHERE \(column) = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement else { return -1 }
        defer { sqlite3_finalize(statement) }
        _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, privacySQLiteTransientForTests) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
    }
    #expect(count("daily_plans", id: "delete-plan") == 0)
    #expect(count("daily_plan_items", id: "delete-item") == 0)
    #expect(count("daily_plan_entries", id: "task-1") == 0)
    #expect(count("daily_plans", id: "keep-plan") == 1)
    #expect(count("daily_plan_items", id: "keep-item") == 1)
    #expect(count("daily_plan_entries", id: "task-2") == 1)
}

@Test
func privacyInventoryExplainsEveryStoredDataClassWithoutExposingRecordContent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-inventory-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let secret = "PRIVATE WINDOW TITLE"
    let sql = "INSERT INTO behavior_records (source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at) VALUES ('2026-07-12', 1, '10:00', 'Safari', '\(secret)', 'https://private.example', 0, NULL, '2026-07-12T10:00:00Z');"
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let inventory = try PrivacyDataService(databaseURL: databaseURL).storedDataInventory()

    #expect(inventory.databasePath == databaseURL.path)
    #expect(inventory.databaseBytes > 0)
    #expect(inventory.schemaVersion > 0)
    #expect(inventory.dataClasses.map(\.id) == ["plans", "behavior", "prompts", "meetings", "learning", "voice", "ai", "settings"])
    #expect(inventory.dataClasses.first(where: { $0.id == "behavior" })?.recordCount == 1)
    #expect(!String(describing: inventory).contains(secret))
}

@Test
func explicitRedactedExportUsesChosenJSONDestinationAndStillExcludesSecrets() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-explicit-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let destination = root.appendingPathComponent("chosen/export.json")

    let exported = try PrivacyDataService(databaseURL: databaseURL)
        .exportRedactedDiagnostics(now: Date(timeIntervalSince1970: 1_800_000_000), destinationURL: destination)
    let contents = try String(contentsOf: exported, encoding: .utf8)

    #expect(exported == destination)
    #expect(contents.contains("Titles, conversation text, URLs, file paths, event names, and payloads are excluded."))
    #expect(throws: PrivacyDataServiceError.self) {
        _ = try PrivacyDataService(databaseURL: databaseURL)
            .exportRedactedDiagnostics(destinationURL: root.appendingPathComponent("not-json.txt"))
    }
}

@Test
func targetedPrivacyDeletionSeparatesBehaviorAIAndLearningRecords() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-targeted-delete-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let setup = """
    INSERT INTO behavior_records (source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at)
    VALUES ('2026-07-12', 1, '10:00', 'Safari', 'Private', '', 0, NULL, '2026-07-12T10:00:00Z');
    INSERT INTO model_runs (id, provider, model, schema_version, prompt_version, normalized_input_hash, validation_state, started_at_utc)
    VALUES ('run', 'local', 'rules', 1, 1, 'hash', 'valid', '2026-07-12T10:00:00Z');
    INSERT INTO learning_samples (id, sample_type, context_key, actual_value, timezone_identifier, evidence_id, occurred_at_utc)
    VALUES ('sample', 'estimate', 'task', 30, 'UTC', 'evidence', '2026-07-12T10:00:00Z');
    """
    #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let service = try PrivacyDataService(databaseURL: databaseURL)

    #expect(try service.deleteRawBehaviorMetadata() == 1)
    #expect(try service.storedDataInventory().dataClasses.first(where: { $0.id == "behavior" })?.recordCount == 0)
    #expect(try service.storedDataInventory().dataClasses.first(where: { $0.id == "ai" })?.recordCount == 1)
    #expect(try service.deleteAIRequestMetadata() == 1)
    #expect(try service.deleteReviewsAndLearnedRules() == 1)
}

@Test
func deleteReviewsAndLearnedRulesClearsEveryReviewAndLearningStoreButPreservesSourceEvidence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-review-delete-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let setup = """
    INSERT INTO behavior_records (source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at, classification)
    VALUES ('2026-07-12', 1000, '10:00', 'Safari', 'Private research', '', 0, NULL, '2026-07-12T10:00:00Z', 'unknown');
    INSERT INTO task_execution_states (task_id, state, updated_at)
    VALUES ('task', 'completed', '2026-07-12T11:00:00Z');
    INSERT INTO daily_review_corrections (id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc)
    VALUES ('correction', '2026-07-12', 1000, 1060, 'work', 'task', '2026-07-12T11:00:00Z');
    INSERT INTO daily_reviews (source_day, hypothesis_state, confirmed_at_utc, updated_at_utc, personal_note)
    VALUES ('2026-07-12', 'accepted', '2026-07-12T18:00:00Z', '2026-07-12T18:00:00Z', 'Private note');
    INSERT INTO weekly_review_experiments (id, review_week_start, title, instruction, measurement, state, tracking_week_start, updated_at_utc)
    VALUES ('experiment', '2026-07-06', 'Try focus', 'Work in one block', 'Minutes aligned', 'accepted', '2026-07-13', '2026-07-12T18:00:00Z');
    INSERT INTO review_hypothesis_promotions (candidate_id, hypothesis, source_day, evidence_json, promoted_at_utc)
    VALUES ('weekly-review:2026-07-06:2026-07-12:focus', 'Focused work may be easier before noon.', '2026-07-06 TO 2026-07-12', '["privacy-safe evidence"]', '2026-07-12T18:00:00Z');
    INSERT INTO app_classification_correction_rules (normalized_app, display_app, classification, state, source_day, source_session_start_epoch, effective_from_epoch, created_at_utc)
    VALUES ('safari', 'Safari', 'work', 'active', '2026-07-12', 1000, 1000, '2026-07-12T18:00:00Z');
    INSERT INTO learning_samples (id, sample_type, context_key, actual_value, timezone_identifier, evidence_id, occurred_at_utc)
    VALUES ('sample', 'estimate', 'task', 30, 'UTC', 'evidence', '2026-07-12T18:00:00Z');
    INSERT INTO learning_aggregates (aggregate_type, aggregate_key, sample_count, median_value, confidence, policy_version, updated_at_utc)
    VALUES ('estimate', 'task', 1, 30, 0.5, 1, '2026-07-12T18:00:00Z');
    INSERT INTO planner_trust_cycles (local_day, plan_version, item_count, stayed_within_capacity, external_writes_suppressed, observed_at_utc)
    VALUES ('2026-07-12', 1, 1, 1, 0, '2026-07-12T18:00:00Z');
    """
    #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)

    let service = try PrivacyDataService(databaseURL: databaseURL)
    let learningInventory = try #require(
        service.storedDataInventory().dataClasses.first(where: { $0.id == "learning" })
    )
    #expect(learningInventory.title == ReviewLearningDeletionDisclosure.inventoryTitle)
    #expect(learningInventory.detail == ReviewLearningDeletionDisclosure.inventoryDetail)
    #expect(learningInventory.recordCount == 8)
    #expect(try service.deleteReviewsAndLearnedRules() == 8)

    for table in [
        "daily_review_corrections",
        "daily_reviews",
        "weekly_review_experiments",
        "review_hypothesis_promotions",
        "app_classification_correction_rules",
        "learning_samples",
        "learning_aggregates",
        "planner_trust_cycles",
    ] {
        #expect(try privacyRowCount(databaseURL: databaseURL, table: table) == 0)
    }
    #expect(try privacyRowCount(databaseURL: databaseURL, table: "behavior_records") == 1)
    #expect(try privacyRowCount(databaseURL: databaseURL, table: "task_execution_states") == 1)

    let reopened = try PrivacyDataService(databaseURL: databaseURL)
    #expect(try reopened.storedDataInventory().dataClasses.first(where: { $0.id == "learning" })?.recordCount == 0)
    #expect(try reopened.deleteReviewsAndLearnedRules() == 0)
}

@Test
func userCanInspectAndDeleteExactlyOneDerivedBehaviorSession() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-session-delete-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    let setup = """
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at) VALUES
      ('2026-07-12', 1000, '00:16', 'Safari', '', '', 0, NULL, '2026-07-12T00:16:40Z'),
      ('2026-07-12', 1120, '00:18', 'Safari', '', '', 0, NULL, '2026-07-12T00:18:40Z'),
      ('2026-07-12', 1180, '00:19', 'Xcode', '', '', 0, NULL, '2026-07-12T00:19:40Z'),
      ('2026-07-12', 1240, '00:20', 'Safari', '', '', 0, NULL, '2026-07-12T00:20:40Z');
    """
    #expect(sqlite3_exec(database, setup, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let service = try PrivacyDataService(databaseURL: databaseURL)

    let sessions = try service.recentBehaviorSessions()
    let firstSafari = try #require(sessions.first(where: { $0.application == "Safari" && $0.recordCount == 2 }))
    #expect(sessions.count == 3)
    #expect(try service.deleteBehaviorSession(firstSafari) == 2)
    #expect(try service.recentBehaviorSessions().map(\.recordCount).reduce(0, +) == 2)
}

@Test
func deleteAllUserDataLeavesMigratedEmptyDatabaseReadyForRestart() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("privacy-delete-all-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("coach.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "INSERT INTO task_execution_states(task_id, state, updated_at) VALUES ('task', 'active', '2026-07-12T10:00:00Z');", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let service = try PrivacyDataService(databaseURL: databaseURL)

    #expect(try service.deleteAllUserData() >= 1)
    #expect(try service.storedDataInventory().dataClasses.allSatisfy { $0.recordCount == 0 })
    #expect(try TaskExecutionStore(databaseURL: databaseURL).snapshot(for: ["task"])["task"]?.state == .ready)
}

private func privacyRowCount(databaseURL: URL, table: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          let database else {
        throw CocoaError(.fileReadUnknown)
    }
    defer { sqlite3_close(database) }
    let allowed = Set([
        "daily_review_corrections",
        "daily_reviews",
        "weekly_review_experiments",
        "review_hypothesis_promotions",
        "app_classification_correction_rules",
        "learning_samples",
        "learning_aggregates",
        "planner_trust_cycles",
        "behavior_records",
        "task_execution_states",
    ])
    guard allowed.contains(table) else { throw CocoaError(.validationMissingMandatoryProperty) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw CocoaError(.fileReadUnknown)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
    return Int(sqlite3_column_int64(statement, 0))
}
