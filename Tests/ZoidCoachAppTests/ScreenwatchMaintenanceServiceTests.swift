import Foundation
import SQLite3
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func historicalScreenwatchBackfillInvokesEachCompletedDayExactlyOnce() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try makeScreenwatchDay("2026-07-07", in: root)
    try makeScreenwatchDay("2026-07-08", in: root)
    try makeScreenwatchDay("2026-07-10", in: root)
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let invocations = DayInvocationRecorder()
    let service = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: root,
        ingestDay: { _, day in
            invocations.record(day)
            return ScreenwatchIngestionResult(insertedCount: 2, totalRecordsRead: 2)
        }
    )
    let now = try #require(utcDate("2026-07-10T12:00:00Z"))

    let first = try service.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)
    let second = try service.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)

    #expect(first.historicalDaysDiscovered == 2)
    #expect(first.historicalDaysIngested == 2)
    #expect(first.observationsInserted == 4)
    #expect(second.historicalDaysIngested == 0)
    #expect(second.historicalDaysSkipped == 2)
    #expect(invocations.count == 2)
}

@Test
func historicalScreenwatchCheckpointsAreScopedToOpenedSourceIdentity() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("screenwatch-history-source-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let firstSource = root.appendingPathComponent("first", isDirectory: true)
    let secondSource = root.appendingPathComponent("second", isDirectory: true)
    try makeScreenwatchDay("2026-07-07", in: firstSource)
    try makeScreenwatchDay("2026-07-07", in: secondSource)
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let invocations = DayInvocationRecorder()
    let first = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: firstSource,
        ingestDay: { _, day in
            invocations.record(day)
            return .init(insertedCount: 1, totalRecordsRead: 1)
        }
    )
    let second = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: secondSource,
        ingestDay: { _, day in
            invocations.record(day)
            return .init(insertedCount: 1, totalRecordsRead: 1)
        }
    )
    let now = try #require(utcDate("2026-07-10T12:00:00Z"))

    let firstReport = try first.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)
    let secondReport = try second.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)

    #expect(firstReport.historicalDaysIngested == 1)
    #expect(secondReport.historicalDaysIngested == 1)
    #expect(secondReport.historicalDaysSkipped == 0)
    #expect(invocations.count == 2)
}

@Test
func screenwatchMaintenanceEnforcesIndependentRetentionAndAuditsTheRun() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let oldDay = root.appendingPathComponent("2026-06-01", isDirectory: true)
    let recentDay = root.appendingPathComponent("2026-07-09", isDirectory: true)
    try FileManager.default.createDirectory(at: oldDay, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: recentDay, withIntermediateDirectories: true)
    let oldImage = oldDay.appendingPathComponent("09-00-00.jpg")
    let recentImage = recentDay.appendingPathComponent("09-00-00.jpg")
    try Data([1]).write(to: oldImage)
    try Data([2]).write(to: recentImage)
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let service = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: root,
        ingestDay: { _, _ in ScreenwatchIngestionResult(insertedCount: 0, totalRecordsRead: 0) }
    )
    try seedRetentionEvidence(databaseURL: databaseURL, oldImage: oldImage, recentImage: recentImage)
    let now = try #require(utcDate("2026-07-10T12:00:00Z"))

    let report = try service.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)

    #expect(report.rawScreenshotFilesDeleted == 0)
    #expect(report.rawScreenshotReferencesRedacted == 2)
    #expect(report.extractedFactsDeleted == 1)
    #expect(report.behaviorTextRowsRedacted == 1)
    #expect(report.diagnosticsPurged == 4)
    #expect(report.health == .healthy)
    #expect(FileManager.default.fileExists(atPath: oldImage.path))
    #expect(FileManager.default.fileExists(atPath: recentImage.path))
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM extracted_facts WHERE id = 'old-fact';") == 0)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM behavior_records WHERE epoch = 1780304400 AND screenshot_path IS NULL AND window_title = '' AND url = '';") == 1)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM behavior_records WHERE epoch = 1783591200 AND screenshot_path IS NOT NULL AND window_title = 'Recent title';") == 1)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM source_checkpoints WHERE source_id = 'screenwatch-maintenance' AND state = 'healthy';") == 1)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM domain_events WHERE event_type = 'screenwatch.maintenance.completed';") == 1)
}

@Test
func screenwatchMaintenanceDryRunNeverMutatesFilesDatabaseOrCheckpoints() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try makeScreenwatchDay("2026-06-01", in: root)
    let oldImage = root.appendingPathComponent("2026-06-01/09-00-00.jpg")
    try Data([1]).write(to: oldImage)
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let invocations = DayInvocationRecorder()
    let service = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: root,
        ingestDay: { _, day in
            invocations.record(day)
            return ScreenwatchIngestionResult(insertedCount: 1, totalRecordsRead: 1)
        }
    )
    try maintenanceExec(databaseURL, """
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at)
    VALUES ('2026-06-01', 1780304400, '09-00-00', 'WhatsApp', 'Old title', 'https://private', 1, '\(oldImage.path)', '2026-06-01T09:00:00Z');
    """)
    let now = try #require(utcDate("2026-07-10T12:00:00Z"))

    let report = try service.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now, mode: .dryRun)

    #expect(report.historicalDaysPending == 1)
    #expect(report.rawScreenshotFilesEligible == 0)
    #expect(report.rawScreenshotFilesDeleted == 0)
    #expect(report.rawScreenshotReferencesEligible == 1)
    #expect(invocations.count == 0)
    #expect(FileManager.default.fileExists(atPath: oldImage.path))
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM behavior_records WHERE screenshot_path IS NOT NULL;") == 1)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM processing_checkpoints;") == 0)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM domain_events;") == 0)
}

