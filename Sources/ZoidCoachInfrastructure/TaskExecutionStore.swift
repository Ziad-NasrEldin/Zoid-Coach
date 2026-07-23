import Foundation
import SQLite3
import ZoidCoachCore

public struct TaskExecutionSnapshot: Equatable, Sendable {
    public let taskID: String
    public let state: TaskExecutionState
    public let elapsedMinutes: Int
    public let activeSince: Date?
    public let latestPauseReason: TaskPauseReason?
    public let acceptedBreak: AcceptedBreakSnapshot?
    public let sprint: SprintSnapshot?

    public init(taskID: String, state: TaskExecutionState, elapsedMinutes: Int, activeSince: Date?, latestPauseReason: TaskPauseReason? = nil, acceptedBreak: AcceptedBreakSnapshot? = nil, sprint: SprintSnapshot? = nil) {
        self.taskID = taskID
        self.state = state
        self.elapsedMinutes = elapsedMinutes
        self.activeSince = activeSince
        self.latestPauseReason = latestPauseReason
        self.acceptedBreak = acceptedBreak
        self.sprint = sprint
    }
}

public final class TaskExecutionStore: @unchecked Sendable {
    private static let maximumContinuousIntervalSeconds: TimeInterval = 24 * 60 * 60

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

    public func apply(
        _ command: TaskActivityCommand,
        taskID: String,
        blockedReason: String? = nil,
        operationID: UUID? = nil,
        at date: Date = Date()
    ) throws {
        let normalizedBlockedReason = blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if command == .block {
            guard let normalizedBlockedReason,
                  (3...240).contains(normalizedBlockedReason.count)
            else { throw TaskExecutionStoreError.invalidBlockedReason }
        }
        try transaction {
            if let operationID, try hasMutationReceipt(operationID: operationID, step: "execution") { return }
            let current = try state(for: taskID)
            switch command {
            case .start, .resume, .startSprint10, .startSprint20, .startSprint25, .continueOpenEnded:
                if let existing = try openInterval(), existing.taskID != taskID {
                    try upsertState(taskID: existing.taskID, state: .paused, at: date)
                    try recordPause(taskID: existing.taskID, reason: .switchingTasks, at: date)
                    try pauseSprint(taskID: existing.taskID, at: date)
                }
                try closeOpenInterval(at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .active, at: date)
                try openInterval(taskID: taskID, at: date)
                if let durationMinutes = command.sprintDurationMinutes {
                    try beginSprint(taskID: taskID, durationMinutes: durationMinutes, at: date)
                } else if command == .resume {
                    try resumeSprint(taskID: taskID, at: date)
                } else if command == .continueOpenEnded {
                    try continueSprintOpenEnded(taskID: taskID, at: date)
                } else {
                    try finishSprint(taskID: taskID, at: date)
                }
            case .pause, .pauseForBreak, .pauseForExternalInterruption, .pauseDoneForNow, .pauseForEndOfDay:
                guard current == .active else { return }
                try closeOpenInterval(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .paused, at: date)
                try recordPause(taskID: taskID, reason: command.pauseReason ?? .unspecified, at: date)
                try pauseSprint(taskID: taskID, at: date)
            case .complete:
                try closeOpenInterval(taskID: taskID, at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .completed, at: date)
                try finishSprint(taskID: taskID, at: date)
            case .block:
                try closeOpenInterval(taskID: taskID, at: date)
                try recordPause(taskID: taskID, reason: .blocked, at: date)
                try upsertState(taskID: taskID, state: .blocked, at: date)
                try updatePlanBlockedReason(normalizedBlockedReason, taskID: taskID, at: date)
                try finishSprint(taskID: taskID, at: date)
            case .reschedule:
                try closeOpenInterval(taskID: taskID, at: date)
                try closeOpenPause(taskID: taskID, at: date)
                try upsertState(taskID: taskID, state: .rescheduled, at: date)
                try updatePlanBlockedReason(nil, taskID: taskID, at: date)
                try finishSprint(taskID: taskID, at: date)
            }
            if let operationID { try insertMutationReceipt(operationID: operationID, step: "execution", at: date) }
        }
    }

