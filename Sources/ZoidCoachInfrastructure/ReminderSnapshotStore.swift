import CryptoKit
import Foundation
import SQLite3
import ZoidCoachCore

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
    public let declaredContext: DeclaredTaskContext?

    public init(id: String, title: String, dueDate: Date?, priority: Int, notes: String? = nil, listID: String? = nil, listName: String? = nil, modificationDate: Date? = nil, isCompleted: Bool = false, sourceKind: ReminderSourceKind = .reminders, declaredContext: DeclaredTaskContext? = nil) {
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
        self.declaredContext = declaredContext
    }
}

public struct ReminderSyncResult: Equatable, Sendable {
    public let insertedCount: Int
    public let updatedCount: Int
    public let removedCount: Int
    public let unchangedCount: Int
}

public enum DeletedReminderDecisionState: String, Equatable, Sendable {
    case pending
    case kept
}

public struct DeletedReminderDecision: Identifiable, Equatable, Sendable {
    public let sourceID: String
    public let title: String
    public let dueDate: Date?
    public let listName: String?
    public let deletedAt: Date
    public let state: DeletedReminderDecisionState
    public let decidedAt: Date?

    public var id: String { sourceID }

    public init(
        sourceID: String,
        title: String,
        dueDate: Date?,
        listName: String?,
        deletedAt: Date,
        state: DeletedReminderDecisionState,
        decidedAt: Date?
    ) {
        self.sourceID = sourceID
        self.title = title
        self.dueDate = dueDate
        self.listName = listName
        self.deletedAt = deletedAt
        self.state = state
        self.decidedAt = decidedAt
    }
}