@Test
func screenwatchMaintenanceAppliesIndependentBehaviorSessionPromptAndReviewRetention() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("policy-retention-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("zoid.sqlite")
    let service = try ScreenwatchMaintenanceService(
        databaseURL: databaseURL,
        screenwatchDirectory: root,
        ingestDay: { _, _ in .init(insertedCount: 0, totalRecordsRead: 0) }
    )
    try maintenanceExec(databaseURL, """
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at)
    VALUES ('2024-01-01', 1704067200, '00-00-00', 'Old App', '', '', 0, NULL, '2024-01-01T00:00:00Z');
    INSERT INTO task_activity_intervals(task_id, started_at, ended_at)
    VALUES ('old-task', '2024-01-01T00:00:00Z', '2024-01-01T01:00:00Z');
    INSERT INTO prompt_episodes(id, decision_key, prompt_type, state, title, summary, action_token, payload_json, created_at_utc)
    VALUES ('old-prompt', 'old-decision', 'ONBOARDING_DELIVERY_TEST', 'dismissed', 'Old', 'Old', 'old-token', '{}', '2024-01-01T00:00:00Z');
    INSERT INTO learning_samples(id, sample_type, context_key, actual_value, timezone_identifier, evidence_id, occurred_at_utc)
    VALUES ('old-learning', 'estimate', 'task', 10, 'UTC', 'old-evidence', '2024-01-01T00:00:00Z');
    """)
    let now = try #require(utcDate("2026-07-10T12:00:00Z"))

    let report = try service.run(policy: .defaults(timeZoneIdentifier: "UTC"), now: now)

    #expect(report.policyRecordsEligible == 4)
    #expect(report.policyRecordsPurged == 4)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM behavior_records;") == 0)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM task_activity_intervals;") == 0)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM prompt_episodes;") == 0)
    #expect(try maintenanceScalar(databaseURL, "SELECT COUNT(*) FROM learning_samples;") == 0)
}

private final class DayInvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var days: [Date] = []

    var count: Int { lock.withLock { days.count } }
    func record(_ day: Date) { lock.withLock { days.append(day) } }
}

private func makeScreenwatchDay(_ key: String, in root: URL) throws {
    let directory = root.appendingPathComponent(key, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: directory.appendingPathComponent("log.jsonl"))
}

private func utcDate(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
}

private func seedRetentionEvidence(databaseURL: URL, oldImage: URL, recentImage: URL) throws {
    try maintenanceExec(databaseURL, """
    INSERT INTO behavior_records(source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at) VALUES
      ('2026-06-01', 1780304400, '09-00-00', 'WhatsApp', 'Old title', 'https://private', 1, '\(oldImage.path)', '2026-06-01T09:00:00Z'),
      ('2026-07-09', 1783591200, '09-00-00', 'Safari', 'Recent title', 'https://recent', 1, '\(recentImage.path)', '2026-07-09T09:00:00Z');
    INSERT INTO screenshot_artifacts(id, behavior_day, behavior_epoch, path, content_hash, perceptual_fingerprint, ocr_state, extractor_version, retention_until_utc, created_at_utc) VALUES
      ('old-artifact', '2026-06-01', 1780304400, '\(oldImage.path)', 'old-hash', 'old-print', 'recognized', 1, '2026-07-01T00:00:00Z', '2026-06-01T09:00:00Z'),
      ('recent-artifact', '2026-07-09', 1783591200, '\(recentImage.path)', 'recent-hash', 'recent-print', 'recognized', 1, '2026-08-08T00:00:00Z', '2026-07-09T09:00:00Z');
    INSERT INTO extracted_facts(id, artifact_id, fact_type, schema_version, confidence, encrypted_payload, evidence_hash, created_at_utc)
      VALUES ('old-fact', 'old-artifact', 'ocr_text_blocks', 1, 0.9, X'01', 'evidence', '2026-06-01T09:00:00Z');
    INSERT INTO meeting_evidence(candidate_id, artifact_id, evidence_hash) VALUES ('candidate', 'old-artifact', 'evidence');
    INSERT INTO screenshot_analyses(source_day, epoch, outcome, processed_at) VALUES ('2026-06-01', 1780304400, 'recognized', '2026-06-01T09:00:00Z');
    INSERT INTO source_checkpoints(source_id, state, detail, evidence, checked_at) VALUES ('old-source', 'attention', 'old', 'old', '2026-06-01T09:00:00Z');
    INSERT INTO model_runs(id, provider, model, schema_version, prompt_version, normalized_input_hash, validation_state, redacted_diagnostic, started_at_utc)
      VALUES ('old-run', 'local', 'test', 1, 1, 'input', 'failed', 'old diagnostic', '2026-06-01T09:00:00Z');
    INSERT INTO processing_checkpoints(source_id, byte_offset, missed_trigger_at_utc, diagnostic)
      VALUES ('old-processing', 0, '2026-06-01T09:00:00Z', 'old diagnostic');
    """)
}

private func maintenanceExec(_ databaseURL: URL, _ sql: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else { throw MaintenanceTestError.database }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw MaintenanceTestError.database }
}

private func maintenanceScalar(_ databaseURL: URL, _ sql: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw MaintenanceTestError.database }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw MaintenanceTestError.database }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw MaintenanceTestError.database }
    return Int(sqlite3_column_int64(statement, 0))
}

private enum MaintenanceTestError: Error { case database }
