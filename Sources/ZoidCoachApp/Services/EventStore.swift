import Foundation
import SQLite3

struct StoredSourceCheck: Equatable, Sendable {
    let id: Int64
    let sourceID: SourceID
    let state: HealthState
    let detail: String
    let evidence: String
    let checkedAt: Date
}

actor EventStore {
    private let handle: SQLiteDatabaseHandle?
    private let dateFormatter = ISO8601DateFormatter()

    init(databaseURL: URL = EventStore.defaultDatabaseURL()) {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        handle = SQLiteDatabaseHandle(path: databaseURL.path)
        Self.migrate(database: handle?.pointer)
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
        INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, CURRENT_TIMESTAMP);
        """
        _ = sqlite3_exec(database, schema, nil, nil, nil)
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
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Zoid Coach", isDirectory: true).appendingPathComponent("zoid-coach.sqlite")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteDatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init?(path: String) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
            return nil
        }
        pointer = database
    }

    deinit { sqlite3_close(pointer) }
}
