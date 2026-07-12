import Foundation
import SQLite3
import ZoidCoachCore

struct StoredSourceCheck: Equatable, Sendable {
    let id: Int64
    let sourceID: SourceID
    let state: HealthState
    let detail: String
    let evidence: String
    let checkedAt: Date
}

struct DailyPlanEntry: Identifiable, Equatable, Sendable {
    let reminderID: String
    let rank: Int
    let isMainObjective: Bool
    let estimateMinutes: Int?
    let selectionReason: String?
    let selectionScore: Int?
    let isOptional: Bool
    let blockedReason: String?
    let deferredUntil: Date?

    init(
        reminderID: String,
        rank: Int,
        isMainObjective: Bool,
        estimateMinutes: Int?,
        selectionReason: String? = nil,
        selectionScore: Int? = nil,
        isOptional: Bool = false,
        blockedReason: String? = nil,
        deferredUntil: Date? = nil
    ) {
        self.reminderID = reminderID
        self.rank = rank
        self.isMainObjective = isMainObjective
        self.estimateMinutes = estimateMinutes
        self.selectionReason = selectionReason
        self.selectionScore = selectionScore
        self.isOptional = isOptional
        self.blockedReason = blockedReason
        self.deferredUntil = deferredUntil
    }

    var id: String { reminderID }
}

struct ScheduledBlockRecord: Equatable, Sendable, Identifiable {
    let planItemID: String
    let calendarEventID: String
    let start: Date
    let end: Date

    var id: String { planItemID }
}

