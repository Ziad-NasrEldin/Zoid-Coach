import Foundation
import SQLite3
import Testing
@testable import ZoidCoachInfrastructure

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
