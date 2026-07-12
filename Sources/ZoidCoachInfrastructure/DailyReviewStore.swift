import Foundation
import SQLite3
import ZoidCoachCore

public final class DailyReviewStore: @unchecked Sendable {
    private struct Correction {
        let startEpoch: Int64
        let endEpoch: Int64
        let classification: BehaviorClassification
        let taskID: String?
    }

    private let database: OpaquePointer
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw DailyReviewStoreError.openDatabase
        }
        database = handle
        self.now = now
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func load(sourceDay: String) throws -> DailyReviewSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let corrections = try readCorrections(sourceDay: sourceDay)
        let observations = try readObservations(sourceDay: sourceDay, corrections: corrections)
        let sessions = DailyReviewSessionizer.sessions(from: observations)
        let totals = DailyReviewSessionizer.totals(for: sessions)
        let state = try readReviewState(sourceDay: sourceDay)
        return DailyReviewSnapshot(
            sourceDay: sourceDay,
            sessions: sessions,
            totals: totals,
            hypothesis: Self.hypothesis(for: totals),
            hypothesisState: state.hypothesisState,
            confirmedAt: state.confirmedAt
        )
    }

    public func correct(
        _ session: DailyReviewSession,
        to classification: BehaviorClassification,
        taskID: String? = nil,
        from splitDate: Date? = nil
    ) throws {
        let start = max(session.start, splitDate ?? session.start)
        guard start < session.end else { throw DailyReviewStoreError.invalidCorrectionRange }
        let normalizedTaskID = taskID?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try execute(
                "INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?);",
                bindings: [
                    .text(UUID().uuidString),
                    .text(session.sourceDay),
                    .integer(Int64(start.timeIntervalSince1970)),
                    .integer(Int64(session.end.timeIntervalSince1970)),
                    .text(classification.rawValue),
                    normalizedTaskID.flatMap { $0.isEmpty ? nil : .text($0) } ?? .null,
                    .text(Self.timestamp(now()))
                ]
            )
            try execute(
                "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, 'pending', NULL, ?) ON CONFLICT(source_day) DO UPDATE SET hypothesis_state = 'pending', confirmed_at_utc = NULL, updated_at_utc = excluded.updated_at_utc;",
                bindings: [.text(session.sourceDay), .text(Self.timestamp(now()))]
            )
        }
    }

    public func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, ?, NULL, ?) ON CONFLICT(source_day) DO UPDATE SET hypothesis_state = excluded.hypothesis_state, confirmed_at_utc = NULL, updated_at_utc = excluded.updated_at_utc;",
            bindings: [.text(sourceDay), .text(state.rawValue), .text(Self.timestamp(now()))]
        )
    }

    public func confirm(sourceDay: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = Self.timestamp(now())
        try execute(
            "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, 'pending', ?, ?) ON CONFLICT(source_day) DO UPDATE SET confirmed_at_utc = excluded.confirmed_at_utc, updated_at_utc = excluded.updated_at_utc;",
            bindings: [.text(sourceDay), .text(timestamp), .text(timestamp)]
        )
    }

    private func readObservations(
        sourceDay: String,
        corrections: [Correction]
    ) throws -> [DailyReviewSessionizer.Observation] {
        var statement: OpaquePointer?
        let sql = "SELECT epoch, app_name, classification FROM behavior_records WHERE source_day = ? ORDER BY epoch ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var result: [DailyReviewSessionizer.Observation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let epoch = sqlite3_column_int64(statement, 0)
            guard let appPointer = sqlite3_column_text(statement, 1) else { continue }
            let stored = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let correction = corrections.last { epoch >= $0.startEpoch && epoch < $0.endEpoch }
            let classification = correction?.classification
                ?? stored.flatMap(BehaviorClassification.init(rawValue:))
                ?? .unknown
            result.append(.init(
                sourceDay: sourceDay,
                observedAt: Date(timeIntervalSince1970: TimeInterval(epoch)),
                application: String(cString: appPointer),
                classification: classification,
                taskID: correction?.taskID
            ))
        }
        if sqlite3_errcode(database) != SQLITE_OK && sqlite3_errcode(database) != SQLITE_DONE {
            throw databaseError(.read)
        }
        return result
    }

    private func readCorrections(sourceDay: String) throws -> [Correction] {
        var statement: OpaquePointer?
        let sql = "SELECT start_epoch, end_epoch, classification, task_id FROM daily_review_corrections WHERE source_day = ? ORDER BY created_at_utc ASC, rowid ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var result: [Correction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawPointer = sqlite3_column_text(statement, 2),
                  let classification = BehaviorClassification(rawValue: String(cString: rawPointer)) else { continue }
            result.append(Correction(
                startEpoch: sqlite3_column_int64(statement, 0),
                endEpoch: sqlite3_column_int64(statement, 1),
                classification: classification,
                taskID: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            ))
        }
        return result
    }

    private func readReviewState(sourceDay: String) throws -> (
        hypothesisState: DailyReviewHypothesisState,
        confirmedAt: Date?
    ) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT hypothesis_state, confirmed_at_utc FROM daily_reviews WHERE source_day = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return (.pending, nil) }
        let rawState = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "pending"
        let confirmed = sqlite3_column_text(statement, 1)
            .map { String(cString: $0) }
            .flatMap(ISO8601DateFormatter().date(from:))
        return (DailyReviewHypothesisState(rawValue: rawState) ?? .pending, confirmed)
    }

    private static func hypothesis(for totals: [DailyReviewTotal]) -> String? {
        guard !totals.isEmpty else { return nil }
        let work = totals.first { $0.classification == .work }?.minutes ?? 0
        let drift = totals
            .filter { $0.classification == .gaming || $0.classification == .distracting }
            .reduce(0) { $0 + $1.minutes }
        if drift > work {
            return "Observed gaming and distracting time exceeded observed work time. This may indicate that the planned work was difficult to start."
        }
        return "Observed work time was the largest covered category. This may indicate that today’s plan matched the available capacity."
    }

    private enum Binding {
        case text(String)
        case integer(Int64)
        case null
    }

    private func execute(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.write) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            switch value {
            case let .text(text): bind(text, statement, Int32(offset + 1))
            case let .integer(integer): sqlite3_bind_int64(statement, Int32(offset + 1), integer)
            case .null: sqlite3_bind_null(statement, Int32(offset + 1))
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(.write)
        }
        do {
            try operation()
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw databaseError(.write)
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func databaseError(_ operation: DailyReviewStoreError.Operation) -> DailyReviewStoreError {
        DailyReviewStoreError.database(operation, String(cString: sqlite3_errmsg(database)))
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

public enum DailyReviewStoreError: LocalizedError {
    public enum Operation: String, Sendable { case read, write }
    case openDatabase
    case invalidCorrectionRange
    case database(Operation, String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            "The local review database could not be opened."
        case .invalidCorrectionRange:
            "The selected split point does not leave any activity to correct."
        case let .database(operation, detail):
            "The daily review could not \(operation.rawValue) local data. \(detail)"
        }
    }
}

private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
}