actor EventStore {
    private let handle: SQLiteDatabaseHandle?
    private let dateFormatter = ISO8601DateFormatter()

    init(databaseURL: URL = EventStore.defaultDatabaseURL(), readOnly: Bool = false) {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        handle = SQLiteDatabaseHandle(path: databaseURL.path, readOnly: readOnly)
        if !readOnly { Self.migrate(database: handle?.pointer) }
    }

    func recordSourceCheck(_ health: SourceHealth, checkedAt: Date = Date()) {
        guard let database = handle?.pointer else { return }
        let sql = "INSERT INTO source_checkpoints (source_id, state, detail, evidence, checked_at) VALUES (?, ?, ?, ?, ?);"
        guard let statement = prepare(sql, database: database) else { return }
        defer { sqlite3_finalize(statement) }
        bind(health.id.rawValue, to: statement, index: 1)
        bind(health.state.rawValue, to: statement, index: 2)
        bind(health.detail, to: statement, index: 3)
        bind(health.evidence, to: statement, index: 4)
        bind(dateFormatter.string(from: checkedAt), to: statement, index: 5)
        _ = sqlite3_step(statement)
    }

    func replaySourceChecks(limit: Int = 100) -> [StoredSourceCheck] {
        guard let database = handle?.pointer else { return [] }
        let sql = "SELECT id, source_id, state, detail, evidence, checked_at FROM source_checkpoints ORDER BY id ASC LIMIT ?;"
        guard let statement = prepare(sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var records: [StoredSourceCheck] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceRaw = columnText(statement, index: 1), let stateRaw = columnText(statement, index: 2), let sourceID = SourceID(rawValue: sourceRaw), let state = HealthState(rawValue: stateRaw), let detail = columnText(statement, index: 3), let evidence = columnText(statement, index: 4), let dateRaw = columnText(statement, index: 5), let checkedAt = dateFormatter.date(from: dateRaw) else { continue }
            records.append(StoredSourceCheck(id: sqlite3_column_int64(statement, 0), sourceID: sourceID, state: state, detail: detail, evidence: evidence, checkedAt: checkedAt))
        }
        return records
    }

    func replaceDailyPlan(_ entries: [DailyPlanEntry], for day: Date = Date()) {
        guard let database = handle?.pointer else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return }
        var shouldCommit = false
        defer {
            _ = sqlite3_exec(database, shouldCommit ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }
        let dayKey = Self.dayKey(for: day)
        guard let delete = prepare("DELETE FROM daily_plan_entries WHERE day_key = ?;", database: database) else { return }
        defer { sqlite3_finalize(delete) }
        bind(dayKey, to: delete, index: 1)
        guard sqlite3_step(delete) == SQLITE_DONE else { return }

        let sql = "INSERT INTO daily_plan_entries (day_key, reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        for entry in entries {
            guard let statement = prepare(sql, database: database) else { return }
            bind(dayKey, to: statement, index: 1)
            bind(entry.reminderID, to: statement, index: 2)
            sqlite3_bind_int(statement, 3, Int32(entry.rank))
            sqlite3_bind_int(statement, 4, entry.isMainObjective ? 1 : 0)
            if let estimateMinutes = entry.estimateMinutes {
                sqlite3_bind_int(statement, 5, Int32(estimateMinutes))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            if let selectionReason = entry.selectionReason {
                bind(selectionReason, to: statement, index: 6)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            if let selectionScore = entry.selectionScore {
                sqlite3_bind_int(statement, 7, Int32(selectionScore))
            } else {
                sqlite3_bind_null(statement, 7)
            }
            sqlite3_bind_int(statement, 8, entry.isOptional ? 1 : 0)
            if let blockedReason = entry.blockedReason {
                bind(blockedReason, to: statement, index: 9)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            if let deferredUntil = entry.deferredUntil {
                bind(dateFormatter.string(from: deferredUntil), to: statement, index: 10)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            bind(dateFormatter.string(from: Date()), to: statement, index: 11)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                return
            }
            sqlite3_finalize(statement)
        }
        shouldCommit = true
    }

    func loadDailyPlan(for day: Date = Date()) -> [DailyPlanEntry] {
        guard let database = handle?.pointer else { return [] }
        let sql = "SELECT reminder_id, rank, is_main_objective, estimate_minutes, selection_reason, selection_score, is_optional, blocked_reason, deferred_until_utc FROM daily_plan_entries WHERE day_key = ? ORDER BY rank ASC;"
        guard let statement = prepare(sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(Self.dayKey(for: day), to: statement, index: 1)
        var entries: [DailyPlanEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let reminderID = columnText(statement, index: 0) else { continue }
            let estimateMinutes = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3))
            let selectionReason = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : columnText(statement, index: 4)
            let selectionScore = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 5))
            let blockedReason = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : columnText(statement, index: 7)
            let deferredUntil = sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? nil
                : columnText(statement, index: 8).flatMap(dateFormatter.date(from:))
            entries.append(
                DailyPlanEntry(
                    reminderID: reminderID,
                    rank: Int(sqlite3_column_int(statement, 1)),
                    isMainObjective: sqlite3_column_int(statement, 2) == 1,
                    estimateMinutes: estimateMinutes,
                    selectionReason: selectionReason,
                    selectionScore: selectionScore,
                    isOptional: sqlite3_column_int(statement, 6) == 1,
                    blockedReason: blockedReason,
                    deferredUntil: deferredUntil
                )
            )
        }
        return entries
    }

    func loadIncompleteLocalTaskIDs() -> Set<String> {
        guard let database = handle?.pointer else { return [] }
        let sql = "SELECT source_id FROM source_tasks WHERE source_kind = 'local' AND is_completed = 0;"
        guard let statement = prepare(sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }
        var identifiers = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW,
              let identifier = columnText(statement, index: 0) {
            identifiers.insert(identifier)
        }
        return identifiers
    }

    func replaceScheduledBlocks(_ blocks: [ScheduledBlockRecord], for day: Date = Date()) {
        guard let database = handle?.pointer else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return }
        var shouldCommit = false
        defer {
            _ = sqlite3_exec(database, shouldCommit ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }
        let dayKey = Self.dayKey(for: day)
        guard let delete = prepare("DELETE FROM scheduled_blocks WHERE day_key = ?;", database: database) else { return }
        defer { sqlite3_finalize(delete) }
        bind(dayKey, to: delete, index: 1)
        guard sqlite3_step(delete) == SQLITE_DONE else { return }

        let sql = "INSERT INTO scheduled_blocks (day_key, plan_item_id, calendar_event_id, start_at, end_at, updated_at) VALUES (?, ?, ?, ?, ?, ?);"
        for block in blocks {
            guard let statement = prepare(sql, database: database) else { return }
            bind(dayKey, to: statement, index: 1)
            bind(block.planItemID, to: statement, index: 2)
            bind(block.calendarEventID, to: statement, index: 3)
            bind(dateFormatter.string(from: block.start), to: statement, index: 4)
            bind(dateFormatter.string(from: block.end), to: statement, index: 5)
            bind(dateFormatter.string(from: Date()), to: statement, index: 6)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                return
            }
            sqlite3_finalize(statement)
        }
        shouldCommit = true
    }

    func loadScheduledBlocks(for day: Date = Date()) -> [ScheduledBlockRecord] {
        guard let database = handle?.pointer else { return [] }
        let sql = "SELECT plan_item_id, calendar_event_id, start_at, end_at FROM scheduled_blocks WHERE day_key = ? ORDER BY start_at ASC;"
        guard let statement = prepare(sql, database: database) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(Self.dayKey(for: day), to: statement, index: 1)
        var blocks: [ScheduledBlockRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let planItemID = columnText(statement, index: 0),
                  let calendarEventID = columnText(statement, index: 1),
                  let startRaw = columnText(statement, index: 2),
                  let endRaw = columnText(statement, index: 3),
                  let start = dateFormatter.date(from: startRaw),
                  let end = dateFormatter.date(from: endRaw)
            else { continue }
            blocks.append(ScheduledBlockRecord(planItemID: planItemID, calendarEventID: calendarEventID, start: start, end: end))
        }
        return blocks
    }

    func replaceReminderListOrder(_ listIDs: [String]) {
        guard let database = handle?.pointer else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return }
        var shouldCommit = false
        defer {
            _ = sqlite3_exec(database, shouldCommit ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }
        guard let delete = prepare("DELETE FROM reminder_list_order;", database: database) else { return }
        defer { sqlite3_finalize(delete) }
        guard sqlite3_step(delete) == SQLITE_DONE else { return }

        let sql = "INSERT INTO reminder_list_order (list_id, position, updated_at) VALUES (?, ?, ?);"
        for (index, listID) in listIDs.enumerated() {
            guard let statement = prepare(sql, database: database) else { return }
            bind(listID, to: statement, index: 1)
            sqlite3_bind_int(statement, 2, Int32(index))
            bind(dateFormatter.string(from: Date()), to: statement, index: 3)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                return
            }
            sqlite3_finalize(statement)
        }
        shouldCommit = true
    }

    func loadReminderListOrder() -> [String] {
        guard let database = handle?.pointer else { return [] }
        guard let statement = prepare("SELECT list_id FROM reminder_list_order ORDER BY position ASC;", database: database) else { return [] }
        defer { sqlite3_finalize(statement) }
        var listIDs: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let listID = columnText(statement, index: 0) {
                listIDs.append(listID)
            }
        }
        return listIDs
    }

    private nonisolated static func migrate(database: OpaquePointer?) {
        guard let database else { return }
        let schema = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS source_checkpoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id TEXT NOT NULL,
            state TEXT NOT NULL,
            detail TEXT NOT NULL,
            evidence TEXT NOT NULL,
            checked_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS source_checkpoints_source_time ON source_checkpoints(source_id, checked_at);
        CREATE TABLE IF NOT EXISTS daily_plan_entries (
            day_key TEXT NOT NULL,
            reminder_id TEXT NOT NULL,
            rank INTEGER NOT NULL,
            is_main_objective INTEGER NOT NULL,
            estimate_minutes INTEGER,
            is_optional INTEGER NOT NULL DEFAULT 0,
            blocked_reason TEXT,
            deferred_until_utc TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (day_key, reminder_id)
        );
        CREATE INDEX IF NOT EXISTS daily_plan_entries_day_rank ON daily_plan_entries(day_key, rank);
        CREATE TABLE IF NOT EXISTS reminder_list_order (
            list_id TEXT PRIMARY KEY,
            position INTEGER NOT NULL,
            updated_at TEXT NOT NULL
        );
        INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, CURRENT_TIMESTAMP);
        INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (2, CURRENT_TIMESTAMP);
        """
        _ = sqlite3_exec(database, schema, nil, nil, nil)
        _ = sqlite3_exec(database, "ALTER TABLE daily_plan_entries ADD COLUMN is_optional INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        _ = sqlite3_exec(database, "ALTER TABLE daily_plan_entries ADD COLUMN blocked_reason TEXT;", nil, nil, nil)
        _ = sqlite3_exec(database, "ALTER TABLE daily_plan_entries ADD COLUMN deferred_until_utc TEXT;", nil, nil, nil)
        applyMigration(
            version: 3,
            statements: [
                "ALTER TABLE daily_plan_entries ADD COLUMN selection_reason TEXT;",
                "ALTER TABLE daily_plan_entries ADD COLUMN selection_score INTEGER;"
            ],
            database: database
        )
        applyMigration(
            version: 4,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS scheduled_blocks (
                    day_key TEXT NOT NULL,
                    plan_item_id TEXT NOT NULL,
                    calendar_event_id TEXT NOT NULL,
                    start_at TEXT NOT NULL,
                    end_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (day_key, plan_item_id)
                );
                """,
                "CREATE INDEX IF NOT EXISTS scheduled_blocks_day_start ON scheduled_blocks(day_key, start_at);"
            ],
            database: database
        )
    }

    private nonisolated static func applyMigration(version: Int, statements: [String], database: OpaquePointer) {
        guard !migrationIsApplied(version, database: database) else { return }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer {
            _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }
        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else { return }
        }
        let record = "INSERT INTO schema_migrations(version, applied_at) VALUES (\(version), CURRENT_TIMESTAMP);"
        guard sqlite3_exec(database, record, nil, nil, nil) == SQLITE_OK else { return }
        committed = true
    }

    private nonisolated static func migrationIsApplied(_ version: Int, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM schema_migrations WHERE version = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(version))
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func prepare(_ sql: String, database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32) {
        _ = value.withCString { pointer in sqlite3_bind_text(statement, index, pointer, -1, SQLITE_TRANSIENT) }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private static func defaultDatabaseURL() -> URL {
        ZoidCoachStorage.databaseURL()
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteDatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init?(path: String, readOnly: Bool = false) {
        var database: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            return nil
        }
        pointer = database
    }

    deinit { sqlite3_close(pointer) }
}
