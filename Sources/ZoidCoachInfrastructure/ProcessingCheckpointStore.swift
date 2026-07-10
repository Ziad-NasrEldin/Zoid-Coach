import Foundation
import SQLite3
import ZoidCoachCore

public struct ProcessingCheckpoint: Equatable, Sendable {
    public let sourceID: String
    public let lastSuccessAt: Date?
    public let lastScheduledLocalDay: String?
    public let lastScheduledTimeZone: String?
    public let missedTriggerAt: Date?
    public let diagnostic: String?
}

public final class ProcessingCheckpointStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else { throw ProcessingCheckpointStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func checkpoint(sourceID: String) throws -> ProcessingCheckpoint? {
        let sql = "SELECT last_success_at_utc, last_scheduled_local_day, last_scheduled_timezone, missed_trigger_at_utc, diagnostic FROM processing_checkpoints WHERE source_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProcessingCheckpointStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return ProcessingCheckpoint(
            sourceID: sourceID,
            lastSuccessAt: text(statement, 0).flatMap(formatter.date(from:)),
            lastScheduledLocalDay: text(statement, 1),
            lastScheduledTimeZone: text(statement, 2),
            missedTriggerAt: text(statement, 3).flatMap(formatter.date(from:)),
            diagnostic: text(statement, 4)
        )
    }

    public func recordSuccess(sourceID: String, at date: Date, scheduledLocalDay: String? = nil, timeZoneIdentifier: String? = nil, missedTriggerAt: Date? = nil) throws {
        let sql = """
        INSERT INTO processing_checkpoints
        (source_id, byte_offset, last_success_at_utc, last_scheduled_local_day, last_scheduled_timezone, missed_trigger_at_utc, diagnostic)
        VALUES (?, 0, ?, ?, ?, ?, NULL)
        ON CONFLICT(source_id) DO UPDATE SET
            last_success_at_utc = excluded.last_success_at_utc,
            last_scheduled_local_day = COALESCE(excluded.last_scheduled_local_day, processing_checkpoints.last_scheduled_local_day),
            last_scheduled_timezone = COALESCE(excluded.last_scheduled_timezone, processing_checkpoints.last_scheduled_timezone),
            missed_trigger_at_utc = excluded.missed_trigger_at_utc,
            diagnostic = NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProcessingCheckpointStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, statement, 1)
        bind(formatter.string(from: date), statement, 2)
        bindOptional(scheduledLocalDay, statement, 3)
        bindOptional(timeZoneIdentifier, statement, 4)
        bindOptional(missedTriggerAt.map(formatter.string(from:)), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProcessingCheckpointStoreError.write }
    }

    public func recordFailure(sourceID: String, at date: Date, diagnostic: String) throws {
        let sql = """
        INSERT INTO processing_checkpoints(source_id, byte_offset, diagnostic)
        VALUES (?, 0, ?)
        ON CONFLICT(source_id) DO UPDATE SET diagnostic = excluded.diagnostic;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ProcessingCheckpointStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, statement, 1)
        bind(String(diagnostic.prefix(240)), statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ProcessingCheckpointStoreError.write }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func bindOptional(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        if let value { bind(value, statement, index) } else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}

public enum ProcessingCheckpointStoreError: LocalizedError {
    case openDatabase, read, write
    public var errorDescription: String? { "Could not update the agent job checkpoint." }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
