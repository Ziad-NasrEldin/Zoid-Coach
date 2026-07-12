import Foundation
import SQLite3
import ZoidCoachCore

public struct StoredAutonomousPlanEntry: Equatable, Codable, Sendable {
    public let reminderID: String
    public let rank: Int
    public let isMainObjective: Bool
    public let estimateMinutes: Int
    public let selectionReason: String?
    public let selectionScore: Int?

    public init(reminderID: String, rank: Int, isMainObjective: Bool, estimateMinutes: Int, selectionReason: String? = nil, selectionScore: Int? = nil) {
        self.reminderID = reminderID
        self.rank = rank
        self.isMainObjective = isMainObjective
        self.estimateMinutes = estimateMinutes
        self.selectionReason = selectionReason
        self.selectionScore = selectionScore
    }
}

public enum DailyPlanInstallResult: Equatable, Sendable {
    case installed([StoredAutonomousPlanEntry])
    case retained([StoredAutonomousPlanEntry])
}

public final class AutonomousPlanStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let dateFormatter = ISO8601DateFormatter()
    private let timeZoneIdentifier: @Sendable () -> String

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        timeZoneIdentifier: @escaping @Sendable () -> String = { TimeZone.current.identifier }
    ) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw AutonomousPlanStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    deinit { sqlite3_close(database) }

    public func hasPlan(for day: Date) throws -> Bool {
        let sql = "SELECT 1 FROM daily_plan_entries WHERE day_key = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(for: day), to: statement, at: 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    public func replaceDailyPlan(_ proposal: DailyPlanProposal, for day: Date) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw AutonomousPlanStoreError.transaction
        }
        var committed = false
        defer {
            _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }
        let dayKey = dayKey(for: day)
        let previous = try loadDailyPlan(for: day)
        if !previous.isEmpty { try saveRevision(previous, dayKey: dayKey) }
        try execute("DELETE FROM daily_plan_entries WHERE day_key = ?;", binding: dayKey)

        let sql = "INSERT INTO daily_plan_entries (day_key, reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
        for item in proposal.items {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement
            else { throw AutonomousPlanStoreError.prepare }
            defer { sqlite3_finalize(statement) }
            bind(dayKey, to: statement, at: 1)
            bind(item.taskID, to: statement, at: 2)
            sqlite3_bind_int(statement, 3, Int32(item.rank))
            sqlite3_bind_int(statement, 4, item.taskID == proposal.mainObjectiveTaskID ? 1 : 0)
            sqlite3_bind_int(statement, 5, Int32(item.estimateMinutes))
            bind(item.reason, to: statement, at: 6)
            sqlite3_bind_int(statement, 7, Int32(item.score))
            bind(dateFormatter.string(from: Date()), to: statement, at: 8)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
        }
        try insertScheduleIntent(dayKey: dayKey)
        committed = true
    }

    public func installDailyPlanIfNoUsablePlan(
        _ proposal: DailyPlanProposal,
        for day: Date,
        usableTaskIDs: Set<String>
    ) throws -> DailyPlanInstallResult {
        guard !proposal.items.isEmpty,
              proposal.items.filter({ $0.taskID == proposal.mainObjectiveTaskID }).count == 1,
              Set(proposal.items.map(\.taskID)).count == proposal.items.count
        else { throw AutonomousPlanStoreError.invalidPlan }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw AutonomousPlanStoreError.transaction
        }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }

        let dayKey = dayKey(for: day)
        let previous = try loadDailyPlan(for: day)
        let visible = previous.filter { usableTaskIDs.contains($0.reminderID) }
        if !visible.isEmpty, visible.filter(\.isMainObjective).count == 1 {
            committed = true
            return .retained(visible)
        }

        if !previous.isEmpty { try saveRevision(previous, dayKey: dayKey) }
        try execute("DELETE FROM daily_plan_entries WHERE day_key = ?;", binding: dayKey)
        let entries = proposal.items.map { item in
            StoredAutonomousPlanEntry(
                reminderID: item.taskID,
                rank: item.rank,
                isMainObjective: item.taskID == proposal.mainObjectiveTaskID,
                estimateMinutes: item.estimateMinutes,
                selectionReason: item.reason,
                selectionScore: item.score
            )
        }
        for entry in entries { try insert(entry, dayKey: dayKey) }
        try insertScheduleIntent(dayKey: dayKey)
        committed = true
        return .installed(entries)
    }

    public func loadDailyPlan(for day: Date) throws -> [StoredAutonomousPlanEntry] {
        let sql = "SELECT reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score FROM daily_plan_entries WHERE day_key = ? ORDER BY rank ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(for: day), to: statement, at: 1)
        var entries: [StoredAutonomousPlanEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let reminderID = sqlite3_column_text(statement, 0) {
            entries.append(StoredAutonomousPlanEntry(
                reminderID: String(cString: reminderID),
                rank: Int(sqlite3_column_int(statement, 1)),
                isMainObjective: sqlite3_column_int(statement, 2) == 1,
                estimateMinutes: sqlite3_column_type(statement, 3) == SQLITE_NULL ? 45 : Int(sqlite3_column_int(statement, 3)),
                selectionReason: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4)),
                selectionScore: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 5))
            ))
        }
        return entries
    }

    @discardableResult
    public func restoreLatestRevision(for day: Date) throws -> Bool {
        let dayKey = dayKey(for: day)
        let sql = "SELECT id, entries_json FROM daily_plan_revisions WHERE day_key = ? AND restored_at_utc IS NULL ORDER BY revision DESC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(dayKey, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let idPointer = sqlite3_column_text(statement, 0),
              let jsonPointer = sqlite3_column_text(statement, 1),
              let data = String(cString: jsonPointer).data(using: .utf8) else { return false }
        let revisionID = String(cString: idPointer)
        let entries = try JSONDecoder().decode([StoredAutonomousPlanEntry].self, from: data)
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw AutonomousPlanStoreError.transaction }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }
        try execute("DELETE FROM daily_plan_entries WHERE day_key = ?;", binding: dayKey)
        for entry in entries { try insert(entry, dayKey: dayKey) }
        var update: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE daily_plan_revisions SET restored_at_utc = ? WHERE id = ?;", -1, &update, nil) == SQLITE_OK, let update else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(update) }
        bind(dateFormatter.string(from: Date()), to: update, at: 1)
        bind(revisionID, to: update, at: 2)
        guard sqlite3_step(update) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
        try insertScheduleIntent(dayKey: dayKey)
        committed = true
        return true
    }

    private func saveRevision(_ entries: [StoredAutonomousPlanEntry], dayKey: String) throws {
        let data = try JSONEncoder().encode(entries)
        guard let json = String(data: data, encoding: .utf8) else { throw AutonomousPlanStoreError.write }
        let revision = try nextRevision(dayKey: dayKey)
        var statement: OpaquePointer?
        let sql = "INSERT INTO daily_plan_revisions (id, day_key, revision, entries_json, created_at_utc) VALUES (?, ?, ?, ?, ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, to: statement, at: 1)
        bind(dayKey, to: statement, at: 2)
        sqlite3_bind_int(statement, 3, Int32(revision))
        bind(json, to: statement, at: 4)
        bind(dateFormatter.string(from: Date()), to: statement, at: 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
    }

    private func insertScheduleIntent(dayKey: String) throws {
        let id = UUID().uuidString
        let timestamp = dateFormatter.string(from: Date())
        var statement: OpaquePointer?
        let sql = "INSERT INTO plan_schedule_requests (id, prompt_id, day_key, state, created_at_utc, updated_at_utc) VALUES (?, ?, ?, 'pending', ?, ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AutonomousPlanStoreError.prepare
        }
        defer { sqlite3_finalize(statement) }
        bind(id, to: statement, at: 1)
        bind("automatic-plan:\(dayKey):\(id)", to: statement, at: 2)
        bind(dayKey, to: statement, at: 3)
        bind(timestamp, to: statement, at: 4)
        bind(timestamp, to: statement, at: 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
    }

    private func nextRevision(dayKey: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(revision), 0) + 1 FROM daily_plan_revisions WHERE day_key = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(dayKey, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AutonomousPlanStoreError.write }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func insert(_ entry: StoredAutonomousPlanEntry, dayKey: String) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO daily_plan_entries (day_key, reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(dayKey, to: statement, at: 1)
        bind(entry.reminderID, to: statement, at: 2)
        sqlite3_bind_int(statement, 3, Int32(entry.rank))
        sqlite3_bind_int(statement, 4, entry.isMainObjective ? 1 : 0)
        sqlite3_bind_int(statement, 5, Int32(entry.estimateMinutes))
        if let reason = entry.selectionReason { bind(reason, to: statement, at: 6) } else { sqlite3_bind_null(statement, 6) }
        if let score = entry.selectionScore { sqlite3_bind_int(statement, 7, Int32(score)) } else { sqlite3_bind_null(statement, 7) }
        bind(dateFormatter.string(from: Date()), to: statement, at: 8)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
    }

    private func ensureSchema() throws {
        let base = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS daily_plan_entries (
            day_key TEXT NOT NULL,
            reminder_id TEXT NOT NULL,
            rank INTEGER NOT NULL,
            is_main_objective INTEGER NOT NULL,
            estimate_minutes INTEGER,
            selection_reason TEXT,
            selection_score INTEGER,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (day_key, reminder_id)
        );
        CREATE INDEX IF NOT EXISTS daily_plan_entries_day_rank ON daily_plan_entries(day_key, rank);
        CREATE TABLE IF NOT EXISTS scheduled_blocks (
            day_key TEXT NOT NULL,
            plan_item_id TEXT NOT NULL,
            calendar_event_id TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (day_key, plan_item_id)
        );
        CREATE INDEX IF NOT EXISTS scheduled_blocks_day_start ON scheduled_blocks(day_key, start_at);
        """
        guard sqlite3_exec(database, base, nil, nil, nil) == SQLITE_OK else { throw AutonomousPlanStoreError.schema }
        try addColumnIfNeeded(named: "selection_reason", declaration: "TEXT", to: "daily_plan_entries")
        try addColumnIfNeeded(named: "selection_score", declaration: "INTEGER", to: "daily_plan_entries")
        guard sqlite3_exec(database, "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, CURRENT_TIMESTAMP), (2, CURRENT_TIMESTAMP), (3, CURRENT_TIMESTAMP), (4, CURRENT_TIMESTAMP);", nil, nil, nil) == SQLITE_OK else {
            throw AutonomousPlanStoreError.schema
        }
    }

    private func addColumnIfNeeded(named column: String, declaration: String, to table: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        var exists = false
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column {
                exists = true
                break
            }
        }
        guard !exists else { return }
        guard sqlite3_exec(database, "ALTER TABLE \(table) ADD COLUMN \(column) \(declaration);", nil, nil, nil) == SQLITE_OK else {
            throw AutonomousPlanStoreError.schema
        }
    }

    private func execute(_ sql: String, binding value: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw AutonomousPlanStoreError.prepare }
        defer { sqlite3_finalize(statement) }
        bind(value, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AutonomousPlanStoreError.write }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier()) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public enum AutonomousPlanStoreError: LocalizedError {
    case openDatabase
    case schema
    case prepare
    case transaction
    case write
    case invalidPlan

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the local Zoid Coach database"
        case .schema: "Could not prepare the autonomous planning database"
        case .prepare: "Could not prepare a planning database operation"
        case .transaction: "Could not begin a planning database transaction"
        case .write: "Could not persist the autonomous daily plan"
        case .invalidPlan: "A daily plan must contain unique tasks and exactly one main objective"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
