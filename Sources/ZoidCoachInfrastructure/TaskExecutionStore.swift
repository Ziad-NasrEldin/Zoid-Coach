import Foundation
import SQLite3
import ZoidCoachCore

public struct TaskExecutionSnapshot: Equatable, Sendable {
    public let taskID: String
    public let state: TaskExecutionState
    public let elapsedMinutes: Int
    public let activeSince: Date?
    public let latestPauseReason: TaskPauseReason?

    public init(taskID: String, state: TaskExecutionState, elapsedMinutes: Int, activeSince: Date?, latestPauseReason: TaskPauseReason? = nil) {
        self.taskID = taskID
        self.state = state
        self.elapsedMinutes = elapsedMinutes
        self.activeSince = activeSince
        self.latestPauseReason = latestPauseReason
    }
}

public final class TaskExecutionStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw TaskExecutionStoreError.openDatabase }
        database = handle
    }

    deinit { sqlite3_close(database) }

    public func apply(_ command: TaskActivityCommand, taskID: String, at date: Date = Date()) throws {
        try transaction {
            let current = try state(for: taskID)
            switch command {
            case .start, .resume:
                if let existing = try openInterval(), existing.taskID != taskID {
                    try upsertState(taskID: existing.taskID, state: .paused, at: date)
                    try recordPause(taskID: existing.taskID, reason: .switchingTasks, at: date)
                }
                try closeOpenInterval(at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .active, at: date)
                try openInterval(taskID: taskID, at: date)
            case .pause, .pauseForBreak, .pauseForExternalInterruption, .pauseDoneForNow, .pauseForEndOfDay:
                guard current == .active else { return }
                try closeOpenInterval(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .paused, at: date)
                try recordPause(taskID: taskID, reason: command.pauseReason ?? .unspecified, at: date)
            case .complete:
                try closeOpenInterval(taskID: taskID, at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .completed, at: date)
            case .block:
                try closeOpenInterval(taskID: taskID, at: date)
                try recordPause(taskID: taskID, reason: .blocked, at: date)
                try upsertState(taskID: taskID, state: .blocked, at: date)
            case .reschedule:
                try closeOpenInterval(taskID: taskID, at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .rescheduled, at: date)
            }
        }
    }

    public func snapshot(for taskIDs: [String], now: Date = Date()) throws -> [String: TaskExecutionSnapshot] {
        let states = try states(for: taskIDs)
        let open = try openInterval()
        return Dictionary(uniqueKeysWithValues: taskIDs.map { taskID in
            let state = states[taskID] ?? .ready
            let elapsed = (try? elapsedMinutes(taskID: taskID, now: now)) ?? 0
            return (taskID, TaskExecutionSnapshot(taskID: taskID, state: state, elapsedMinutes: elapsed, activeSince: open?.taskID == taskID ? open?.startedAt : nil, latestPauseReason: try? latestPauseReason(taskID: taskID)))
        })
    }

    public func activeTask(now: Date = Date()) throws -> ActiveTaskSnapshot? {
        guard let open = try openInterval() else { return nil }
        return ActiveTaskSnapshot(taskID: open.taskID, startedAt: open.startedAt, elapsedMinutes: try elapsedMinutes(taskID: open.taskID, now: now))
    }

    private func transaction(_ body: () throws -> Void) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw TaskExecutionStoreError.write }
        do {
            try body()
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else { throw TaskExecutionStoreError.write }
        } catch {
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func state(for taskID: String) throws -> TaskExecutionState? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT state FROM task_execution_states WHERE task_id = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return TaskExecutionState(rawValue: String(cString: value))
    }

    private func states(for taskIDs: [String]) throws -> [String: TaskExecutionState] {
        guard !taskIDs.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: taskIDs.count).joined(separator: ",")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT task_id, state FROM task_execution_states WHERE task_id IN (\(placeholders));", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        for (index, id) in taskIDs.enumerated() { bind(id, statement, Int32(index + 1)) }
        var result: [String: TaskExecutionState] = [:]
        while sqlite3_step(statement) == SQLITE_ROW, let task = sqlite3_column_text(statement, 0), let state = sqlite3_column_text(statement, 1), let value = TaskExecutionState(rawValue: String(cString: state)) {
            result[String(cString: task)] = value
        }
        return result
    }

    private func upsertState(taskID: String, state: TaskExecutionState, at date: Date) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO task_execution_states(task_id, state, updated_at) VALUES (?, ?, ?) ON CONFLICT(task_id) DO UPDATE SET state = excluded.state, updated_at = excluded.updated_at;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(state.rawValue, statement, 2)
        bind(formatter.string(from: date), statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func openInterval(taskID: String, at date: Date) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO task_activity_intervals(task_id, started_at, ended_at) VALUES (?, ?, NULL);", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(formatter.string(from: date), statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func closeOpenInterval(taskID: String? = nil, at date: Date) throws {
        let sql = taskID == nil ? "UPDATE task_activity_intervals SET ended_at = ? WHERE ended_at IS NULL;" : "UPDATE task_activity_intervals SET ended_at = ? WHERE task_id = ? AND ended_at IS NULL;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: date), statement, 1)
        if let taskID { bind(taskID, statement, 2) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func recordPause(taskID: String, reason: TaskPauseReason, at date: Date) throws {
        try closeOpenPause(taskID: taskID, at: date)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO task_pause_events(task_id, reason, paused_at, resumed_at) VALUES (?, ?, ?, NULL);", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(reason.rawValue, statement, 2)
        bind(formatter.string(from: date), statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func closeOpenPause(taskID: String, at date: Date) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE task_pause_events SET resumed_at = ? WHERE task_id = ? AND resumed_at IS NULL;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: date), statement, 1)
        bind(taskID, statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func latestPauseReason(taskID: String) throws -> TaskPauseReason? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT reason FROM task_pause_events WHERE task_id = ? ORDER BY paused_at DESC, id DESC LIMIT 1;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return TaskPauseReason(rawValue: String(cString: value))
    }

    private func openInterval() throws -> (taskID: String, startedAt: Date)? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT task_id, started_at FROM task_activity_intervals WHERE ended_at IS NULL LIMIT 1;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let task = sqlite3_column_text(statement, 0), let started = sqlite3_column_text(statement, 1), let date = formatter.date(from: String(cString: started)) else { return nil }
        return (String(cString: task), date)
    }

    private func elapsedMinutes(taskID: String, now: Date) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT started_at, ended_at FROM task_activity_intervals WHERE task_id = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        var seconds: TimeInterval = 0
        while sqlite3_step(statement) == SQLITE_ROW, let start = sqlite3_column_text(statement, 0), let startedAt = formatter.date(from: String(cString: start)) {
            let endedAt = sqlite3_column_type(statement, 1) == SQLITE_NULL ? now : sqlite3_column_text(statement, 1).flatMap { formatter.date(from: String(cString: $0)) } ?? now
            seconds += max(0, endedAt.timeIntervalSince(startedAt))
        }
        return Int(seconds / 60)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }
}

public enum TaskExecutionStoreError: LocalizedError {
    case openDatabase, schema, read, write

    public var errorDescription: String? { "Could not persist task execution state." }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
