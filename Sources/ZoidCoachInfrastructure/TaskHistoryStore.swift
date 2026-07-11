import Foundation
import SQLite3

public enum TaskHistoryState: String, Sendable {
    case selected
    case completed
    case postponed
}

public struct TaskHistoryEvidence: Equatable, Sendable {
    public let selectionCount: Int
    public let completionCount: Int
    public let deferralCount: Int

    public init(selectionCount: Int, completionCount: Int, deferralCount: Int) {
        self.selectionCount = selectionCount
        self.completionCount = completionCount
        self.deferralCount = deferralCount
    }
}

public struct TaskHistoryDaySummary: Equatable, Sendable {
    public let selectedCount: Int
    public let completedCount: Int
    public let postponedCount: Int

    public init(selectedCount: Int, completedCount: Int, postponedCount: Int) {
        self.selectedCount = selectedCount
        self.completedCount = completedCount
        self.postponedCount = postponedCount
    }
}

public final class TaskHistoryStore: @unchecked Sendable {
    private let database: OpaquePointer

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw TaskHistoryStoreError.openDatabase }
        database = handle
    }

    deinit { sqlite3_close(database) }

    public func record(taskID: String, state: TaskHistoryState, at date: Date = Date()) throws {
        let sql = "INSERT INTO task_history (task_id, state, occurred_at) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(state.rawValue, statement, 2)
        bind(ISO8601DateFormatter().string(from: date), statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskHistoryStoreError.write }
    }

    public func evidence(for taskIDs: [String]) throws -> [String: TaskHistoryEvidence] {
        var result = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, TaskHistoryEvidence(selectionCount: 0, completionCount: 0, deferralCount: 0)) })
        guard !taskIDs.isEmpty else { return result }
        let placeholders = Array(repeating: "?", count: taskIDs.count).joined(separator: ",")
        let sql = "SELECT task_id, state, COUNT(*) FROM task_history WHERE task_id IN (\(placeholders)) GROUP BY task_id, state;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.read }
        defer { sqlite3_finalize(statement) }
        for (index, taskID) in taskIDs.enumerated() {
            bind(taskID, statement, Int32(index + 1))
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let taskIDPointer = sqlite3_column_text(statement, 0),
                  let statePointer = sqlite3_column_text(statement, 1),
                  let state = TaskHistoryState(rawValue: String(cString: statePointer))
            else { continue }
            let taskID = String(cString: taskIDPointer)
            let count = Int(sqlite3_column_int(statement, 2))
            let existing = result[taskID] ?? TaskHistoryEvidence(selectionCount: 0, completionCount: 0, deferralCount: 0)
            switch state {
            case .selected:
                result[taskID] = TaskHistoryEvidence(selectionCount: count, completionCount: existing.completionCount, deferralCount: existing.deferralCount)
            case .completed:
                result[taskID] = TaskHistoryEvidence(selectionCount: existing.selectionCount, completionCount: count, deferralCount: existing.deferralCount)
            case .postponed:
                result[taskID] = TaskHistoryEvidence(selectionCount: existing.selectionCount, completionCount: existing.completionCount, deferralCount: count)
            }
        }
        return result
    }

    public func summary(for date: Date, calendar: Calendar = .current) throws -> TaskHistoryDaySummary {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        let formatter = ISO8601DateFormatter()
        let sql = "SELECT state, COUNT(*) FROM task_history WHERE occurred_at >= ? AND occurred_at < ? GROUP BY state;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: interval.start), statement, 1)
        bind(formatter.string(from: interval.end), statement, 2)

        var selected = 0
        var completed = 0
        var postponed = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let statePointer = sqlite3_column_text(statement, 0),
                  let state = TaskHistoryState(rawValue: String(cString: statePointer))
            else { continue }
            switch state {
            case .selected: selected = Int(sqlite3_column_int(statement, 1))
            case .completed: completed = Int(sqlite3_column_int(statement, 1))
            case .postponed: postponed = Int(sqlite3_column_int(statement, 1))
            }
        }
        return TaskHistoryDaySummary(selectedCount: selected, completedCount: completed, postponedCount: postponed)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }
}

public enum TaskHistoryStoreError: LocalizedError {
    case openDatabase
    case schema
    case read
    case write

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open task history storage"
        case .schema: "Could not create task history storage"
        case .read: "Could not read task history"
        case .write: "Could not record task history"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
