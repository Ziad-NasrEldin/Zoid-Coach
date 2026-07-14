import Foundation
import SQLite3
import ZoidCoachCore

public struct TaskMutationOperation: Equatable, Sendable {
    public enum State: String, Sendable { case pending, completed, failed }

    public let id: UUID
    public let taskID: String
    public let command: TaskActivityCommand
    public let requestedAt: Date
    public let state: State
    public let lastDiagnostic: String?
    public let result: TodaySnapshot?
}

public final class TaskMutationOperationStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else { throw TaskMutationOperationStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func begin(id: UUID, taskID: String, command: TaskActivityCommand, requestedAt: Date) throws -> TaskMutationOperation {
        let sql = "INSERT OR IGNORE INTO task_mutation_operations(operation_id, task_id, command, requested_at_utc, state) VALUES (?, ?, ?, ?, 'pending');"
        try execute(sql, bindings: [id.uuidString, taskID, command.rawValue, formatter.string(from: requestedAt)])
        guard let operation = try load(id: id) else { throw TaskMutationOperationStoreError.write }
        guard operation.taskID == taskID, operation.command == command else {
            throw TaskMutationOperationStoreError.operationKeyConflict
        }
        return operation
    }

    public func load(id: UUID) throws -> TaskMutationOperation? {
        let sql = "SELECT task_id, command, requested_at_utc, state, last_diagnostic, result_json FROM task_mutation_operations WHERE operation_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskMutationOperationStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let task = string(statement, 0), let commandRaw = string(statement, 1), let command = TaskActivityCommand(rawValue: commandRaw),
              let requestedRaw = string(statement, 2), let requestedAt = formatter.date(from: requestedRaw),
              let stateRaw = string(statement, 3), let state = TaskMutationOperation.State(rawValue: stateRaw) else { throw TaskMutationOperationStoreError.read }
        let result: TodaySnapshot?
        if let bytes = sqlite3_column_blob(statement, 5) {
            result = try decoder.decode(TodaySnapshot.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 5))))
        } else { result = nil }
        return TaskMutationOperation(id: id, taskID: task, command: command, requestedAt: requestedAt, state: state, lastDiagnostic: string(statement, 4), result: result)
    }

    public func hasCompletedStep(operationID: UUID, step: String) throws -> Bool {
        let sql = "SELECT 1 FROM task_mutation_steps WHERE operation_id = ? AND step = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskMutationOperationStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(operationID.uuidString, statement, 1); bind(step, statement, 2)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public func completeStep(operationID: UUID, step: String, at date: Date = Date()) throws {
        try execute("INSERT OR IGNORE INTO task_mutation_steps(operation_id, step, completed_at_utc) VALUES (?, ?, ?);", bindings: [operationID.uuidString, step, formatter.string(from: date)])
    }

    public func complete(operationID: UUID, result: TodaySnapshot) throws {
        let data = try encoder.encode(result)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE task_mutation_operations SET state = 'completed', result_json = ?, last_diagnostic = NULL WHERE operation_id = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskMutationOperationStoreError.write }
        defer { sqlite3_finalize(statement) }
        data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        bind(operationID.uuidString, statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskMutationOperationStoreError.write }
    }

    public func recordPendingFailure(operationID: UUID, diagnostic: String) throws {
        try execute("UPDATE task_mutation_operations SET state = 'pending', last_diagnostic = ? WHERE operation_id = ?;", bindings: [diagnostic, operationID.uuidString])
    }

    public func failValidation(operationID: UUID, diagnostic: String) throws {
        try execute("UPDATE task_mutation_operations SET state = 'failed', last_diagnostic = ? WHERE operation_id = ?;", bindings: [diagnostic, operationID.uuidString])
    }

    private func execute(_ sql: String, bindings: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskMutationOperationStoreError.write }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() { bind(value, statement, Int32(offset + 1)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskMutationOperationStoreError.write }
    }
}

public enum TaskMutationOperationStoreError: Error, Equatable {
    case openDatabase, read, write, operationKeyConflict
}

private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
