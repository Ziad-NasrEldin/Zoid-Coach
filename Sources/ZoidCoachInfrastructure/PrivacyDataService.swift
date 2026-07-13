import Foundation
import SQLite3

private let privacySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct PrivacyStoredDataClass: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let recordCount: Int

    public init(id: String, title: String, detail: String, recordCount: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.recordCount = max(0, recordCount)
    }
}

public struct PrivacyStoredDataInventory: Equatable, Sendable {
    public let databasePath: String
    public let databaseBytes: Int64
    public let schemaVersion: Int
    public let dataClasses: [PrivacyStoredDataClass]

    public init(databasePath: String, databaseBytes: Int64, schemaVersion: Int, dataClasses: [PrivacyStoredDataClass]) {
        self.databasePath = databasePath
        self.databaseBytes = max(0, databaseBytes)
        self.schemaVersion = max(0, schemaVersion)
        self.dataClasses = dataClasses
    }
}

public struct PrivacyBehaviorSession: Equatable, Sendable, Identifiable {
    public let application: String
    public let startedAt: Date
    public let endedAt: Date
    public let recordCount: Int

    public var id: String {
        "\(Int(startedAt.timeIntervalSince1970)):\(Int(endedAt.timeIntervalSince1970)):\(application)"
    }

    public init(application: String, startedAt: Date, endedAt: Date, recordCount: Int) {
        self.application = application
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.recordCount = max(1, recordCount)
    }
}

public final class PrivacyDataService: @unchecked Sendable {
    private let database: OpaquePointer
    private let databaseURL: URL
    private let exportRoot: URL

