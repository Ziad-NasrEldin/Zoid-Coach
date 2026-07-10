import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func screenwatchArchiveIngestsEachObservationOnlyOnceAcrossRepeatedRuns() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-10", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let log = """
    {"t":"09-00-00","epoch":1783663200,"app":"Cursor","window":"Project","url":"","img":false}
    {"t":"09-00-05","epoch":1783663205,"app":"WhatsApp","window":"Sarah","url":"","img":true}

    """
    try Data(log.utf8).write(to: day.appendingPathComponent("log.jsonl"))
    try Data([0x00]).write(to: day.appendingPathComponent("09-00-05.jpg"))
    let archive = try ScreenwatchArchive(databaseURL: root.appendingPathComponent("zoid-coach.sqlite"))
    let date = Date(timeIntervalSince1970: 1_783_663_210)

    let first = try archive.ingestToday(from: root, now: date)
    let second = try archive.ingestToday(from: root, now: date)

    #expect(first.totalRecordsRead == 2)
    #expect(first.insertedCount == 2)
    #expect(second.totalRecordsRead == 0)
    #expect(second.insertedCount == 0)
    #expect(try archiveScalar(databaseURL: root.appendingPathComponent("zoid-coach.sqlite"), sql: "SELECT COUNT(*) FROM screenshot_artifacts;") == 1)
    #expect(try archiveScalar(databaseURL: root.appendingPathComponent("zoid-coach.sqlite"), sql: "SELECT byte_offset FROM processing_checkpoints LIMIT 1;") == Data(log.utf8).count)
}

@Test
func screenwatchCheckpointLeavesPartialLineForTheNextTailPass() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-10", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let logURL = day.appendingPathComponent("log.jsonl")
    let firstLine = "{\"t\":\"09-00-00\",\"epoch\":1783663200,\"app\":\"Cursor\",\"window\":\"Project\",\"url\":\"\",\"img\":false}\n"
    let partial = "{\"t\":\"09-00-05\",\"epoch\":1783663205"
    try Data((firstLine + partial).utf8).write(to: logURL)
    let databaseURL = root.appendingPathComponent("zoid-coach.sqlite")
    let archive = try ScreenwatchArchive(databaseURL: databaseURL)
    let date = Date(timeIntervalSince1970: 1_783_663_210)

    let first = try archive.ingestToday(from: root, now: date)
    let remainder = ",\"app\":\"Safari\",\"window\":\"Web\",\"url\":\"\",\"img\":false}\n"
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(remainder.utf8))
    try handle.close()
    let second = try archive.ingestToday(from: root, now: date)

    #expect(first.totalRecordsRead == 1)
    #expect(second.totalRecordsRead == 1)
    #expect(try archiveScalar(databaseURL: databaseURL, sql: "SELECT COUNT(*) FROM behavior_records;") == 2)
}

private func archiveScalar(databaseURL: URL, sql: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw ArchiveTestError.database }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ArchiveTestError.database }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw ArchiveTestError.database }
    return Int(sqlite3_column_int64(statement, 0))
}

private enum ArchiveTestError: Error { case database }

@Test
func whatsappOCRPersistsEncryptedPositionedEvidenceAndLinksTheCandidate() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-10", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = "{\"t\":\"09-00-00\",\"epoch\":1783663200,\"app\":\"WhatsApp\",\"window\":\"Sarah\",\"url\":\"\",\"img\":true}\n"
    try Data(log.utf8).write(to: day.appendingPathComponent("log.jsonl"))
    try Data([0x01, 0x02, 0x03]).write(to: day.appendingPathComponent("09-00-00.jpg"))
    let databaseURL = root.appendingPathComponent("zoid-coach.sqlite")
    let archive = try ScreenwatchArchive(databaseURL: databaseURL)
    let observedAt = Date(timeIntervalSince1970: 1_783_663_200)
    _ = try archive.ingestToday(from: root, now: observedAt)
    let result = ScreenshotOCRResult(blocks: [
        OCRTextBlock(
            text: "Meeting tomorrow at 3 pm for 30 minutes",
            confidence: 0.96,
            boundingBox: NormalizedBoundingBox(x: 0.1, y: 0.2, width: 0.7, height: 0.1),
            localeHint: "en"
        )
    ])
    let cipher = try LocalEvidenceCipher(keyData: Data(repeating: 7, count: 32))

    let analysis = try await archive.analyzePendingWhatsAppScreenshots(using: FakeScreenshotRecognizer(result: result), cipher: cipher)
    let encrypted = try archiveBlob(databaseURL: databaseURL, sql: "SELECT encrypted_payload FROM extracted_facts LIMIT 1;")
    let decrypted = try cipher.decrypt(encrypted)
    let decoded = try JSONDecoder().decode(ScreenshotOCRResult.self, from: decrypted)

    #expect(analysis.screenshotsProcessed == 1)
    #expect(analysis.candidatesCreated == 1)
    #expect(decoded == result)
    #expect(try archiveScalar(databaseURL: databaseURL, sql: "SELECT COUNT(*) FROM meeting_evidence;") == 1)
}

private struct FakeScreenshotRecognizer: ScreenshotTextRecognizing {
    let result: ScreenshotOCRResult
    func recognize(in imageURL: URL) async throws -> ScreenshotOCRResult { result }
}

private func archiveBlob(databaseURL: URL, sql: String) throws -> Data {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw ArchiveTestError.database }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ArchiveTestError.database }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { throw ArchiveTestError.database }
    return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0)))
}
