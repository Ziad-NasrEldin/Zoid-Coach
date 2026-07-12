import Foundation
import SQLite3
import ZoidCoachCore

public enum ScreenwatchMaintenanceMode: Sendable {
    case apply
    case dryRun
}

public enum ScreenwatchMaintenanceHealth: String, Equatable, Sendable {
    case healthy
    case attention
}

public struct ScreenwatchMaintenanceReport: Equatable, Sendable {
    public let mode: ScreenwatchMaintenanceMode
    public let historicalDaysDiscovered: Int
    public let historicalDaysPending: Int
    public let historicalDaysIngested: Int
    public let historicalDaysSkipped: Int
    public let historicalDaysFailed: Int
    public let observationsInserted: Int
    public let rawScreenshotFilesEligible: Int
    public let rawScreenshotFilesDeleted: Int
    public let rawScreenshotReferencesEligible: Int
    public let rawScreenshotReferencesRedacted: Int
    public let extractedFactsEligible: Int
    public let extractedFactsDeleted: Int
    public let behaviorTextRowsEligible: Int
    public let behaviorTextRowsRedacted: Int
    public let diagnosticsEligible: Int
    public let diagnosticsPurged: Int
    public let failedFileDeletions: Int
    public let health: ScreenwatchMaintenanceHealth

    public var detail: String {
        if mode == .dryRun {
            return "Dry run: \(historicalDaysPending) historical days and \(rawScreenshotFilesEligible) screenshot files are eligible."
        }
        if health == .attention {
            return "Maintenance needs attention: \(historicalDaysFailed) backfills and \(failedFileDeletions) file deletions failed."
        }
        return "Maintenance completed: \(historicalDaysIngested) days ingested and \(rawScreenshotFilesDeleted) expired screenshot files deleted."
    }
}

public typealias HistoricalScreenwatchDayIngestor = @Sendable (URL, Date) throws -> ScreenwatchIngestionResult

public final class ScreenwatchMaintenanceService: @unchecked Sendable {
    private static let healthSourceID = "screenwatch-maintenance"
    private static let historySourcePrefix = "screenwatch-history:"

    private let databaseURL: URL
    private let screenwatchSource: ScreenwatchDirectoryLease
    private let fileManager: FileManager
    private let ingestDay: @Sendable (Date) throws -> ScreenwatchIngestionResult
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()

