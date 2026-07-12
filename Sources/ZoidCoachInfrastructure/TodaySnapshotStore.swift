import Foundation
import SQLite3
import ZoidCoachCore

public final class TodaySnapshotStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL, readOnly: Bool = false) throws {
        if !readOnly { try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true) }
        if !readOnly { try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate() }
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle
        else { throw TodaySnapshotStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit { sqlite3_close(database) }

    public func save(_ snapshot: TodaySnapshot, for day: Date = Date()) throws {
        let sql = "INSERT INTO today_snapshots(day_key, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(day_key) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TodaySnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(day), statement, 1)
        let data = try encoder.encode(snapshot)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
        bind(formatter.string(from: Date()), statement, 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TodaySnapshotStoreError.write }
    }

    public func load(for day: Date = Date()) throws -> TodaySnapshot? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM today_snapshots WHERE day_key = ?;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TodaySnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(day), statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_blob(statement, 0)
        else { return nil }
        let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0)))
        return try decoder.decode(TodaySnapshot.self, from: data)
    }

    public func applyPriorityRewardIfNeeded(taskID: String, policy: GamingPolicy, day: Date = Date()) throws -> Bool {
        let sql = "INSERT OR IGNORE INTO gaming_reward_ledger(day_key, task_id, policy_version, applied_at, reward_minutes) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw TodaySnapshotStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(day), statement, 1)
        bind(taskID, statement, 2)
        sqlite3_bind_int(statement, 3, Int32(policy.version))
        bind(formatter.string(from: Date()), statement, 4)
        sqlite3_bind_int(statement, 5, Int32(policy.priorityTaskRewardMinutes))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TodaySnapshotStoreError.write }
        return sqlite3_changes(database) == 1
    }

    public func hasPriorityReward(policy: GamingPolicy, day: Date = Date()) throws -> Bool {
        try priorityRewardMinutes(policy: policy, day: day) != nil
    }

    public func priorityRewardMinutes(
        policy: GamingPolicy,
        day: Date = Date()
    ) throws -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT reward_minutes FROM gaming_reward_ledger WHERE day_key = ? AND policy_version = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK, let statement else { throw TodaySnapshotStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(dayKey(day), statement, 1)
        sqlite3_bind_int(statement, 2, Int32(policy.version))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return max(0, Int(sqlite3_column_int(statement, 0)))
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }
}

public enum TodaySnapshotStoreError: LocalizedError {
    case openDatabase, schema, read, write
    public var errorDescription: String? { "Could not persist the agent-owned Today snapshot." }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