    private func hasMutationReceipt(operationID: UUID, step: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM task_mutation_steps WHERE operation_id = ? AND step = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(operationID.uuidString, statement, 1)
        bind(step, statement, 2)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func insertMutationReceipt(operationID: UUID, step: String, at date: Date) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR IGNORE INTO task_mutation_steps(operation_id, step, completed_at_utc) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(operationID.uuidString, statement, 1)
        bind(step, statement, 2)
        bind(formatter.string(from: date), statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    public func startSprint(taskID: String, durationMinutes: Int, at date: Date = Date()) throws {
        guard (1...480).contains(durationMinutes) else { throw TaskExecutionStoreError.invalidSprintDuration }
        try transaction {
            if let existing = try openInterval(), existing.taskID != taskID {
                try upsertState(taskID: existing.taskID, state: .paused, at: date)
                try recordPause(taskID: existing.taskID, reason: .switchingTasks, at: date)
                try pauseSprint(taskID: existing.taskID, at: date)
            }
            try closeOpenInterval(at: date)
            try closeOpenPause(taskID: taskID, at: date)
            try upsertState(taskID: taskID, state: .active, at: date)
            try openInterval(taskID: taskID, at: date)
            try beginSprint(taskID: taskID, durationMinutes: durationMinutes, at: date)
        }
    }

    public func pauseForDeletedReminder(taskID: String, at date: Date = Date()) throws {
        try transaction {
            guard try state(for: taskID) == .active else { return }
            try closeOpenInterval(taskID: taskID, at: date)
            try upsertState(taskID: taskID, state: .paused, at: date)
            try recordPause(taskID: taskID, reason: .reminderDeleted, at: date)
            try pauseSprint(taskID: taskID, at: date)
        }
    }

    public func snapshot(for taskIDs: [String], now: Date = Date()) throws -> [String: TaskExecutionSnapshot] {
        let states = try states(for: taskIDs)
        let open = try openInterval()
        return Dictionary(uniqueKeysWithValues: taskIDs.map { taskID in
            let state = states[taskID] ?? .ready
            let elapsed = (try? elapsedMinutes(taskID: taskID, now: now)) ?? 0
            let pause = try? latestPause(taskID: taskID)
            let acceptedBreak = pause?.reason == .break && pause?.resumedAt == nil
                ? pause.map { AcceptedBreakSnapshot(startedAt: $0.pausedAt) }
                : nil
            return (taskID, TaskExecutionSnapshot(taskID: taskID, state: state, elapsedMinutes: elapsed, activeSince: open?.taskID == taskID ? open?.startedAt : nil, latestPauseReason: pause?.reason, acceptedBreak: acceptedBreak, sprint: try? sprintSnapshot(taskID: taskID, now: now)))
        })
    }

    public func activeTask(now: Date = Date()) throws -> ActiveTaskSnapshot? {
        guard let open = try openInterval() else { return nil }
        return ActiveTaskSnapshot(
            taskID: open.taskID,
            startedAt: open.startedAt,
            elapsedMinutes: try elapsedMinutes(taskID: open.taskID, now: now),
            sprint: try sprintSnapshot(taskID: open.taskID, now: now)
        )
    }

    public func latestIntervalStartedAt(taskID: String, endingAt date: Date) throws -> Date? {
        var statement: OpaquePointer?
        let sql = "SELECT started_at FROM task_activity_intervals WHERE task_id = ? AND ended_at <= ? ORDER BY ended_at DESC, id DESC LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        bind(formatter.string(from: date), statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return formatter.date(from: String(cString: text))
    }

    public func sprintSnapshot(taskID: String, now: Date = Date()) throws -> SprintSnapshot? {
        guard let sprint = try openSprint(taskID: taskID) else { return nil }
        let elapsedSeconds = sprint.elapsedSeconds(at: now)
        let durationSeconds = sprint.durationMinutes * 60
        let visibleState: SprintExecutionState
        if sprint.state == .active, elapsedSeconds >= TimeInterval(durationSeconds) {
            visibleState = .expired
        } else {
            visibleState = sprint.state
        }
        return SprintSnapshot(
            durationMinutes: sprint.durationMinutes,
            elapsedSeconds: Int(elapsedSeconds.rounded(.down)),
            remainingSeconds: max(0, durationSeconds - Int(elapsedSeconds.rounded(.down))),
            state: visibleState,
            observedAt: now
        )
    }

    private struct StoredSprint {
        let id: Int64
        let durationMinutes: Int
        let activeSegmentStartedAt: Date?
        let accumulatedActiveSeconds: TimeInterval
        let state: SprintExecutionState

        func elapsedSeconds(at date: Date) -> TimeInterval {
            guard state == .active, let activeSegmentStartedAt else {
                return accumulatedActiveSeconds
            }
            return accumulatedActiveSeconds + max(0, date.timeIntervalSince(activeSegmentStartedAt))
        }
    }

    private func beginSprint(taskID: String, durationMinutes: Int, at date: Date) throws {
        if let current = try openSprint(taskID: taskID),
           current.durationMinutes == durationMinutes,
           current.state == .active,
           current.elapsedSeconds(at: date) < TimeInterval(durationMinutes * 60) {
            return
        }
        try finishSprint(taskID: taskID, at: date)
        var statement: OpaquePointer?
        let sql = "INSERT INTO task_sprint_sessions(task_id, duration_minutes, started_at_utc, active_segment_started_at_utc, accumulated_active_seconds, state, ended_at_utc) VALUES (?, ?, ?, ?, 0, 'active', NULL);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TaskExecutionStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        sqlite3_bind_int(statement, 2, Int32(durationMinutes))
        let timestamp = formatter.string(from: date)
        bind(timestamp, statement, 3)
        bind(timestamp, statement, 4)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
    }

    private func pauseSprint(taskID: String, at date: Date) throws {
        guard let sprint = try openSprint(taskID: taskID), sprint.state == .active else { return }
        let elapsed = sprint.elapsedSeconds(at: date)
        let state: SprintExecutionState = elapsed >= TimeInterval(sprint.durationMinutes * 60) ? .expired : .paused
        try updateSprint(id: sprint.id, state: state, accumulatedSeconds: elapsed, activeSince: nil, endedAt: nil)
    }

    private func resumeSprint(taskID: String, at date: Date) throws {
        guard let sprint = try openSprint(taskID: taskID), sprint.state == .paused else { return }
        guard sprint.accumulatedActiveSeconds < TimeInterval(sprint.durationMinutes * 60) else {
            try updateSprint(id: sprint.id, state: .expired, accumulatedSeconds: sprint.accumulatedActiveSeconds, activeSince: nil, endedAt: nil)
            return
        }
        try updateSprint(id: sprint.id, state: .active, accumulatedSeconds: sprint.accumulatedActiveSeconds, activeSince: date, endedAt: nil)
    }

    private func continueSprintOpenEnded(taskID: String, at date: Date) throws {
        guard let sprint = try openSprint(taskID: taskID) else {
            throw TaskExecutionStoreError.sprintUnavailable
        }
        if sprint.state == .continuedOpenEnded {
            return
        }
        guard sprint.state == .expired
                || sprint.elapsedSeconds(at: date) >= TimeInterval(sprint.durationMinutes * 60)
        else {
            throw TaskExecutionStoreError.sprintStillActive
        }
        try updateSprint(
            id: sprint.id,
            state: .continuedOpenEnded,
            accumulatedSeconds: sprint.elapsedSeconds(at: date),
            activeSince: nil,
            endedAt: nil
        )
    }

    private func finishSprint(taskID: String, at date: Date) throws {
        guard let sprint = try openSprint(taskID: taskID) else { return }
        try updateSprint(
            id: sprint.id,
            state: .finished,
            accumulatedSeconds: sprint.elapsedSeconds(at: date),
            activeSince: nil,
            endedAt: date
        )
    }

    private func openSprint(taskID: String) throws -> StoredSprint? {
        var statement: OpaquePointer?
        let sql = "SELECT id, duration_minutes, active_segment_started_at_utc, accumulated_active_seconds, state FROM task_sprint_sessions WHERE task_id = ? AND state IN ('active', 'paused', 'expired', 'continuedOpenEnded') ORDER BY id DESC LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TaskExecutionStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let stateText = sqlite3_column_text(statement, 4),
              let state = SprintExecutionState(rawValue: String(cString: stateText))
        else { return nil }
        let activeSince = sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil
            : sqlite3_column_text(statement, 2).flatMap { formatter.date(from: String(cString: $0)) }
        return StoredSprint(
            id: sqlite3_column_int64(statement, 0),
            durationMinutes: Int(sqlite3_column_int(statement, 1)),
            activeSegmentStartedAt: activeSince,
            accumulatedActiveSeconds: sqlite3_column_double(statement, 3),
            state: state
        )
    }

    private func updateSprint(
        id: Int64,
        state: SprintExecutionState,
        accumulatedSeconds: TimeInterval,
        activeSince: Date?,
        endedAt: Date?
    ) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE task_sprint_sessions SET state = ?, accumulated_active_seconds = ?, active_segment_started_at_utc = ?, ended_at_utc = ? WHERE id = ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TaskExecutionStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(state.rawValue, statement, 1)
        sqlite3_bind_double(statement, 2, max(0, accumulatedSeconds))
        if let activeSince { bind(formatter.string(from: activeSince), statement, 3) } else { sqlite3_bind_null(statement, 3) }
        if let endedAt { bind(formatter.string(from: endedAt), statement, 4) } else { sqlite3_bind_null(statement, 4) }
        sqlite3_bind_int64(statement, 5, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
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

    private func updatePlanBlockedReason(_ reason: String?, taskID: String, at date: Date) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE daily_plan_entries SET blocked_reason = ?, updated_at = ? WHERE reminder_id = ? AND day_key = (SELECT MAX(day_key) FROM daily_plan_entries WHERE reminder_id = ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        if let reason {
            bind(reason, statement, 1)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        bind(formatter.string(from: date), statement, 2)
        bind(taskID, statement, 3)
        bind(taskID, statement, 4)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TaskExecutionStoreError.write }
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
        let normalizedEnd = "CASE WHEN started_at > ? THEN started_at ELSE ? END"
        let sql = taskID == nil
            ? "UPDATE task_activity_intervals SET ended_at = \(normalizedEnd) WHERE ended_at IS NULL;"
            : "UPDATE task_activity_intervals SET ended_at = \(normalizedEnd) WHERE task_id = ? AND ended_at IS NULL;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: date), statement, 1)
        bind(formatter.string(from: date), statement, 2)
        if let taskID { bind(taskID, statement, 3) }
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

    private func latestPause(taskID: String) throws -> (reason: TaskPauseReason, pausedAt: Date, resumedAt: Date?)? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT reason, paused_at, resumed_at FROM task_pause_events WHERE task_id = ? ORDER BY paused_at DESC, id DESC LIMIT 1;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TaskExecutionStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(taskID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let reasonText = sqlite3_column_text(statement, 0),
              let pausedText = sqlite3_column_text(statement, 1),
              let reason = TaskPauseReason(rawValue: String(cString: reasonText)),
              let pausedAt = formatter.date(from: String(cString: pausedText))
        else { return nil }
        let resumedAt = sqlite3_column_text(statement, 2).flatMap { formatter.date(from: String(cString: $0)) }
        return (reason, pausedAt, resumedAt)
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
            let intervalSeconds = max(0, endedAt.timeIntervalSince(startedAt))
            seconds += min(Self.maximumContinuousIntervalSeconds, intervalSeconds)
        }
        return Int(seconds / 60)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }
}

public enum TaskExecutionStoreError: LocalizedError {
    case openDatabase, schema, read, write, invalidSprintDuration, invalidBlockedReason, sprintUnavailable, sprintStillActive

    public var errorDescription: String? {
        switch self {
        case .invalidSprintDuration: "Choose a sprint from 1 to 240 minutes."
        case .invalidBlockedReason: "Explain the blocker in 3 to 240 characters."
        case .sprintUnavailable: "Start a bounded sprint before continuing without a timer."
        case .sprintStillActive: "The sprint is still running. Wait for the boundary before continuing without a timer."
        case .openDatabase, .schema, .read, .write: "Could not persist task execution state."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
