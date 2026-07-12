import CryptoKit
import Foundation
import SQLite3

public enum ReminderSourceKind: String, Codable, Equatable, Sendable {
    case reminders
    case local
}

public struct ReminderSourceSnapshot: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public let priority: Int
    public let notes: String?
    public let listID: String?
    public let listName: String?
    public let modificationDate: Date?
    public let isCompleted: Bool
    public let sourceKind: ReminderSourceKind

    public init(id: String, title: String, dueDate: Date?, priority: Int, notes: String? = nil, listID: String? = nil, listName: String? = nil, modificationDate: Date? = nil, isCompleted: Bool = false, sourceKind: ReminderSourceKind = .reminders) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
        self.listID = listID
        self.listName = listName
        self.modificationDate = modificationDate
        self.isCompleted = isCompleted
        self.sourceKind = sourceKind
    }
}

public struct ReminderSyncResult: Equatable, Sendable {
    public let insertedCount: Int
    public let updatedCount: Int
    public let removedCount: Int
    public let unchangedCount: Int
}

public final class ReminderSnapshotStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw ReminderSnapshotStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func replace(_ reminders: [ReminderSourceSnapshot]) throws {
        _ = try synchronize(reminders)
    }

    @discardableResult
    public func synchronize(_ reminders: [ReminderSourceSnapshot], observedAt: Date = Date(), timeZone: TimeZone = .current) throws -> ReminderSyncResult {
        guard reminders.allSatisfy({ $0.sourceKind == .reminders }) else {
            throw ReminderSnapshotStoreError.invalidExternalSourceKind
        }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ReminderSnapshotStoreError.write }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }
        var inserted = 0
        var updated = 0
        var unchanged = 0
        let existing = try existingHashes()
        let incomingIDs = Set(reminders.map(\.id))
        let sql = """
        INSERT INTO source_tasks
        (source_id, title, notes, list_id, list_name, due_at, priority, is_completed, modified_at, source_hash, updated_at, source_kind)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_id) DO UPDATE SET
            title = excluded.title,
            notes = excluded.notes,
            list_id = excluded.list_id,
            list_name = excluded.list_name,
            due_at = excluded.due_at,
            priority = excluded.priority,
            is_completed = excluded.is_completed,
            modified_at = excluded.modified_at,
            source_hash = excluded.source_hash,
            updated_at = excluded.updated_at;
        """
        for reminder in reminders {
            let hash = try sourceHash(reminder)
            if try sourceKind(for: reminder.id) == .local {
                throw ReminderSnapshotStoreError.localSourceCollision(reminder.id)
            }
            if existing[reminder.id] == hash {
                unchanged += 1
                continue
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement
            else { throw ReminderSnapshotStoreError.write }
            defer { sqlite3_finalize(statement) }
            bind(reminder.id, statement, 1)
            bind(reminder.title, statement, 2)
            bindOptional(reminder.notes, statement, 3)
            bindOptional(reminder.listID, statement, 4)
            bindOptional(reminder.listName, statement, 5)
            if let dueDate = reminder.dueDate {
                bind(formatter.string(from: dueDate), statement, 6)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_int(statement, 7, Int32(reminder.priority))
            sqlite3_bind_int(statement, 8, reminder.isCompleted ? 1 : 0)
            bindOptional(reminder.modificationDate.map(formatter.string(from:)), statement, 9)
            bind(hash, statement, 10)
            bind(formatter.string(from: observedAt), statement, 11)
            bind(ReminderSourceKind.reminders.rawValue, statement, 12)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
            let wasInserted = existing[reminder.id] == nil
            if wasInserted { inserted += 1 } else { updated += 1 }
            try appendSourceEvent(type: wasInserted ? "source_task.created" : "source_task.updated", taskID: reminder.id, hash: hash, observedAt: observedAt, timeZone: timeZone)
        }
        let removedIDs = Set(existing.keys).subtracting(incomingIDs)
        for id in removedIDs {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM source_tasks WHERE source_id = ? AND source_kind = 'reminders';", -1, &statement, nil) == SQLITE_OK, let statement else { throw ReminderSnapshotStoreError.write }
            bind(id, statement, 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { sqlite3_finalize(statement); throw ReminderSnapshotStoreError.write }
            sqlite3_finalize(statement)
            try appendSourceEvent(type: "source_task.removed", taskID: id, hash: existing[id] ?? "", observedAt: observedAt, timeZone: timeZone)
        }
        committed = true
        return ReminderSyncResult(insertedCount: inserted, updatedCount: updated, removedCount: removedIDs.count, unchangedCount: unchanged)
    }

    @discardableResult
    public func upsertLocal(_ task: ReminderSourceSnapshot, observedAt: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        guard task.sourceKind == .local,
              !task.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ReminderSnapshotStoreError.invalidLocalTask }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ReminderSnapshotStoreError.write }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }

        if try sourceKind(for: task.id) == .reminders {
            throw ReminderSnapshotStoreError.localSourceCollision(task.id)
        }
        let hash = try sourceHash(task)
        if try storedHash(for: task.id) == hash {
            committed = true
            return false
        }

        let sql = """
        INSERT INTO source_tasks
        (source_id, title, notes, list_id, list_name, due_at, priority, is_completed, modified_at, source_hash, updated_at, source_kind)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'local')
        ON CONFLICT(source_id) DO UPDATE SET
            title = excluded.title,
            notes = excluded.notes,
            list_id = excluded.list_id,
            list_name = excluded.list_name,
            due_at = excluded.due_at,
            priority = excluded.priority,
            is_completed = excluded.is_completed,
            modified_at = excluded.modified_at,
            source_hash = excluded.source_hash,
            updated_at = excluded.updated_at,
            source_kind = 'local';
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReminderSnapshotStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(task.id, statement, 1)
        bind(task.title, statement, 2)
        bindOptional(task.notes, statement, 3)
        bindOptional(task.listID, statement, 4)
        bindOptional(task.listName, statement, 5)
        bindOptional(task.dueDate.map(formatter.string(from:)), statement, 6)
        sqlite3_bind_int(statement, 7, Int32(task.priority))
        sqlite3_bind_int(statement, 8, task.isCompleted ? 1 : 0)
        bindOptional(task.modificationDate.map(formatter.string(from:)), statement, 9)
        bind(hash, statement, 10)
        bind(formatter.string(from: observedAt), statement, 11)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
        try appendSourceEvent(type: "source_task.local_upserted", taskID: task.id, hash: hash, observedAt: observedAt, timeZone: timeZone)
        committed = true
        return true
    }

    public func loadIncomplete() throws -> [ReminderSourceSnapshot] {
        let sql = "SELECT source_id, title, due_at, priority, notes, list_id, list_name, modified_at, is_completed, source_kind FROM source_tasks WHERE is_completed = 0 ORDER BY due_at IS NULL, due_at ASC, title ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        var reminders: [ReminderSourceSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0), let title = text(statement, 1) else { continue }
            let dueDate = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : text(statement, 2).flatMap(formatter.date(from:))
            reminders.append(ReminderSourceSnapshot(
                id: id,
                title: title,
                dueDate: dueDate,
                priority: Int(sqlite3_column_int(statement, 3)),
                notes: text(statement, 4),
                listID: text(statement, 5),
                listName: text(statement, 6),
                modificationDate: text(statement, 7).flatMap(formatter.date(from:)),
                isCompleted: sqlite3_column_int(statement, 8) == 1,
                sourceKind: text(statement, 9).flatMap(ReminderSourceKind.init(rawValue:)) ?? .reminders
            ))
        }
        return reminders
    }

    public func lastUpdatedAt() throws -> Date? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT MAX(updated_at) FROM source_tasks;", -1, &statement, nil) == SQLITE_OK, let statement else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = text(statement, 0) else { return nil }
        return formatter.date(from: value)
    }

    private func existingHashes() throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT source_id, source_hash FROM source_tasks WHERE source_kind = 'reminders';", -1, &statement, nil) == SQLITE_OK, let statement else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        var result: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW, let id = text(statement, 0) {
            result[id] = text(statement, 1) ?? ""
        }
        return result
    }

    private func sourceKind(for id: String) throws -> ReminderSourceKind? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT source_kind FROM source_tasks WHERE source_id = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(id, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0).flatMap(ReminderSourceKind.init(rawValue:)) ?? .reminders
    }

    private func storedHash(for id: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT source_hash FROM source_tasks WHERE source_id = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(id, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func sourceHash(_ reminder: ReminderSourceSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(HashableReminder(reminder))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func appendSourceEvent(type: String, taskID: String, hash: String, observedAt: Date, timeZone: TimeZone) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: observedAt)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let sql = "INSERT INTO domain_events(id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json) VALUES (?, ?, ?, ?, ?, ?, 1, '[]', ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ReminderSnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, statement, 1)
        bind(type, statement, 2)
        bind(taskID, statement, 3)
        bind(day, statement, 4)
        bind(timeZone.identifier, statement, 5)
        bind(formatter.string(from: observedAt), statement, 6)
        bind("{\"sourceHash\":\"\(hash)\"}", statement, 7)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func bindOptional(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        if let value { bind(value, statement, index) } else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}

private struct HashableReminder: Codable {
    let id: String
    let title: String
    let dueDate: Date?
    let priority: Int
    let notes: String?
    let listID: String?
    let listName: String?
    let modificationDate: Date?
    let isCompleted: Bool

    init(_ reminder: ReminderSourceSnapshot) {
        id = reminder.id
        title = reminder.title
        dueDate = reminder.dueDate
        priority = reminder.priority
        notes = reminder.notes
        listID = reminder.listID
        listName = reminder.listName
        modificationDate = reminder.modificationDate
        isCompleted = reminder.isCompleted
    }
}

public enum ReminderSnapshotStoreError: LocalizedError {
    case openDatabase
    case schema
    case read
    case write
    case invalidExternalSourceKind
    case invalidLocalTask
    case localSourceCollision(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open reminder snapshot storage"
        case .schema: "Could not create reminder snapshot storage"
        case .read: "Could not read reminder snapshots"
        case .write: "Could not update reminder snapshots"
        case .invalidExternalSourceKind: "External reminder sync only accepts Reminders source tasks"
        case .invalidLocalTask: "Local fallback tasks require a non-empty identifier and title"
        case let .localSourceCollision(id): "A different task source already owns identifier \(id)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
