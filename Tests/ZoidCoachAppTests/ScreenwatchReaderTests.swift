import Foundation
import Testing
@testable import ZoidCoachApp

@Test
func screenwatchReaderReportsHealthySchemaValidStream() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-09", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)

    let line = """
    {"t":"12-00-00","epoch":1783581600,"app":"Test","window":"Fixture","url":"","img":true}

    """
    try Data(line.utf8).write(to: day.appendingPathComponent("log.jsonl"))

    let reader = ScreenwatchReader(baseDirectory: root)
    let now = Date(timeIntervalSince1970: 1_783_581_620)
    let result = await reader.inspect(now: now)

    #expect(result.state == .healthy)
    #expect(result.detail == "Live stream updated 20s ago")
    #expect(result.evidence == "1 records parsed · 1 image references")

    try FileManager.default.removeItem(at: root)
}

@Test
func screenwatchReaderReportsMissingDailyStream() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let reader = ScreenwatchReader(baseDirectory: root)
    let now = Date(timeIntervalSince1970: 1_783_581_620)

    let result = await reader.inspect(now: now)

    #expect(result.state == .unavailable)
    #expect(result.detail == "Today’s telemetry stream is missing")
}
