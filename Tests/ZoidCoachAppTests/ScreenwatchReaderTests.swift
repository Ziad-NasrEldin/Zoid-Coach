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
    #expect(result.evidence == "1 record parsed · 1 image reference")

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

@Test
func screenwatchReaderNamesAChangedSchemaWithoutExposingCapturedContent() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-09", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let privateTitle = "Secret client acquisition plan"
    let line = """
    {"timestamp":1783581600,"application":"Test","privateTitle":"\(privateTitle)"}

    """
    try Data(line.utf8).write(to: day.appendingPathComponent("log.jsonl"))

    let result = await ScreenwatchReader(baseDirectory: root).inspect(
        now: Date(timeIntervalSince1970: 1_783_581_620)
    )

    #expect(result.state == .attention)
    #expect(result.detail == "Screenwatch source format is unsupported")
    #expect(result.evidence.contains("1 complete record did not match the expected schema"))
    #expect(!result.evidence.contains(privateTitle))
    #expect(result.actionTitle == "Repair")
}

@Test
func screenwatchReaderFlagsAMixedSchemaWhileRetainingValidFreshness() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let day = root.appendingPathComponent("2026-07-09", isDirectory: true)
    try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let lines = """
    {"t":"12-00-00","epoch":1783581600,"app":"Test","window":"Fixture","url":"","img":false}
    {"timestamp":1783581610,"application":"Changed"}

    """
    try Data(lines.utf8).write(to: day.appendingPathComponent("log.jsonl"))

    let result = await ScreenwatchReader(baseDirectory: root).inspect(
        now: Date(timeIntervalSince1970: 1_783_581_620)
    )

    #expect(result.state == .attention)
    #expect(result.detail == "Some Screenwatch records use an unsupported format")
    #expect(result.evidence == "1 record parsed · 0 image references · 1 unsupported schema record")
    #expect(result.actionTitle == "Repair")
}
