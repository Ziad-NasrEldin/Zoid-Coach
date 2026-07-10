import Foundation
import SQLite3

private let privacySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class PrivacyDataService: @unchecked Sendable {
    private let database: OpaquePointer
    private let databaseURL: URL

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        self.databaseURL = databaseURL
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else { throw PrivacyDataServiceError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func exportRedactedDiagnostics(now: Date = Date()) throws -> URL {
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
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("zoid-coach-redacted-\(formatter.string(from: now)).json")
        try data.write(to: url, options: .atomic)
        return url
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
}
