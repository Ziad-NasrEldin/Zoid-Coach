import Foundation
import SQLite3
import ZoidCoachCore

public struct VersionedUserPolicy: Equatable, Sendable {
    public let version: Int
    public let policy: UserPolicy
    public let createdAtUTC: Date
    public let isActive: Bool

    public init(version: Int, policy: UserPolicy, createdAtUTC: Date, isActive: Bool) {
        self.version = version
        self.policy = policy
        self.createdAtUTC = createdAtUTC
        self.isActive = isActive
    }
}

public final class PolicyStore: @unchecked Sendable {
    private static let policyType = "user_policy"
    private static let settingsKey = "user_policy"

    private let database: OpaquePointer
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        readOnly: Bool = false,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        if !readOnly { try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate() }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw PolicyStoreError.openDatabase
        }
        database = handle
        self.now = now
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit {
        sqlite3_close(database)
    }

    @discardableResult
    public func save(_ policy: UserPolicy) throws -> VersionedUserPolicy {
        let policy = policy.upgradedToCurrentSchema()
        let violations = policy.validationViolations()
        guard violations.isEmpty else { throw PolicyStoreError.invalidPolicy(violations) }
        let payload = try encode(policy)
        let createdAt = now()
        let timestamp = Self.timestamp(createdAt)

        lock.lock()
        defer { lock.unlock() }
        return try inTransaction {
            let version = try nextVersion()
            try execute(
                "UPDATE policy_versions SET is_active = 0 WHERE policy_type = ?;",
                bindings: [.text(Self.policyType)]
            )
            try execute(
                """
                INSERT INTO policy_versions(policy_type, version, payload_json, created_at_utc, is_active)
                VALUES (?, ?, ?, ?, 1);
                """,
                bindings: [.text(Self.policyType), .integer(version), .text(payload), .text(timestamp)]
            )
            try upsertSetting(payload: payload, version: version, timestamp: timestamp)
            return VersionedUserPolicy(
                version: version,
                policy: policy,
                createdAtUTC: createdAt,
                isActive: true
            )
        }
    }

    public func current() throws -> VersionedUserPolicy? {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT p.version, s.value_json, p.created_at_utc, p.is_active
        FROM settings AS s
        JOIN policy_versions AS p
          ON p.policy_type = ? AND p.version = s.policy_version
        WHERE s.key = ?
        LIMIT 1;
        """
        return try readOne(
            sql,
            bindings: [.text(Self.policyType), .text(Self.settingsKey)]
        )
    }

    public func effective(at date: Date) throws -> VersionedUserPolicy? {
        lock.lock()
        defer { lock.unlock() }
        return try readOne(
            """
            SELECT version, payload_json, created_at_utc, is_active
            FROM policy_versions
            WHERE policy_type = ? AND julianday(created_at_utc) <= julianday(?)
            ORDER BY julianday(created_at_utc) DESC, version DESC
            LIMIT 1;
            """,
            bindings: [.text(Self.policyType), .text(Self.timestamp(date))]
        )
    }

    public func history(limit: Int = 50) throws -> [VersionedUserPolicy] {
        guard limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT version, payload_json, created_at_utc, is_active
        FROM policy_versions
        WHERE policy_type = ?
        ORDER BY version DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        try bind([.text(Self.policyType), .integer(limit)], to: statement)
        var result: [VersionedUserPolicy] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append(try decodeRow(statement))
            case SQLITE_DONE:
                return result
            default:
                throw databaseError(.read)
            }
        }
    }

    @discardableResult
    public func rollback(to version: Int) throws -> VersionedUserPolicy {
        lock.lock()
        let target: VersionedUserPolicy
        do {
            guard let stored = try readOne(
                """
                SELECT version, payload_json, created_at_utc, is_active
                FROM policy_versions
                WHERE policy_type = ? AND version = ?
                LIMIT 1;
                """,
                bindings: [.text(Self.policyType), .integer(version)]
            ) else {
                throw PolicyStoreError.versionNotFound(version)
            }
            target = stored
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        return try save(target.policy.upgradedToCurrentSchema())
    }

    private func nextVersion() throws -> Int {
        let sql = "SELECT COALESCE(MAX(version), 0) + 1 FROM policy_versions WHERE policy_type = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        try bind([.text(Self.policyType)], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError(.read) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func upsertSetting(payload: String, version: Int, timestamp: String) throws {
        try execute(
            """
            INSERT INTO settings(key, value_json, policy_version, updated_at_utc)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value_json = excluded.value_json,
                policy_version = excluded.policy_version,
                updated_at_utc = excluded.updated_at_utc;
            """,
            bindings: [
                .text(Self.settingsKey),
                .text(payload),
                .integer(version),
                .text(timestamp)
            ]
        )
    }

    private func readOne(_ sql: String, bindings: [SQLiteBinding]) throws -> VersionedUserPolicy? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return try decodeRow(statement)
        case SQLITE_DONE:
            return nil
        default:
            throw databaseError(.read)
        }
    }

    private func decodeRow(_ statement: OpaquePointer) throws -> VersionedUserPolicy {
        guard let payloadPointer = sqlite3_column_text(statement, 1),
              let createdPointer = sqlite3_column_text(statement, 2) else {
            throw PolicyStoreError.corruptPolicy
        }
        let payload = String(cString: payloadPointer)
        let created = String(cString: createdPointer)
        guard let data = payload.data(using: .utf8),
              let createdAt = Self.parseTimestamp(created) else {
            throw PolicyStoreError.corruptPolicy
        }
        do {
            let policy = try JSONDecoder.zoidPolicy.decode(UserPolicy.self, from: data)
            let violations = policy.upgradedToCurrentSchema().validationViolations()
            guard violations.isEmpty else { throw PolicyStoreError.invalidPolicy(violations) }
            return VersionedUserPolicy(
                version: Int(sqlite3_column_int64(statement, 0)),
                policy: policy,
                createdAtUTC: createdAt,
                isActive: sqlite3_column_int(statement, 3) == 1
            )
        } catch let error as PolicyStoreError {
            throw error
        } catch {
            throw PolicyStoreError.decode(error.localizedDescription)
        }
    }

    private func encode(_ policy: UserPolicy) throws -> String {
        do {
            let data = try JSONEncoder.zoidPolicy.encode(policy)
            guard let payload = String(data: data, encoding: .utf8) else {
                throw PolicyStoreError.encode("Policy JSON was not UTF-8.")
            }
            return payload
        } catch let error as PolicyStoreError {
            throw error
        } catch {
            throw PolicyStoreError.encode(error.localizedDescription)
        }
    }

    private func inTransaction<T>(_ body: () throws -> T) throws -> T {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(.write)
        }
        do {
            let result = try body()
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw databaseError(.write)
            }
            return result
        } catch {
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(.write)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case let .integer(value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case let .text(value):
                result = value.withCString {
                    sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT)
                }
            }
            guard result == SQLITE_OK else { throw databaseError(.write) }
        }
    }

    private func databaseError(_ operation: PolicyStoreError.Operation) -> PolicyStoreError {
        let message = sqlite3_errmsg(database).map(String.init(cString:)) ?? "Unknown SQLite error"
        return .database(operation, message)
    }

    private static func timestamp(_ date: Date) -> String {
        preciseFormatter().string(from: date)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        preciseFormatter().date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func preciseFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private enum SQLiteBinding {
    case integer(Int)
    case text(String)
}

public enum PolicyStoreError: Error, Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case read
        case write
    }

    case openDatabase
    case database(Operation, String)
    case invalidPolicy([PolicyViolation])
    case versionNotFound(Int)
    case corruptPolicy
    case encode(String)
    case decode(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
