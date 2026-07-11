import Foundation
import SQLite3
import ZoidCoachCore

public final class DomainEventStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw DomainEventStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    deinit { sqlite3_close(database) }

    public func append(_ event: DomainEvent) throws {
        let sql = """
        INSERT OR IGNORE INTO domain_events
        (id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DomainEventStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(event.id, statement, 1)
        bind(event.type, statement, 2)
        if let entityID = event.entityID { bind(entityID, statement, 3) } else { sqlite3_bind_null(statement, 3) }
        bind(event.localDay, statement, 4)
        bind(event.timezoneIdentifier, statement, 5)
        bind(formatter.string(from: event.occurredAt), statement, 6)
        sqlite3_bind_int(statement, 7, Int32(event.schemaVersion))
        bind(String(decoding: try encoder.encode(event.evidenceIDs), as: UTF8.self), statement, 8)
        bind(String(decoding: try encoder.encode(event.payload), as: UTF8.self), statement, 9)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DomainEventStoreError.write }
    }

    public func events(localDay: String? = nil, limit: Int = 200) throws -> [DomainEvent] {
        let sql: String
        if localDay == nil {
            sql = "SELECT id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json FROM domain_events ORDER BY occurred_at_utc DESC, id DESC LIMIT ?;"
        } else {
            sql = "SELECT id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json FROM domain_events WHERE local_day = ? ORDER BY occurred_at_utc DESC, id DESC LIMIT ?;"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DomainEventStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if let localDay { bind(localDay, statement, index); index += 1 }
        sqlite3_bind_int(statement, index, Int32(max(1, limit)))
        var result: [DomainEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0),
              let type = text(statement, 1),
              let storedDay = text(statement, 3),
              let timezone = text(statement, 4),
              let dateRaw = text(statement, 5),
              let date = formatter.date(from: dateRaw),
              let evidenceRaw = text(statement, 7),
              let payloadRaw = text(statement, 8),
              let evidence = try? decoder.decode([String].self, from: Data(evidenceRaw.utf8)),
              let payload = try? decoder.decode([String: String].self, from: Data(payloadRaw.utf8)) {
            result.append(DomainEvent(
                id: id,
                type: type,
                entityID: text(statement, 2),
                localDay: storedDay,
                timezoneIdentifier: timezone,
                occurredAt: date,
                schemaVersion: Int(sqlite3_column_int(statement, 6)),
                evidenceIDs: evidence,
                payload: payload
            ))
        }
        return result
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}

public enum DomainEventStoreError: LocalizedError {
    case openDatabase, prepare, write
    public var errorDescription: String? { "Could not persist the autonomous action audit." }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