    public convenience init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        screenwatchDirectory: URL,
        fileManager: FileManager = .default,
        ingestDay: HistoricalScreenwatchDayIngestor? = nil
    ) throws {
        let source = try ScreenwatchDirectoryLease(
            rootURL: screenwatchDirectory,
            source: .defaultLocation
        )
        try self.init(
            databaseURL: databaseURL,
            screenwatchSource: source,
            fileManager: fileManager,
            ingestDay: ingestDay
        )
    }

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        screenwatchSource: ScreenwatchDirectoryLease,
        fileManager: FileManager = .default,
        ingestDay: HistoricalScreenwatchDayIngestor? = nil
    ) throws {
        self.databaseURL = databaseURL
        self.screenwatchSource = screenwatchSource
        self.fileManager = fileManager
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, fileManager: fileManager).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw ScreenwatchMaintenanceError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        if let ingestDay {
            self.ingestDay = { day in
                try ingestDay(screenwatchSource.rootURL, day)
            }
        } else {
            let archive = try ScreenwatchArchive(databaseURL: databaseURL)
            self.ingestDay = { day in
                try archive.ingestToday(from: screenwatchSource, now: day)
            }
        }
    }

    deinit { sqlite3_close(database) }

    public func run(
        policy: UserPolicy,
        now: Date = Date(),
        mode: ScreenwatchMaintenanceMode = .apply
    ) throws -> ScreenwatchMaintenanceReport {
        let policy = try policy.validated()
        let maintenanceTimeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier) ?? .current
        let historicalDays = try discoverHistoricalDays(before: now, timeZone: maintenanceTimeZone)
        let completed = try completedHistoricalDayKeys()
        let pending = historicalDays.filter { !completed.contains($0.key) }
        let retention = try retentionPlan(policy: policy, now: now)

        if mode == .dryRun {
            return makeReport(
                mode: mode,
                discovered: historicalDays.count,
                pending: pending.count,
                ingested: 0,
                skipped: historicalDays.count - pending.count,
                failed: 0,
                inserted: 0,
                retention: retention,
                applied: nil
            )
        }

        var ingested = 0
        var failed = 0
        var inserted = 0
        for day in pending {
            do {
                let result = try ingestDay(day.date)
                try recordHistoricalCheckpoint(dayKey: day.key, now: now)
                ingested += 1
                inserted += result.insertedCount
            } catch {
                failed += 1
                try recordHistoricalFailure(dayKey: day.key, error: error, now: now)
            }
        }

        let applied = try applyRetention(retention)
        let report = makeReport(
            mode: mode,
            discovered: historicalDays.count,
            pending: pending.count,
            ingested: ingested,
            skipped: historicalDays.count - pending.count,
            failed: failed,
            inserted: inserted,
            retention: retention,
            applied: applied
        )
        try recordRun(report, policy: policy, now: now)
        return report
    }

    private func discoverHistoricalDays(before now: Date, timeZone: TimeZone) throws -> [HistoricalDay] {
        let todayKey = Self.dayKey(now, timeZone: timeZone)
        let children = try screenwatchSource.entries()
        return children.compactMap { entry -> HistoricalDay? in
            let key = entry.name
            guard key < todayKey,
                  entry.isDirectory,
                  screenwatchSource.fileExists([key, "log.jsonl"]),
                  let date = Self.dayDate(key, timeZone: timeZone)
            else { return nil }
            return HistoricalDay(key: key, date: date)
        }.sorted { $0.key < $1.key }
    }

    private func completedHistoricalDayKeys() throws -> Set<String> {
        let sql = "SELECT source_id FROM processing_checkpoints WHERE source_id LIKE ? AND last_success_at_utc IS NOT NULL;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError(.prepare) }
        defer { sqlite3_finalize(statement) }
        bind(Self.historySourcePrefix + "%", statement, 1)
        var keys = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW, let source = text(statement, 0) {
            keys.insert(String(source.dropFirst(Self.historySourcePrefix.count)))
        }
        return keys
    }

    private func recordHistoricalCheckpoint(dayKey: String, now: Date) throws {
        let sql = """
        INSERT INTO processing_checkpoints
        (source_id, file_identity, byte_offset, last_record_epoch, last_success_at_utc, diagnostic)
        VALUES (?, NULL, 0, NULL, ?, NULL)
        ON CONFLICT(source_id) DO UPDATE SET
            last_success_at_utc = excluded.last_success_at_utc,
            missed_trigger_at_utc = NULL,
            diagnostic = NULL;
        """
        try execute(sql) { statement in
            bind(Self.historySourcePrefix + dayKey, statement, 1)
            bind(formatter.string(from: now), statement, 2)
        }
    }

    private func recordHistoricalFailure(dayKey: String, error: Error, now: Date) throws {
        let sql = """
        INSERT INTO processing_checkpoints
        (source_id, file_identity, byte_offset, last_record_epoch, missed_trigger_at_utc, diagnostic)
        VALUES (?, NULL, 0, NULL, ?, ?)
        ON CONFLICT(source_id) DO UPDATE SET
            missed_trigger_at_utc = excluded.missed_trigger_at_utc,
            diagnostic = excluded.diagnostic;
        """
        try execute(sql) { statement in
            bind(Self.historySourcePrefix + dayKey, statement, 1)
            bind(formatter.string(from: now), statement, 2)
            bind(Self.redactedDiagnostic(error), statement, 3)
        }
    }

    private func retentionPlan(policy: UserPolicy, now: Date) throws -> RetentionPlan {
        let calendar = Calendar(identifier: .gregorian)
        let rawCutoff = calendar.date(byAdding: .day, value: -policy.privacy.rawScreenshotRetentionDays, to: now) ?? now
        let textCutoff = calendar.date(byAdding: .day, value: -policy.privacy.extractedTextRetentionDays, to: now) ?? now
        let diagnosticCutoff = calendar.date(byAdding: .day, value: -policy.privacy.diagnosticRetentionDays, to: now) ?? now
        let rawEpoch = Int64(rawCutoff.timeIntervalSince1970)
        let textEpoch = Int64(textCutoff.timeIntervalSince1970)

        let rawReferences = try scalar(
            "SELECT (SELECT COUNT(*) FROM behavior_records WHERE epoch < ? AND screenshot_path IS NOT NULL) + (SELECT COUNT(*) FROM screenshot_artifacts WHERE behavior_epoch < ? AND path <> '');",
            bind: {
                sqlite3_bind_int64($0, 1, rawEpoch)
                sqlite3_bind_int64($0, 2, rawEpoch)
            }
        )
        let facts = try scalar(
            "SELECT COUNT(*) FROM extracted_facts WHERE artifact_id IN (SELECT id FROM screenshot_artifacts WHERE behavior_epoch < ?);",
            bind: { sqlite3_bind_int64($0, 1, textEpoch) }
        )
        let textRows = try scalar(
            "SELECT COUNT(*) FROM behavior_records WHERE epoch < ? AND (window_title <> '' OR url <> '');",
            bind: { sqlite3_bind_int64($0, 1, textEpoch) }
        )
        let diagnostics = try diagnosticCount(olderThan: formatter.string(from: diagnosticCutoff))
        return RetentionPlan(
            rawCutoffEpoch: rawEpoch,
            textCutoffEpoch: textEpoch,
            diagnosticCutoff: formatter.string(from: diagnosticCutoff),
            // Screenwatch owns its archive. Zoid expires only its local references
            // and derived evidence unless a separate destructive-source policy is added.
            screenshotFiles: [],
            rawReferences: rawReferences,
            extractedFacts: facts,
            behaviorTextRows: textRows,
            diagnostics: diagnostics
        )
    }

    private func screenshotFiles(olderThan cutoff: Date) throws -> Set<URL> {
        let cutoffKey = Self.dayKey(cutoff, timeZone: .current)
        let children = try screenwatchSource.entries()
        var result = Set<URL>()
        for day in children where day.name <= cutoffKey && day.isDirectory {
            let files = (try? screenwatchSource.entries(in: [day.name])) ?? []
            for file in files where file.isRegularFile
                && ["jpg", "jpeg", "webp"].contains(URL(fileURLWithPath: file.name).pathExtension.lowercased()) {
                let fileURL = screenwatchSource.rootURL
                    .appendingPathComponent(day.name, isDirectory: true)
                    .appendingPathComponent(file.name, isDirectory: false)
                if let capturedAt = Self.screenshotDate(
                    dayKey: day.name,
                    filename: URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent
                ) {
                    if capturedAt < cutoff { result.insert(fileURL) }
                } else if day.name < cutoffKey {
                    result.insert(fileURL)
                }
            }
        }
        return result
    }

    private func diagnosticCount(olderThan cutoff: String) throws -> Int {
        let sql = """
        SELECT
          (SELECT COUNT(*) FROM screenshot_analyses WHERE processed_at < ?) +
          (SELECT COUNT(*) FROM source_checkpoints WHERE checked_at < ?) +
          (SELECT COUNT(*) FROM model_runs WHERE started_at_utc < ? AND redacted_diagnostic IS NOT NULL) +
          (SELECT COUNT(*) FROM processing_checkpoints
             WHERE diagnostic IS NOT NULL AND COALESCE(last_success_at_utc, missed_trigger_at_utc, '') < ?);
        """
        return try scalar(sql) { statement in
            for index in 1...4 { bind(cutoff, statement, Int32(index)) }
        }
    }

    private func applyRetention(_ plan: RetentionPlan) throws -> AppliedRetention {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw databaseError(.write) }
        var transactionOpen = true
        defer {
            if transactionOpen { _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) }
        }
        do {
            var rawRedacted = 0
            rawRedacted += try executeChanges("UPDATE behavior_records SET has_screenshot = 0, screenshot_path = NULL WHERE epoch < ? AND screenshot_path IS NOT NULL;") {
                sqlite3_bind_int64($0, 1, plan.rawCutoffEpoch)
            }
            rawRedacted += try executeChanges("UPDATE screenshot_artifacts SET path = '', ocr_state = CASE WHEN ocr_state = 'pending' THEN 'raw_purged' ELSE ocr_state END WHERE behavior_epoch < ? AND path <> '';") {
                sqlite3_bind_int64($0, 1, plan.rawCutoffEpoch)
            }

            _ = try executeChanges("DELETE FROM meeting_evidence WHERE artifact_id IN (SELECT id FROM screenshot_artifacts WHERE behavior_epoch < ?);") {
                sqlite3_bind_int64($0, 1, plan.textCutoffEpoch)
            }
            let factsDeleted = try executeChanges("DELETE FROM extracted_facts WHERE artifact_id IN (SELECT id FROM screenshot_artifacts WHERE behavior_epoch < ?);") {
                sqlite3_bind_int64($0, 1, plan.textCutoffEpoch)
            }
            _ = try executeChanges("UPDATE meeting_candidates SET source_evidence = '' WHERE epoch < ? AND COALESCE(source_evidence, '') <> '';") {
                sqlite3_bind_int64($0, 1, plan.textCutoffEpoch)
            }
            let textRedacted = try executeChanges("UPDATE behavior_records SET window_title = '', url = '' WHERE epoch < ? AND (window_title <> '' OR url <> '');") {
                sqlite3_bind_int64($0, 1, plan.textCutoffEpoch)
            }
            let bothExpired = min(plan.rawCutoffEpoch, plan.textCutoffEpoch)
            _ = try executeChanges("DELETE FROM screenshot_artifacts WHERE behavior_epoch < ? AND path = '' AND id NOT IN (SELECT artifact_id FROM extracted_facts);") {
                sqlite3_bind_int64($0, 1, bothExpired)
            }

            var diagnosticsPurged = 0
            diagnosticsPurged += try executeChanges("DELETE FROM screenshot_analyses WHERE processed_at < ?;") { bind(plan.diagnosticCutoff, $0, 1) }
            diagnosticsPurged += try executeChanges("DELETE FROM source_checkpoints WHERE checked_at < ?;") { bind(plan.diagnosticCutoff, $0, 1) }
            diagnosticsPurged += try executeChanges("UPDATE model_runs SET redacted_diagnostic = NULL WHERE started_at_utc < ? AND redacted_diagnostic IS NOT NULL;") { bind(plan.diagnosticCutoff, $0, 1) }
            diagnosticsPurged += try executeChanges("UPDATE processing_checkpoints SET diagnostic = NULL WHERE diagnostic IS NOT NULL AND COALESCE(last_success_at_utc, missed_trigger_at_utc, '') < ?;") { bind(plan.diagnosticCutoff, $0, 1) }
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw databaseError(.write) }
            transactionOpen = false

            return AppliedRetention(
                filesDeleted: 0,
                rawReferencesRedacted: rawRedacted,
                extractedFactsDeleted: factsDeleted,
                behaviorTextRowsRedacted: textRedacted,
                diagnosticsPurged: diagnosticsPurged,
                failedFileDeletions: 0
            )
        } catch {
            throw error
        }
    }

    private func recordRun(_ report: ScreenwatchMaintenanceReport, policy: UserPolicy, now: Date) throws {
        let evidence = "days=\(report.historicalDaysIngested),observations=\(report.observationsInserted),files=\(report.rawScreenshotFilesDeleted),facts=\(report.extractedFactsDeleted),diagnostics=\(report.diagnosticsPurged)"
        try execute("INSERT INTO source_checkpoints(source_id, state, detail, evidence, checked_at) VALUES (?, ?, ?, ?, ?);") { statement in
            bind(Self.healthSourceID, statement, 1)
            bind(report.health.rawValue, statement, 2)
            bind(report.detail, statement, 3)
            bind(evidence, statement, 4)
            bind(formatter.string(from: now), statement, 5)
        }
        let event = DomainEvent(
            id: UUID().uuidString,
            type: report.health == .healthy ? "screenwatch.maintenance.completed" : "screenwatch.maintenance.attention",
            entityID: "screenwatch",
            localDay: Self.dayKey(now, timeZone: TimeZone(identifier: policy.schedule.timeZoneIdentifier) ?? .current),
            timezoneIdentifier: policy.schedule.timeZoneIdentifier,
            occurredAt: now,
            evidenceIDs: [],
            payload: [
                "historical_days_ingested": String(report.historicalDaysIngested),
                "observations_inserted": String(report.observationsInserted),
                "raw_files_deleted": String(report.rawScreenshotFilesDeleted),
                "extracted_facts_deleted": String(report.extractedFactsDeleted),
                "diagnostics_purged": String(report.diagnosticsPurged),
                "failed_operations": String(report.historicalDaysFailed + report.failedFileDeletions)
            ]
        )
        try DomainEventStore(databaseURL: databaseURL).append(event)
    }

    private func makeReport(
        mode: ScreenwatchMaintenanceMode,
        discovered: Int,
        pending: Int,
        ingested: Int,
        skipped: Int,
        failed: Int,
        inserted: Int,
        retention: RetentionPlan,
        applied: AppliedRetention?
    ) -> ScreenwatchMaintenanceReport {
        let failedFiles = applied?.failedFileDeletions ?? 0
        return ScreenwatchMaintenanceReport(
            mode: mode,
            historicalDaysDiscovered: discovered,
            historicalDaysPending: pending,
            historicalDaysIngested: ingested,
            historicalDaysSkipped: skipped,
            historicalDaysFailed: failed,
            observationsInserted: inserted,
            rawScreenshotFilesEligible: retention.screenshotFiles.count,
            rawScreenshotFilesDeleted: applied?.filesDeleted ?? 0,
            rawScreenshotReferencesEligible: retention.rawReferences,
            rawScreenshotReferencesRedacted: applied?.rawReferencesRedacted ?? 0,
            extractedFactsEligible: retention.extractedFacts,
            extractedFactsDeleted: applied?.extractedFactsDeleted ?? 0,
            behaviorTextRowsEligible: retention.behaviorTextRows,
            behaviorTextRowsRedacted: applied?.behaviorTextRowsRedacted ?? 0,
            diagnosticsEligible: retention.diagnostics,
            diagnosticsPurged: applied?.diagnosticsPurged ?? 0,
            failedFileDeletions: failedFiles,
            health: failed + failedFiles == 0 ? .healthy : .attention
        )
    }

    private func isInsideScreenwatchDirectory(_ url: URL) -> Bool {
        let directory = screenwatchSource.rootURL.path
        let root = directory.hasSuffix("/") ? directory : directory + "/"
        return url.path.hasPrefix(root)
    }

    private func strings(_ sql: String, bind binder: (OpaquePointer) -> Void) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError(.prepare) }
        defer { sqlite3_finalize(statement) }
        binder(statement)
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, let value = text(statement, 0) { result.append(value) }
        return result
    }

    private func scalar(_ sql: String, bind binder: (OpaquePointer) -> Void) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError(.prepare) }
        defer { sqlite3_finalize(statement) }
        binder(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError(.read) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(_ sql: String, bind binder: (OpaquePointer) -> Void) throws {
        _ = try executeChanges(sql, bind: binder)
    }

    private func executeChanges(_ sql: String, bind binder: (OpaquePointer) -> Void) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError(.prepare) }
        defer { sqlite3_finalize(statement) }
        binder(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
        return Int(sqlite3_changes(database))
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT_MAINTENANCE) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func databaseError(_ operation: ScreenwatchMaintenanceError.Operation) -> ScreenwatchMaintenanceError {
        let message = sqlite3_errmsg(database).map(String.init(cString:)) ?? "unknown SQLite error"
        return .database(operation, message)
    }

    private static func redactedDiagnostic(_ error: Error) -> String {
        String(String(describing: type(of: error)).prefix(120))
    }

    private static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func dayDate(_ key: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter.date(from: key + " 12:00:00")
    }

    private static func screenshotDate(dayKey: String, filename: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        formatter.isLenient = false
        return formatter.date(from: dayKey + " " + filename)
    }
}

private struct HistoricalDay {
    let key: String
    let date: Date
}

private struct RetentionPlan {
    let rawCutoffEpoch: Int64
    let textCutoffEpoch: Int64
    let diagnosticCutoff: String
    let screenshotFiles: Set<URL>
    let rawReferences: Int
    let extractedFacts: Int
    let behaviorTextRows: Int
    let diagnostics: Int
}

private struct AppliedRetention {
    let filesDeleted: Int
    let rawReferencesRedacted: Int
    let extractedFactsDeleted: Int
    let behaviorTextRowsRedacted: Int
    let diagnosticsPurged: Int
    let failedFileDeletions: Int
}

public enum ScreenwatchMaintenanceError: LocalizedError {
    public enum Operation: String, Sendable { case prepare, read, write }
    case openDatabase
    case database(Operation, String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            "Could not open Screenwatch maintenance storage."
        case let .database(operation, message):
            "Screenwatch maintenance database \(operation.rawValue) failed: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT_MAINTENANCE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