    public init(databaseURL: URL, exportRoot: URL? = nil) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        self.databaseURL = databaseURL
        self.exportRoot = exportRoot
            ?? databaseURL.deletingLastPathComponent().appendingPathComponent("Diagnostics", isDirectory: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else { throw PrivacyDataServiceError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func storedDataInventory() throws -> PrivacyStoredDataInventory {
        let definitions: [(String, String, String, [String])] = [
            ("plans", "Plans and task activity", "Daily plans, revisions, task status, estimates, and scheduling requests.", ["daily_plans", "daily_plan_items", "daily_plan_entries", "daily_plan_revisions", "task_execution_states", "task_activity_intervals", "task_history", "plan_schedule_requests"]),
            ("behavior", "Behavior evidence", "Local activity summaries, extracted facts, and app-owned screenshot indexes. Source screenshots are never owned or deleted by Zoid 666.", ["behavior_records", "screenshot_analyses", "screenshot_artifacts", "extracted_facts"]),
            ("prompts", "Prompts and responses", "Local coaching prompts, responses, and their durable effects.", ["prompt_episodes", "prompt_responses", "prompt_response_effects"]),
            ("meetings", "Meeting suggestions", "Locally extracted meeting candidates and encrypted supporting evidence.", ["meeting_candidates", "meeting_evidence"]),
            ("learning", "Learned estimates and rules", "Local estimate samples, aggregates, and planner trust history.", ["learning_samples", "learning_aggregates", "planner_trust_cycles"]),
            ("voice", "Voice conversations", "Local voice sessions, turns, confirmed memory facts, approvals, and tool history.", ["voice_sessions", "conversation_turns", "conversation_memory_facts", "voice_tool_invocations", "voice_approval_requests"]),
            ("ai", "AI request metadata", "Local provider run metadata, cache records, Codex jobs, and transmission receipts. Credentials are stored separately in Keychain.", ["model_runs", "codex_jobs", "screen_context_transmissions"]),
            ("settings", "Settings and diagnostics", "Versioned local policy, source checkpoints, notification delivery results, action audit, and saved Today snapshots.", ["policy_versions", "settings", "source_checkpoints", "processing_checkpoints", "notification_delivery_events", "action_commands", "action_attempts", "today_snapshots"])
        ]
        let classes = try definitions.map { definition in
            PrivacyStoredDataClass(
                id: definition.0,
                title: definition.1,
                detail: definition.2,
                recordCount: try definition.3.reduce(into: 0) { total, table in
                    guard try tableExists(table) else { return }
                    total += try scalar("SELECT COUNT(*) FROM \(quotedIdentifier(table));")
                }
            )
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return PrivacyStoredDataInventory(
            databasePath: databaseURL.path,
            databaseBytes: size,
            schemaVersion: try scalar("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"),
            dataClasses: classes
        )
    }

    public func exportRedactedDiagnostics(now: Date = Date(), destinationURL: URL? = nil) throws -> URL {
        let payload: [String: Any] = [
            "generatedAtUTC": ISO8601DateFormatter().string(from: now),
            "schemaVersion": try scalar("SELECT COALESCE(MAX(version), 0) FROM schema_migrations;"),
            "actionCounts": try groupedCounts("SELECT state, COUNT(*) FROM action_commands GROUP BY state;"),
            "sourceCounts": try groupedCounts("SELECT state, COUNT(*) FROM source_checkpoints GROUP BY state;"),
            "promptCounts": try groupedCounts("SELECT state, COUNT(*) FROM prompt_episodes GROUP BY state;"),
            "meetingCounts": try groupedCounts("SELECT state, COUNT(*) FROM meeting_candidates GROUP BY state;"),
            "note": "Titles, conversation text, URLs, file paths, event names, and payloads are excluded."
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = destinationURL
            ?? exportRoot.appendingPathComponent("zoid-666-redacted-\(formatter.string(from: now)).json")
        guard url.pathExtension.lowercased() == "json" else {
            throw PrivacyDataServiceError.invalidExportDestination
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            throw PrivacyDataServiceError.invalidExportDestination
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func recentBehaviorSessions(limit: Int = 12, maximumGap: TimeInterval = 300) throws -> [PrivacyBehaviorSession] {
        guard limit > 0 else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT epoch, app_name FROM behavior_records ORDER BY epoch ASC;", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PrivacyDataServiceError.read }
        defer { sqlite3_finalize(statement) }
        var sessions: [PrivacyBehaviorSession] = []
        var currentApplication: String?
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0
        var currentCount = 0
        func finishCurrent() {
            guard let currentApplication, currentCount > 0 else { return }
            sessions.append(.init(
                application: currentApplication,
                startedAt: Date(timeIntervalSince1970: currentStart),
                endedAt: Date(timeIntervalSince1970: currentEnd),
                recordCount: currentCount
            ))
        }
        while sqlite3_step(statement) == SQLITE_ROW, let app = sqlite3_column_text(statement, 1) {
            let epoch = TimeInterval(sqlite3_column_int64(statement, 0))
            let application = String(cString: app)
            if currentCount == 0 {
                currentApplication = application
                currentStart = epoch
                currentEnd = epoch
                currentCount = 1
            } else if currentApplication == application, epoch - currentEnd <= maximumGap {
                currentEnd = epoch
                currentCount += 1
            } else {
                finishCurrent()
                currentApplication = application
                currentStart = epoch
                currentEnd = epoch
                currentCount = 1
            }
        }
        finishCurrent()
        return Array(sessions.suffix(limit).reversed())
    }

    public func deleteBehaviorSession(_ session: PrivacyBehaviorSession) throws -> Int {
        guard session.startedAt <= session.endedAt else { throw PrivacyDataServiceError.invalidRange }
        var statement: OpaquePointer?
        let sql = "DELETE FROM behavior_records WHERE epoch >= ? AND epoch <= ? AND app_name = ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PrivacyDataServiceError.write }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(session.startedAt.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(session.endedAt.timeIntervalSince1970))
        bind(session.application, statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PrivacyDataServiceError.write }
        return Int(sqlite3_changes(database))
    }

    public func deleteRawBehaviorMetadata() throws -> Int {
        try deleteFromTables([
            "meeting_evidence", "extracted_facts", "screenshot_artifacts",
            "screenshot_analyses", "behavior_records"
        ])
    }

    public func deleteAIRequestMetadata() throws -> Int {
        try deleteFromTables(["screen_context_transmissions", "codex_jobs", "model_runs"])
    }

    public func deleteReviewsAndLearnedRules() throws -> Int {
        try deleteFromTables([
            "daily_review_corrections",
            "daily_reviews",
            "weekly_review_experiments",
            "app_classification_correction_rules",
            "learning_samples",
            "learning_aggregates",
            "planner_trust_cycles",
        ])
    }

    public func deleteAllUserData() throws -> Int {
        let preserved = Set(["schema_migrations", "sqlite_sequence"])
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PrivacyDataServiceError.read }
        var tables: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 0) {
            let table = String(cString: name)
            if !preserved.contains(table) { tables.append(table) }
        }
        sqlite3_finalize(statement)
        return try deleteFromTables(tables)
    }

    public func deleteExtractedConversationText() throws -> Int {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw PrivacyDataServiceError.write }
        var changed = 0
        do {
            try execute("DELETE FROM extracted_facts WHERE fact_type IN ('ocr_text', 'ocr_text_blocks');", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("DELETE FROM prompt_response_effects WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE prompt_type = 'MEETING_CANDIDATE');", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("DELETE FROM prompt_responses WHERE prompt_id IN (SELECT id FROM prompt_episodes WHERE prompt_type = 'MEETING_CANDIDATE');", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("DELETE FROM prompt_episodes WHERE prompt_type = 'MEETING_CANDIDATE';", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("DELETE FROM action_attempts WHERE command_id IN (SELECT id FROM action_commands WHERE action_type = 'createConfirmedMeeting' OR (action_type = 'createReminder' AND entity_id IN (SELECT source_day || ':' || epoch FROM meeting_candidates)));", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("DELETE FROM action_commands WHERE action_type = 'createConfirmedMeeting' OR (action_type = 'createReminder' AND entity_id IN (SELECT source_day || ':' || epoch FROM meeting_candidates));", bindings: [])
            changed += Int(sqlite3_changes(database))
            try execute("UPDATE meeting_candidates SET title = 'Private meeting', participants_json = '[]', start_expression = '', location = NULL, call_link = NULL, source_evidence = '' WHERE title != 'Private meeting' OR COALESCE(participants_json, '[]') != '[]' OR COALESCE(start_expression, '') != '' OR location IS NOT NULL OR call_link IS NOT NULL OR COALESCE(source_evidence, '') != '';", bindings: [])
            changed += Int(sqlite3_changes(database))
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw PrivacyDataServiceError.write }
            return changed
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    public func deleteDateRange(start: Date, end: Date) throws -> Int {
        guard start < end else { throw PrivacyDataServiceError.invalidRange }
        let startDay = Self.dayKey(start)
        let endDay = Self.dayKey(end)
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw PrivacyDataServiceError.write }
        var deleted = 0
        do {
            // Delete every local-day keyed planning projection, not only the legacy
            // daily_plan_entries projection. The canonical planner tables are kept
            // alongside the UI projection and must disappear from the same range.
            try execute("DELETE FROM daily_plan_items WHERE plan_id IN (SELECT id FROM daily_plans WHERE local_day >= ? AND local_day < ?);", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM daily_plans WHERE local_day >= ? AND local_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM scheduled_blocks WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM daily_plan_revisions WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM plan_undo_requests WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM plan_schedule_requests WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM today_snapshots WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM gaming_reward_ledger WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM planner_trust_cycles WHERE local_day >= ? AND local_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM domain_events WHERE local_day >= ? AND local_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            let iso8601 = ISO8601DateFormatter()
            try execute("DELETE FROM notification_delivery_events WHERE recorded_at >= ? AND recorded_at < ?;", bindings: [iso8601.string(from: start), iso8601.string(from: end)]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM meeting_evidence WHERE artifact_id IN (SELECT id FROM screenshot_artifacts WHERE behavior_day >= ? AND behavior_day < ?);", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM extracted_facts WHERE artifact_id IN (SELECT id FROM screenshot_artifacts WHERE behavior_day >= ? AND behavior_day < ?);", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM screenshot_artifacts WHERE behavior_day >= ? AND behavior_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM screenshot_analyses WHERE source_day >= ? AND source_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM meeting_candidates WHERE source_day >= ? AND source_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM behavior_records WHERE source_day >= ? AND source_day < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            try execute("DELETE FROM daily_plan_entries WHERE day_key >= ? AND day_key < ?;", bindings: [startDay, endDay]); deleted += Int(sqlite3_changes(database))
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw PrivacyDataServiceError.write }
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
        return deleted
    }

    private func scalar(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw PrivacyDataServiceError.read }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw PrivacyDataServiceError.read }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func groupedCounts(_ sql: String) throws -> [String: Int] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw PrivacyDataServiceError.read }
        defer { sqlite3_finalize(statement) }
        var result: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW, let key = sqlite3_column_text(statement, 0) {
            result[String(cString: key)] = Int(sqlite3_column_int64(statement, 1))
        }
        return result
    }

    private func deleteFromTables(_ tables: [String]) throws -> Int {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            throw PrivacyDataServiceError.write
        }
        var changed = 0
        do {
            guard sqlite3_exec(database, "PRAGMA defer_foreign_keys = ON;", nil, nil, nil) == SQLITE_OK else {
                throw PrivacyDataServiceError.write
            }
            for table in tables where try tableExists(table) {
                try execute("DELETE FROM \(quotedIdentifier(table));", bindings: [])
                changed += Int(sqlite3_changes(database))
            }
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw PrivacyDataServiceError.write
            }
            return changed
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func tableExists(_ table: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PrivacyDataServiceError.read }
        defer { sqlite3_finalize(statement) }
        bind(table, statement, 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func execute(_ sql: String, bindings: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw PrivacyDataServiceError.write }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() { bind(value, statement, Int32(offset + 1)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PrivacyDataServiceError.write }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, privacySQLiteTransient) }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public enum PrivacyDataServiceError: Error {
    case openDatabase
    case read
    case write
    case invalidRange
    case invalidExportDestination
}
