import Foundation
import SQLite3

private let planUndoSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct PlanUndoRequest: Equatable, Sendable {
    public let id: String
    public let promptID: String
    public let dayKey: String
}

public final class PlanUndoRequestStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSRecursiveLock()
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            throw PlanUndoRequestStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func recoverInterrupted(now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE plan_undo_requests SET state = 'pending', updated_at_utc = ? WHERE state = 'executing';", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw PlanUndoRequestStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: now), statement, 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PlanUndoRequestStoreError.write }
    }

    public func enqueue(promptID: String, dayKey: String, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = "INSERT OR IGNORE INTO plan_undo_requests (id, prompt_id, day_key, state, created_at_utc, updated_at_utc) VALUES (?, ?, ?, 'pending', ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw PlanUndoRequestStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, statement, 1)
        bind(promptID, statement, 2)
        bind(dayKey, statement, 3)
        bind(formatter.string(from: now), statement, 4)
        bind(formatter.string(from: now), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PlanUndoRequestStoreError.write }
    }

    public func claimNext(now: Date = Date()) throws -> PlanUndoRequest? {
        lock.lock()
        defer { lock.unlock() }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { throw PlanUndoRequestStoreError.write }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }
        var select: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id, prompt_id, day_key FROM plan_undo_requests WHERE state = 'pending' ORDER BY created_at_utc LIMIT 1;", -1, &select, nil) == SQLITE_OK, let select else { throw PlanUndoRequestStoreError.read }
        defer { sqlite3_finalize(select) }
        guard sqlite3_step(select) == SQLITE_ROW,
              let id = sqlite3_column_text(select, 0),
              let prompt = sqlite3_column_text(select, 1),
              let day = sqlite3_column_text(select, 2) else { committed = true; return nil }
        let request = PlanUndoRequest(id: String(cString: id), promptID: String(cString: prompt), dayKey: String(cString: day))
        var update: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE plan_undo_requests SET state = 'executing', updated_at_utc = ? WHERE id = ? AND state = 'pending';", -1, &update, nil) == SQLITE_OK, let update else { throw PlanUndoRequestStoreError.write }
        defer { sqlite3_finalize(update) }
        bind(formatter.string(from: now), update, 1)
        bind(request.id, update, 2)
        guard sqlite3_step(update) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw PlanUndoRequestStoreError.write }
        committed = true
        return request
    }

    public func finish(_ request: PlanUndoRequest, succeeded: Bool, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE plan_undo_requests SET state = ?, updated_at_utc = ? WHERE id = ? AND state = 'executing';", -1, &statement, nil) == SQLITE_OK, let statement else { throw PlanUndoRequestStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(succeeded ? "succeeded" : "pending", statement, 1)
        bind(formatter.string(from: now), statement, 2)
        bind(request.id, statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PlanUndoRequestStoreError.write }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, planUndoSQLiteTransient) }
    }
}

public enum PlanUndoRequestStoreError: Error {
    case openDatabase
    case read
    case write
}
