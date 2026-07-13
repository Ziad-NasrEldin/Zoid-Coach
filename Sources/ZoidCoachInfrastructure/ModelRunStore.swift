import Foundation
import SQLite3
import ZoidCoachCore

public final class ModelRunStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let reservationLock = NSRecursiveLock()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(databaseURL: URL) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw ModelRunStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func record(_ run: ModelRun) throws {
        let sql = """
        INSERT INTO model_runs
        (id, provider, model, schema_version, prompt_version, normalized_input_hash, validation_state, redacted_diagnostic, started_at_utc, finished_at_utc, duration_milliseconds)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET validation_state = excluded.validation_state,
            redacted_diagnostic = excluded.redacted_diagnostic,
            finished_at_utc = excluded.finished_at_utc,
            duration_milliseconds = excluded.duration_milliseconds;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ModelRunStoreError.write }
        defer { sqlite3_finalize(statement) }
        bind(run.id, statement, 1)
        bind(run.provider, statement, 2)
        bind(run.model, statement, 3)
        sqlite3_bind_int(statement, 4, Int32(run.schemaVersion))
        sqlite3_bind_int(statement, 5, Int32(run.promptVersion))
        bind(run.normalizedInputHash, statement, 6)
        bind(run.validationState.rawValue, statement, 7)
        bindOptional(run.redactedDiagnostic, statement, 8)
        bind(formatter.string(from: run.startedAtUTC), statement, 9)
        bindOptional(run.finishedAtUTC.map(formatter.string(from:)), statement, 10)
        if let duration = run.durationMilliseconds { sqlite3_bind_int64(statement, 11, Int64(duration)) } else { sqlite3_bind_null(statement, 11) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ModelRunStoreError.write }
    }

    public func cachedValidatedRun(provider: String, model: String, schemaVersion: Int, normalizedInputHash: String) throws -> ModelRun? {
        let sql = """
        SELECT id, provider, model, schema_version, prompt_version, normalized_input_hash, validation_state,
               redacted_diagnostic, started_at_utc, finished_at_utc, duration_milliseconds
        FROM model_runs
        WHERE provider = ? AND model = ? AND schema_version = ? AND normalized_input_hash = ? AND validation_state = 'validated'
        ORDER BY started_at_utc DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ModelRunStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(provider, statement, 1)
        bind(model, statement, 2)
        sqlite3_bind_int(statement, 3, Int32(schemaVersion))
        bind(normalizedInputHash, statement, 4)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decode(statement)
    }

    public func requestCount(provider: String, since: Date) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM model_runs WHERE provider = ? AND started_at_utc >= ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ModelRunStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(provider, statement, 1)
        bind(formatter.string(from: since), statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ModelRunStoreError.read }
        return Int(sqlite3_column_int(statement, 0))
    }

    public func requestCount(since: Date) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM model_runs WHERE started_at_utc >= ?;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ModelRunStoreError.read }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: since), statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ModelRunStoreError.read }
        return Int(sqlite3_column_int(statement, 0))
    }

    public func canStartRequest(
        provider: String,
        dailyBudget: Int,
        monthlyBudget: Int = .max,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> Bool {
        guard dailyBudget > 0, monthlyBudget > 0 else { return false }
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: now)
        guard try requestCount(since: startOfDay) < dailyBudget else { return false }
        let monthComponents = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: monthComponents) else { throw ModelRunStoreError.read }
        return try requestCount(since: startOfMonth) < monthlyBudget
    }

    public func reserveRequest(
        _ pendingRun: ModelRun,
        dailyBudget: Int,
        monthlyBudget: Int,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> Bool {
        reservationLock.lock()
        defer { reservationLock.unlock() }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw ModelRunStoreError.write
        }
        var committed = false
        defer {
            if !committed { _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) }
        }
        guard try canStartRequest(
            provider: pendingRun.provider,
            dailyBudget: dailyBudget,
            monthlyBudget: monthlyBudget,
            now: now,
            calendar: calendar
        ) else {
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw ModelRunStoreError.write
            }
            committed = true
            return false
        }
        try record(pendingRun)
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw ModelRunStoreError.write
        }
        committed = true
        return true
    }

    private func decode(_ statement: OpaquePointer) -> ModelRun? {
        guard let id = text(statement, 0), let provider = text(statement, 1), let model = text(statement, 2),
              let hash = text(statement, 5), let stateRaw = text(statement, 6), let state = ModelRunValidationState(rawValue: stateRaw),
              let startedRaw = text(statement, 8), let started = formatter.date(from: startedRaw)
        else { return nil }
        return ModelRun(
            id: id, provider: provider, model: model,
            schemaVersion: Int(sqlite3_column_int(statement, 3)), promptVersion: Int(sqlite3_column_int(statement, 4)),
            normalizedInputHash: hash, validationState: state, redactedDiagnostic: text(statement, 7),
            startedAtUTC: started, finishedAtUTC: text(statement, 9).flatMap(formatter.date(from:)),
            durationMilliseconds: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 10))
        )
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }
    private func bindOptional(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        if let value { bind(value, statement, index) } else { sqlite3_bind_null(statement, index) }
    }
    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}

public enum ModelRunStoreError: Error { case openDatabase, read, write }

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
