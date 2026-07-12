import Foundation
import SQLite3
import ZoidCoachCore

private let agentOwnedSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class AgentOwnedStateStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else { throw AgentOwnedStateStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func replaceDailyPlan(_ items: [AgentPlanItem], day: Date, now: Date = Date()) throws {
        try validateDailyPlan(items, now: now)
        try transaction {
            let dayKey = Self.dayKey(day)
            try execute("DELETE FROM daily_plan_entries WHERE day_key = ?;", values: [.text(dayKey)])
            for item in items {
                try execute(
                    "INSERT INTO daily_plan_entries (day_key, reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                    values: [
                        .text(dayKey), .text(item.reminderID), .integer(item.rank), .integer(item.isMainObjective ? 1 : 0),
                        item.estimateMinutes.map(Value.integer) ?? .null,
                        item.selectionReason.map(Value.text) ?? .null,
                        item.selectionScore.map(Value.integer) ?? .null,
                        .integer(item.isOptional == true ? 1 : 0),
                        item.blockedReason.map(Value.text) ?? .null,
                        item.deferredUntil.map { .text(formatter.string(from: $0)) } ?? .null,
                        .text(formatter.string(from: now))
                    ]
                )
            }
        }
    }

    private func validateDailyPlan(_ items: [AgentPlanItem], now: Date) throws {
        guard items.count <= 5 else { throw AgentOwnedStateStoreError.invalidDailyPlan }
        guard !items.isEmpty else { return }

        let reminderIDs = items.map { $0.reminderID.trimmingCharacters(in: .whitespacesAndNewlines) }
        let ranks = items.map(\.rank)
        guard reminderIDs.allSatisfy({ !$0.isEmpty }),
              Set(reminderIDs).count == items.count,
              Set(ranks) == Set(1...items.count),
              items.filter(\.isMainObjective).count == 1,
              items.allSatisfy({ $0.estimateMinutes.map { $0 > 0 } ?? true }),
              items.allSatisfy({ item in
                  guard let reason = item.blockedReason else { return true }
                  return (3...240).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count)
              }),
              let mainObjective = items.first(where: \.isMainObjective),
              mainObjective.isOptional != true,
              !(mainObjective.deferredUntil.map { $0 > now } ?? false)
        else { throw AgentOwnedStateStoreError.invalidDailyPlan }
    }

    public func appendLocalTaskToDailyPlan(
        taskID: String,
        estimateMinutes: Int,
        day: Date,
        now: Date = Date()
    ) throws {
        try transaction {
            let dayKey = Self.dayKey(day)
            try execute(
                """
                INSERT OR IGNORE INTO daily_plan_entries
                (day_key, reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, updated_at)
                SELECT ?, ?, COALESCE(MAX(rank), 0) + 1,
                       CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END,
                       ?, 'Created locally by the user', NULL, ?
                FROM daily_plan_entries
                WHERE day_key = ?;
                """,
                values: [
                    .text(dayKey),
                    .text(taskID),
                    .integer(estimateMinutes),
                    .text(formatter.string(from: now)),
                    .text(dayKey)
                ]
            )
        }
    }

    public func replaceReminderListOrder(_ listIDs: [String], now: Date = Date()) throws {
        try transaction {
            try execute("DELETE FROM reminder_list_order;", values: [])
            for (position, listID) in listIDs.enumerated() {
                try execute(
                    "INSERT INTO reminder_list_order (list_id, position, updated_at) VALUES (?, ?, ?);",
                    values: [.text(listID), .integer(position), .text(formatter.string(from: now))]
                )
            }
        }
    }

    public func recordSourceCheck(sourceID: String, state: String, detail: String, evidence: String, checkedAt: Date) throws {
        try execute(
            "INSERT INTO source_checkpoints (source_id, state, detail, evidence, checked_at) VALUES (?, ?, ?, ?, ?);",
            values: [.text(sourceID), .text(state), .text(detail), .text(evidence), .text(formatter.string(from: checkedAt))]
        )
    }

    private func transaction(_ body: () throws -> Void) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            throw AgentOwnedStateStoreError.write(errorMessage)
        }
        do {
            try body()
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw AgentOwnedStateStoreError.write(errorMessage)
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func execute(_ sql: String, values: [Value]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AgentOwnedStateStoreError.write(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let .text(text):
                _ = text.withCString { sqlite3_bind_text(statement, index, $0, -1, agentOwnedSQLiteTransient) }
            case let .integer(integer): sqlite3_bind_int64(statement, index, sqlite3_int64(integer))
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AgentOwnedStateStoreError.write(errorMessage) }
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(database)) }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private enum Value {
        case text(String)
        case integer(Int)
        case null
    }
}

public enum AgentOwnedStateStoreError: LocalizedError {
    case openDatabase
    case invalidDailyPlan
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: return "The agent could not open its state database."
        case .invalidDailyPlan: return "The daily plan is invalid and was not saved."
        case let .write(message): return "The agent could not persist state: \(message)"
        }
    }
}