public final class ReminderSnapshotStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSRecursiveLock()
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
        lock.lock()
        defer { lock.unlock() }
        guard reminders.allSatisfy({ $0.sourceKind == .reminders }) else {
            throw ReminderSnapshotStoreError.invalidExternalSourceKind
        }
        let incomingIdentifiers = reminders.map(\.id)
        guard incomingIdentifiers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(incomingIdentifiers).count == incomingIdentifiers.count
        else { throw ReminderSnapshotStoreError.duplicateOrInvalidExternalSourceID }
        let incomingHashes = try Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, try sourceHash($0)) })
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ReminderSnapshotStoreError.write }
        var committed = false
        defer { if !committed { _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) } }

        for reminder in reminders {
            if try sourceKind(for: reminder.id) == .local {
                throw ReminderSnapshotStoreError.localSourceCollision(reminder.id)
            }
        }
        var inserted = 0
        var updated = 0
        var unchanged = 0
        let existing = try existingHashes()
        let incomingIDs = Set(reminders.map(\.id))

        for id in incomingIDs {
            try clearDeletedReminderDecision(sourceID: id)
        }
        let sql = """
        INSERT INTO source_tasks
        (source_id, title, notes, list_id, list_name, due_at, priority, is_completed, modified_at, source_hash, updated_at, source_kind, declared_context)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            declared_context = excluded.declared_context;
        """
        for reminder in reminders {
            let hash = incomingHashes[reminder.id] ?? ""
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
            bindOptional(reminder.declaredContext?.rawValue, statement, 13)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
            let wasInserted = existing[reminder.id] == nil
            if wasInserted { inserted += 1 } else { updated += 1 }
            try appendSourceEvent(type: wasInserted ? "source_task.created" : "source_task.updated", taskID: reminder.id, hash: hash, observedAt: observedAt, timeZone: timeZone)
        }
        let removedIDs = Set(existing.keys).subtracting(incomingIDs)
        for id in removedIDs {
            try archiveDeletedReminderDecision(sourceID: id, deletedAt: observedAt)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM source_tasks WHERE source_id = ? AND source_kind = 'reminders';", -1, &statement, nil) == SQLITE_OK, let statement else { throw ReminderSnapshotStoreError.write }
            bind(id, statement, 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { sqlite3_finalize(statement); throw ReminderSnapshotStoreError.write }
            sqlite3_finalize(statement)
            try appendSourceEvent(type: "source_task.removed", taskID: id, hash: existing[id] ?? "", observedAt: observedAt, timeZone: timeZone)
        }
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw ReminderSnapshotStoreError.write
        }
        committed = true
        return ReminderSyncResult(insertedCount: inserted, updatedCount: updated, removedCount: removedIDs.count, unchangedCount: unchanged)
    }

    public func deletedReminderDecisions() throws -> [DeletedReminderDecision] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let sql = """
        SELECT source_id, title, due_at, list_name, deleted_at_utc, state, decided_at_utc
        FROM deleted_reminder_decisions
        ORDER BY CASE state WHEN 'pending' THEN 0 ELSE 1 END, deleted_at_utc DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReminderSnapshotStoreError.read
        }
        defer { sqlite3_finalize(statement) }

        var decisions: [DeletedReminderDecision] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceID = text(statement, 0),
                  let title = text(statement, 1),
                  let deletedAtValue = text(statement, 4),
                  let deletedAt = formatter.date(from: deletedAtValue),
                  let stateValue = text(statement, 5),
                  let state = DeletedReminderDecisionState(rawValue: stateValue)
            else { throw ReminderSnapshotStoreError.read }
            decisions.append(DeletedReminderDecision(
                sourceID: sourceID,
                title: title,
                dueDate: text(statement, 2).flatMap(formatter.date(from:)),
                listName: text(statement, 3),
                deletedAt: deletedAt,
                state: state,
                decidedAt: text(statement, 6).flatMap(formatter.date(from:))
            ))
        }
        return decisions
    }

    @discardableResult
    public func keepDeletedReminderInLocalHistory(sourceID: String, decidedAt: Date = Date()) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let sql = "UPDATE deleted_reminder_decisions SET state = 'kept', decided_at_utc = ? WHERE source_id = ? AND state = 'pending';"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReminderSnapshotStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: decidedAt), statement, 1)
        bind(sourceID, statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
        return sqlite3_changes(database) == 1
    }

    @discardableResult
    public func removeDeletedReminderLocalCopy(sourceID: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM deleted_reminder_decisions WHERE source_id = ? AND state = 'pending';", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
        return sqlite3_changes(database) == 1
    }

    @discardableResult
    public func createLocal(_ task: ReminderSourceSnapshot, observedAt: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard task.sourceKind == .local,
              !task.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ReminderSnapshotStoreError.invalidLocalTask }
        if try sourceKind(for: task.id) == .reminders {
            throw ReminderSnapshotStoreError.localSourceCollision(task.id)
        }
        let hash = try sourceHash(task)
        if let storedHash = try storedHash(for: task.id) {
            guard storedHash == hash else {
                throw ReminderSnapshotStoreError.localTaskConflict(task.id)
            }
            return false
        }
        return try upsertLocal(task, observedAt: observedAt, timeZone: timeZone)
    }

    @discardableResult
    public func upsertLocal(_ task: ReminderSourceSnapshot, observedAt: Date = Date(), timeZone: TimeZone = .current) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard task.sourceKind == .local,
              !task.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ReminderSnapshotStoreError.invalidLocalTask }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ReminderSnapshotStoreError.write }
        var committed = false
        defer { if !committed { _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) } }

        if try sourceKind(for: task.id) == .reminders {
            throw ReminderSnapshotStoreError.localSourceCollision(task.id)
        }
        let hash = try sourceHash(task)
        if try storedHash(for: task.id) == hash {
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw ReminderSnapshotStoreError.write
            }
            committed = true
            return false
        }

        let sql = """
        INSERT INTO source_tasks
        (source_id, title, notes, list_id, list_name, due_at, priority, is_completed, modified_at, source_hash, updated_at, source_kind, declared_context)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'local', ?)
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
            source_kind = 'local',
            declared_context = excluded.declared_context;
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
        bindOptional(task.declaredContext?.rawValue, statement, 12)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
        try appendSourceEvent(type: "source_task.local_upserted", taskID: task.id, hash: hash, observedAt: observedAt, timeZone: timeZone)
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw ReminderSnapshotStoreError.write
        }
        committed = true
        return true
    }

    public func completeLocal(id: String, completedAt: Date = Date(), timeZone: TimeZone = .current) throws {
        lock.lock()
        defer { lock.unlock() }
        guard try sourceKind(for: id) == .local else {
            throw ReminderSnapshotStoreError.invalidLocalTask
        }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw ReminderSnapshotStoreError.write
        }
        var committed = false
        defer { if !committed { _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) } }
        var statement: OpaquePointer?
        let sql = "UPDATE source_tasks SET is_completed = 1, modified_at = ?, updated_at = ? WHERE source_id = ? AND source_kind = 'local';"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        let timestamp = formatter.string(from: completedAt)
        bind(timestamp, statement, 1)
        bind(timestamp, statement, 2)
        bind(id, statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
            throw ReminderSnapshotStoreError.write
        }
        try appendSourceEvent(
            type: "source_task.local_completed",
            taskID: id,
            hash: try storedHash(for: id) ?? "",
            observedAt: completedAt,
            timeZone: timeZone
        )
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw ReminderSnapshotStoreError.write
        }
        committed = true
    }

    public func sourceKind(forID id: String) throws -> ReminderSourceKind? {
        lock.lock()
        defer { lock.unlock() }
        return try sourceKind(for: id)
    }

    public func snapshot(forID id: String) throws -> ReminderSourceSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT source_id, title, due_at, priority, notes, list_id, list_name, modified_at, is_completed, source_kind, declared_context FROM source_tasks WHERE source_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(id, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let sourceID = text(statement, 0),
              let title = text(statement, 1)
        else { return nil }
        return ReminderSourceSnapshot(
            id: sourceID,
            title: title,
            dueDate: text(statement, 2).flatMap(formatter.date(from:)),
            priority: Int(sqlite3_column_int(statement, 3)),
            notes: text(statement, 4),
            listID: text(statement, 5),
            listName: text(statement, 6),
            modificationDate: text(statement, 7).flatMap(formatter.date(from:)),
            isCompleted: sqlite3_column_int(statement, 8) == 1,
            sourceKind: try decodedSourceKind(text(statement, 9)),
            declaredContext: try decodedDeclaredContext(text(statement, 10))
        )
    }

    public func loadIncomplete() throws -> [ReminderSourceSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT source_id, title, due_at, priority, notes, list_id, list_name, modified_at, is_completed, source_kind, declared_context FROM source_tasks WHERE is_completed = 0 ORDER BY due_at IS NULL, due_at ASC, title ASC;"
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
                sourceKind: try decodedSourceKind(text(statement, 9)),
                declaredContext: try decodedDeclaredContext(text(statement, 10))
            ))
        }
        return reminders
    }

    public func lastUpdatedAt() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
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

    private func archiveDeletedReminderDecision(sourceID: String, deletedAt: Date) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO deleted_reminder_decisions(source_id, title, due_at, list_name, deleted_at_utc, state, decided_at_utc)
        SELECT source_id, title, due_at, list_name, ?, 'pending', NULL
        FROM source_tasks WHERE source_id = ? AND source_kind = 'reminders'
        ON CONFLICT(source_id) DO UPDATE SET
            title = excluded.title,
            due_at = excluded.due_at,
            list_name = excluded.list_name,
            deleted_at_utc = excluded.deleted_at_utc,
            state = 'pending',
            decided_at_utc = NULL;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReminderSnapshotStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: deletedAt), statement, 1)
        bind(sourceID, statement, 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
    }

    private func clearDeletedReminderDecision(sourceID: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM deleted_reminder_decisions WHERE source_id = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ReminderSnapshotStoreError.write }
    }

    private func sourceKind(for id: String) throws -> ReminderSourceKind? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT source_kind FROM source_tasks WHERE source_id = ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ReminderSnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(id, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodedSourceKind(text(statement, 0))
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

    private func decodedSourceKind(_ rawValue: String?) throws -> ReminderSourceKind {
        guard let rawValue, let kind = ReminderSourceKind(rawValue: rawValue) else {
            throw ReminderSnapshotStoreError.invalidStoredSourceKind(rawValue)
        }
        return kind
    }

    private func decodedDeclaredContext(_ rawValue: String?) throws -> DeclaredTaskContext? {
        guard let rawValue else { return nil }
        guard let context = DeclaredTaskContext(rawValue: rawValue) else {
            throw ReminderSnapshotStoreError.invalidStoredDeclaredContext(rawValue)
        }
        return context
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
    let declaredContext: DeclaredTaskContext?

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
        declaredContext = reminder.declaredContext
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
    case localTaskConflict(String)
    case duplicateOrInvalidExternalSourceID
    case invalidStoredSourceKind(String?)
    case invalidStoredDeclaredContext(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open reminder snapshot storage"
        case .schema: "Could not create reminder snapshot storage"
        case .read: "Could not read reminder snapshots"
        case .write: "Could not update reminder snapshots"
        case .invalidExternalSourceKind: "External reminder sync only accepts Reminders source tasks"
        case .invalidLocalTask: "Local fallback tasks require a non-empty identifier and title"
        case let .localSourceCollision(id): "A different task source already owns identifier \(id)"
        case let .localTaskConflict(id): "A different local task already owns identifier \(id)"
        case .duplicateOrInvalidExternalSourceID: "External reminder sync requires unique, non-empty source identifiers"
        case let .invalidStoredSourceKind(kind): "The stored task source kind is invalid: \(kind ?? "missing")"
        case let .invalidStoredDeclaredContext(context): "The stored declared task context is invalid: \(context)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
