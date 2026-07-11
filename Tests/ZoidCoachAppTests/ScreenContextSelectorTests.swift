import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func screenContextSelectsNewestDistinctFramesAndSuppressesPerceptualDuplicates() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-screen-context-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("zoid.sqlite")
    try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
    let oldPath = directory.appendingPathComponent("old.webp")
    let newerDuplicatePath = directory.appendingPathComponent("newer.webp")
    let newestDistinctPath = directory.appendingPathComponent("newest.webp")
    try Data([1]).write(to: oldPath)
    try Data([2]).write(to: newerDuplicatePath)
    try Data([3]).write(to: newestDistinctPath)
    try insertScreenshot(databaseURL, id: "shot-1", epoch: 100, path: oldPath.path, hash: "hash-1", fingerprint: "same")
    try insertScreenshot(databaseURL, id: "shot-2", epoch: 200, path: newerDuplicatePath.path, hash: "hash-2", fingerprint: "same")
    try insertScreenshot(databaseURL, id: "shot-3", epoch: 300, path: newestDistinctPath.path, hash: "hash-3", fingerprint: "different")
    let selector = try ScreenContextSelector(databaseURL: databaseURL)

    let selection = try selector.select(
        reason: "Look at the current screen",
        limit: 3,
        mayTransmitPrivateContent: true
    )

    #expect(selection.artifactIDs == ["shot-3", "shot-2"])
    #expect(selection.paths == [newestDistinctPath.path, newerDuplicatePath.path])
    #expect(selection.contentHashes == ["hash-3", "hash-2"])
    #expect(selection.mayTransmitPrivateContent)
}

private func insertScreenshot(
    _ databaseURL: URL,
    id: String,
    epoch: Int,
    path: String,
    hash: String,
    fingerprint: String
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { throw ScreenContextTestError.database }
    defer { sqlite3_close(database) }
    let sql = """
    INSERT INTO screenshot_artifacts
    (id, behavior_day, behavior_epoch, path, content_hash, perceptual_fingerprint, ocr_state, extractor_version, retention_until_utc, created_at_utc)
    VALUES ('\(id)', '2026-07-10', \(epoch), '\(path)', '\(hash)', '\(fingerprint)', 'pending', 1, '2027-01-01T00:00:00Z', '2026-07-10T00:00:00Z');
    """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw ScreenContextTestError.database }
}

private enum ScreenContextTestError: Error { case database }
