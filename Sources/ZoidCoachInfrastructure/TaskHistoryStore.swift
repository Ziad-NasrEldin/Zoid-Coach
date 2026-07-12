import Foundation
import SQLite3
import ZoidCoachCore

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

    public func record(
        taskID: String,
        state: TaskHistoryState,
        title: String? = nil,
        sourceKind: ReminderSourceKind? = nil,
        at date: Date = Date()
    ) throws {
        let sql = "INSERT INTO task_history (task_id, state, title_snapshot, source_kind, occurred_at) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(state.rawValue, statement, 2)
        bindOptional(title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, statement, 3)
        bind((sourceKind.map(\.rawValue) ?? "unknown"), statement, 4)
        bind(ISO8601DateFormatter().string(from: date), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskHistoryStoreError.write }
    }

    public func completedEntries(for date: Date, calendar: Calendar = .current) throws -> [CompletedTaskHistoryEntry] {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        let formatter = ISO8601DateFormatter()
        let sql = """
        WITH day_completions AS (
            SELECT MAX(id) AS id
            FROM task_history
            WHERE state = 'completed' AND occurred_at >= ? AND occurred_at < ?
            GROUP BY task_id
        )
        SELECT h.id,
               h.task_id,
               COALESCE(NULLIF(h.title_snapshot, ''), s.title, 'Completed task'),
               CASE
                   WHEN h.source_kind IN ('reminders', 'local') THEN h.source_kind
                   WHEN s.source_kind IN ('reminders', 'local') THEN s.source_kind
                   ELSE 'unknown'
               END,
               h.occurred_at,
               (
                   SELECT p.reason
                   FROM task_pause_events p
                   WHERE p.task_id = h.task_id AND p.paused_at <= h.occurred_at
                   ORDER BY p.paused_at DESC, p.id DESC
                   LIMIT 1
               )
        FROM task_history h
        LEFT JOIN source_tasks s ON s.source_id = h.task_id
        WHERE h.id IN (SELECT id FROM day_completions)
        ORDER BY h.occurred_at DESC, h.id DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: interval.start), statement, 1)
        bind(formatter.string(from: interval.end), statement, 2)

        var entries: [CompletedTaskHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let taskIDPointer = sqlite3_column_text(statement, 1),
                  let titlePointer = sqlite3_column_text(statement, 2),
                  let sourcePointer = sqlite3_column_text(statement, 3),
                  let datePointer = sqlite3_column_text(statement, 4),
                  let completedAt = formatter.date(from: String(cString: datePointer))
            else { continue }
            let pauseReason = sqlite3_column_text(statement, 5).flatMap {
                TaskPauseReason(rawValue: String(cString: $0))
            }
            entries.append(CompletedTaskHistoryEntry(
                id: sqlite3_column_int64(statement, 0),
                taskID: String(cString: taskIDPointer),
                title: String(cString: titlePointer),
                sourceKind: CompletedTaskSourceKind(rawValue: String(cString: sourcePointer)) ?? .unknown,
                completedAt: completedAt,
                lastPauseReason: pauseReason
            ))
        }
        return entries
    }

    public func latestCompletedEntry(for taskID: String) throws -> CompletedTaskHistoryEntry? {
        let sql = """
        SELECT h.id,
               h.task_id,
               COALESCE(NULLIF(h.title_snapshot, ''), s.title, 'Completed task'),
               CASE
                   WHEN h.source_kind IN ('reminders', 'local') THEN h.source_kind
                   WHEN s.source_kind IN ('reminders', 'local') THEN s.source_kind
                   ELSE 'unknown'
               END,
               h.occurred_at,
               (
                   SELECT p.reason
                   FROM task_pause_events p
                   WHERE p.task_id = h.task_id AND p.paused_at <= h.occurred_at
                   ORDER BY p.paused_at DESC, p.id DESC
                   LIMIT 1
               )
        FROM task_history h
        LEFT JOIN source_tasks s ON s.source_id = h.task_id
        WHERE h.task_id = ? AND h.state = 'completed'
        ORDER BY h.occurred_at DESC, h.id DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskHistoryStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let taskIDPointer = sqlite3_column_text(statement, 1),
              let titlePointer = sqlite3_column_text(statement, 2),
              let sourcePointer = sqlite3_column_text(statement, 3),
              let datePointer = sqlite3_column_text(statement, 4),
              let completedAt = ISO8601DateFormatter().date(from: String(cString: datePointer))
        else { return nil }
        let pauseReason = sqlite3_column_text(statement, 5).flatMap {
            TaskPauseReason(rawValue: String(cString: $0))
        }
        return CompletedTaskHistoryEntry(
            id: sqlite3_column_int64(statement, 0),
            taskID: String(cString: taskIDPointer),
            title: String(cString: titlePointer),
            sourceKind: CompletedTaskSourceKind(rawValue: String(cString: sourcePointer)) ?? .unknown,
            completedAt: completedAt,
            lastPauseReason: pauseReason
        )
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

    private func bindOptional(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bind(value, statement, index)
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
