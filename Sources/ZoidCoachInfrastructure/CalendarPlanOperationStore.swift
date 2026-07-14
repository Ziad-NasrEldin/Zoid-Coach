import Foundation
import SQLite3
import ZoidCoachCore

public struct CalendarPlanOperation: Equatable, Sendable {
    public enum State: String, Codable, Equatable, Sendable {
        case pending
        case completed
        case refused
    }

    public let id: UUID
    public let requestFingerprint: String
    public let normalizedDay: Date
    public let state: State
    public let preparedSchedule: PreparedAgentPlanSchedule
    public let receipt: AgentMutationReceipt?
    public let lastDiagnostic: String?
}

public final class CalendarPlanOperationStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw CalendarPlanOperationStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 1_000)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit { sqlite3_close(database) }

    public func load(id: UUID) throws -> CalendarPlanOperation? {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT request_fingerprint, normalized_day_utc, state, prepared_schedule_json,
               receipt_json, last_diagnostic
        FROM calendar_plan_operations
        WHERE operation_id = ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw CalendarPlanOperationStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let fingerprint = string(statement, 0),
              let dayRaw = string(statement, 1),
              let day = formatter.date(from: dayRaw),
              let stateRaw = string(statement, 2),
              let state = CalendarPlanOperation.State(rawValue: stateRaw),
              let preparedData = data(statement, 3),
              let prepared = try? decoder.decode(PreparedAgentPlanSchedule.self, from: preparedData) else {
            throw CalendarPlanOperationStoreError.read
        }
        let receipt = data(statement, 4).flatMap { try? decoder.decode(AgentMutationReceipt.self, from: $0) }
        if state != .pending, receipt == nil {
            throw CalendarPlanOperationStoreError.read
        }
        return CalendarPlanOperation(
            id: id,
            requestFingerprint: fingerprint,
            normalizedDay: day,
            state: state,
            preparedSchedule: prepared,
            receipt: receipt,
            lastDiagnostic: string(statement, 5)
        )
    }

    @discardableResult
    public func begin(
        id: UUID,
        requestFingerprint: String,
        normalizedDay: Date,
        preparedSchedule: PreparedAgentPlanSchedule,
        requestedAt: Date = Date()
    ) throws -> CalendarPlanOperation {
        lock.lock()
        defer { lock.unlock() }
        let preparedData = try encoder.encode(preparedSchedule)
        let requiredData = try encoder.encode(
            preparedSchedule.requiredCommands.sorted(by: Self.requirementOrder)
        )
        let sql = """
        INSERT OR IGNORE INTO calendar_plan_operations(
            operation_id, request_fingerprint, normalized_day_utc, state,
            prepared_schedule_json, required_commands_json, requested_at_utc, updated_at_utc
        ) VALUES (?, ?, ?, 'pending', ?, ?, ?, ?);
        """
        try execute(
            sql,
            bindings: [
                .text(id.uuidString),
                .text(requestFingerprint),
                .text(formatter.string(from: normalizedDay)),
                .blob(preparedData),
                .blob(requiredData),
                .text(formatter.string(from: requestedAt)),
                .text(formatter.string(from: requestedAt))
            ]
        )
        guard let operation = try load(id: id) else {
            throw CalendarPlanOperationStoreError.write
        }
        try validate(
            operation,
            requestFingerprint: requestFingerprint,
            normalizedDay: normalizedDay
        )
        return operation
    }

    public func validate(
        _ operation: CalendarPlanOperation,
        requestFingerprint: String,
        normalizedDay: Date
    ) throws {
        guard operation.requestFingerprint == requestFingerprint,
              operation.normalizedDay == normalizedDay else {
            throw CalendarPlanOperationStoreError.operationKeyConflict
        }
    }

    public func finish(
        id: UUID,
        requestFingerprint: String,
        receipt: AgentMutationReceipt,
        at date: Date = Date()
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let operation = try load(id: id),
              operation.requestFingerprint == requestFingerprint else {
            throw CalendarPlanOperationStoreError.operationKeyConflict
        }
        if let existing = operation.receipt {
            guard existing == receipt else {
                throw CalendarPlanOperationStoreError.receiptConflict
            }
            return
        }
        let state: CalendarPlanOperation.State = receipt.accepted ? .completed : .refused
        let receiptData = try encoder.encode(receipt)
        let commandIDsData = try encoder.encode(receipt.commandIDs.sorted())
        let sql = """
        UPDATE calendar_plan_operations
        SET state = ?, command_ids_json = ?, receipt_json = ?, last_diagnostic = NULL, updated_at_utc = ?
        WHERE operation_id = ? AND request_fingerprint = ? AND state = 'pending';
        """
        try execute(
            sql,
            bindings: [
                .text(state.rawValue),
                .blob(commandIDsData),
                .blob(receiptData),
                .text(formatter.string(from: date)),
                .text(id.uuidString),
                .text(requestFingerprint)
            ]
        )
        guard sqlite3_changes(database) == 1 else {
            throw CalendarPlanOperationStoreError.write
        }
    }

    public func recordPendingFailure(
        id: UUID,
        requestFingerprint: String,
        diagnostic: String,
        at date: Date = Date()
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let redacted = diagnostic.replacingOccurrences(of: "\n", with: " ")
        try execute(
            "UPDATE calendar_plan_operations SET last_diagnostic = ?, updated_at_utc = ? WHERE operation_id = ? AND request_fingerprint = ? AND state = 'pending';",
            bindings: [
                .text(String(redacted.prefix(240))),
                .text(formatter.string(from: date)),
                .text(id.uuidString),
                .text(requestFingerprint)
            ]
        )
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw CalendarPlanOperationStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            switch value {
            case let .text(value):
                bind(value, statement, Int32(offset + 1))
            case let .blob(value):
                _ = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, Int32(offset + 1), bytes.baseAddress, Int32(value.count), sqliteTransient)
                }
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CalendarPlanOperationStoreError.write
        }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func data(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private static func requirementOrder(
        _ lhs: AgentPlanCommandRequirement,
        _ rhs: AgentPlanCommandRequirement
    ) -> Bool {
        lhs.type.rawValue == rhs.type.rawValue
            ? lhs.entityID < rhs.entityID
            : lhs.type.rawValue < rhs.type.rawValue
    }
}

private enum SQLiteBinding {
    case text(String)
    case blob(Data)
}

public enum CalendarPlanOperationStoreError: LocalizedError, Equatable {
    case openDatabase
    case read
    case write
    case operationKeyConflict
    case receiptConflict

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            return "The Calendar plan operation ledger could not open the local database."
        case .read:
            return "The Calendar plan operation ledger could not read a durable operation."
        case .write:
            return "The Calendar plan operation ledger could not durably record the operation."
        case .operationKeyConflict:
            return "This Calendar plan operation ID was already used for different reviewed inputs. Review the current plan and confirm it as a new operation."
        case .receiptConflict:
            return "This Calendar plan operation already has a different authoritative receipt."
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
