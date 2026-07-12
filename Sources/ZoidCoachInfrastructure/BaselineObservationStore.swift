import Foundation
import SQLite3
import ZoidCoachCore

private let baselineSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class BaselineObservationStore: @unchecked Sendable {
    private struct Observation {
        let localDay: String
        let epoch: Int64
        let classification: BehaviorClassification
    }

    private struct PlannedTaskCompletion {
        let completedAt: Date?
    }

    private let database: OpaquePointer
    private let now: @Sendable () -> Date
    private let requiredCompleteDays: Int
    private let lock = NSLock()
    private let timestampFormatter = ISO8601DateFormatter()

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        requiredCompleteDays: Int = 7,
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
            throw BaselineObservationStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.requiredCompleteDays = max(1, requiredCompleteDays)
        self.now = now
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    public func record(_ day: BaselineObservationDay) throws -> BaselineObservationStatus {
        guard Self.isValidDay(day.localDay) else {
            throw BaselineObservationStoreError.invalidLocalDay
        }
        lock.lock()
        defer { lock.unlock() }
        let current = try readStatus()
        guard !current.isComplete else { return current }
        try execute(
            """
            INSERT INTO baseline_observation_days(
                local_day, observed_minutes, work_minutes, gaming_minutes,
                distracting_minutes, unknown_minutes, eligible_drift_count,
                coverage, recorded_at_utc
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(local_day) DO UPDATE SET
                observed_minutes = excluded.observed_minutes,
                work_minutes = excluded.work_minutes,
                gaming_minutes = excluded.gaming_minutes,
                distracting_minutes = excluded.distracting_minutes,
                unknown_minutes = excluded.unknown_minutes,
                eligible_drift_count = excluded.eligible_drift_count,
                coverage = excluded.coverage,
                recorded_at_utc = excluded.recorded_at_utc
            WHERE baseline_observation_days.coverage != 'complete'
               OR excluded.coverage = 'complete';
            """,
            bindings: [
                .text(day.localDay),
                .integer(Int64(day.observedMinutes)),
                .integer(Int64(day.workMinutes)),
                .integer(Int64(day.gamingMinutes)),
                .integer(Int64(day.distractingMinutes)),
                .integer(Int64(day.unknownMinutes)),
                .integer(Int64(day.eligibleDriftCount)),
                .text(day.coverage.rawValue),
                .text(timestampFormatter.string(from: day.recordedAt))
            ]
        )
        return try readStatus()
    }

    /// Finalizes only days earlier than `today`; the current partial day can never advance the gate.
    /// Missing calendar days after observation begins remain visible but do not count toward seven complete days.
    @discardableResult
    public func reconcileCompletedDays(
        before today: Date,
        calendar suppliedCalendar: Calendar = .current
    ) throws -> BaselineObservationStatus {
        let calendar = suppliedCalendar
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let todayKey = dayFormatter.string(from: today)

        lock.lock()
        defer { lock.unlock() }
        let current = try readStatus()
        guard !current.isComplete else { return current }
        let observations = try readObservations(before: todayKey)
        guard let firstKey = observations.first?.localDay,
              let firstDate = dayFormatter.date(from: firstKey),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
        else { return try readStatus() }

        let grouped = Dictionary(grouping: observations, by: \.localDay)
        let plannedCompletions = try readPlannedCompletions(before: todayKey)
        var cursor = calendar.startOfDay(for: firstDate)
        while cursor <= yesterday {
            let localDay = dayFormatter.string(from: cursor)
            let day = Self.summarize(
                localDay: localDay,
                observations: grouped[localDay] ?? [],
                plannedCompletions: plannedCompletions[localDay] ?? [],
                recordedAt: now()
            )
            try write(day)
            if try readStatus().isComplete { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return try readStatus()
    }

    public func status() throws -> BaselineObservationStatus {
        lock.lock()
        defer { lock.unlock() }
        return try readStatus()
    }

    private func readStatus() throws -> BaselineObservationStatus {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT local_day, observed_minutes, work_minutes, gaming_minutes,
                   distracting_minutes, unknown_minutes, eligible_drift_count,
                   coverage, recorded_at_utc
            FROM baseline_observation_days
            ORDER BY local_day;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        var days: [BaselineObservationDay] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let localDay = text(statement, 0),
                  let rawCoverage = text(statement, 7),
                  let coverage = BaselineDayCoverage(rawValue: rawCoverage),
                  let recordedAt = text(statement, 8).flatMap(timestampFormatter.date(from:))
            else { throw BaselineObservationStoreError.invalidStoredDay }
            days.append(BaselineObservationDay(
                localDay: localDay,
                observedMinutes: Int(sqlite3_column_int64(statement, 1)),
                workMinutes: Int(sqlite3_column_int64(statement, 2)),
                gamingMinutes: Int(sqlite3_column_int64(statement, 3)),
                distractingMinutes: Int(sqlite3_column_int64(statement, 4)),
                unknownMinutes: Int(sqlite3_column_int64(statement, 5)),
                eligibleDriftCount: Int(sqlite3_column_int64(statement, 6)),
                coverage: coverage,
                recordedAt: recordedAt
            ))
        }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw databaseError(.read)
        }
        return BaselineObservationStatus(
            requiredCompleteDays: requiredCompleteDays,
            days: days,
            report: Self.report(for: days)
        )
    }

    private func readObservations(before localDay: String) throws -> [Observation] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT behavior.source_day, behavior.epoch,
                   COALESCE(
                       (
                           SELECT correction.classification
                           FROM daily_review_corrections correction
                           WHERE correction.source_day = behavior.source_day
                             AND behavior.epoch >= correction.start_epoch
                             AND behavior.epoch < correction.end_epoch
                           ORDER BY correction.created_at_utc DESC, correction.rowid DESC
                           LIMIT 1
                       ),
                       behavior.classification
                   )
            FROM behavior_records behavior
            WHERE behavior.source_day < ?
            ORDER BY behavior.source_day, behavior.epoch;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var observations: [Observation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let day = text(statement, 0),
                  let rawClassification = text(statement, 2),
                  let classification = BehaviorClassification(rawValue: rawClassification)
            else { continue }
            observations.append(Observation(
                localDay: day,
                epoch: sqlite3_column_int64(statement, 1),
                classification: classification
            ))
        }
        return observations
    }

    private func readPlannedCompletions(before localDay: String) throws -> [String: [PlannedTaskCompletion]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT plan.day_key, MIN(history.occurred_at)
            FROM daily_plan_entries plan
            LEFT JOIN task_history history
              ON history.task_id = plan.reminder_id
             AND history.state = 'completed'
            WHERE plan.day_key < ?
            GROUP BY plan.day_key, plan.reminder_id;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw databaseError(.read)
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var days: [String: [PlannedTaskCompletion]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let day = text(statement, 0) else { continue }
            let completedAt = text(statement, 1).flatMap(timestampFormatter.date(from:))
            days[day, default: []].append(PlannedTaskCompletion(completedAt: completedAt))
        }
        return days
    }

    private func write(_ day: BaselineObservationDay) throws {
        try execute(
            """
            INSERT INTO baseline_observation_days(
                local_day, observed_minutes, work_minutes, gaming_minutes,
                distracting_minutes, unknown_minutes, eligible_drift_count,
                coverage, recorded_at_utc
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(local_day) DO UPDATE SET
                observed_minutes = excluded.observed_minutes,
                work_minutes = excluded.work_minutes,
                gaming_minutes = excluded.gaming_minutes,
                distracting_minutes = excluded.distracting_minutes,
                unknown_minutes = excluded.unknown_minutes,
                eligible_drift_count = excluded.eligible_drift_count,
                coverage = excluded.coverage,
                recorded_at_utc = excluded.recorded_at_utc
            WHERE baseline_observation_days.coverage != 'complete'
               OR excluded.coverage = 'complete';
            """,
            bindings: [
                .text(day.localDay), .integer(Int64(day.observedMinutes)),
                .integer(Int64(day.workMinutes)), .integer(Int64(day.gamingMinutes)),
                .integer(Int64(day.distractingMinutes)), .integer(Int64(day.unknownMinutes)),
                .integer(Int64(day.eligibleDriftCount)), .text(day.coverage.rawValue),
                .text(timestampFormatter.string(from: day.recordedAt))
            ]
        )
    }

    private static func summarize(
        localDay: String,
        observations: [Observation],
        plannedCompletions: [PlannedTaskCompletion],
        recordedAt: Date
    ) -> BaselineObservationDay {
        guard !observations.isEmpty else {
            return BaselineObservationDay(
                localDay: localDay, observedMinutes: 0, workMinutes: 0,
                gamingMinutes: 0, distractingMinutes: 0, unknownMinutes: 0,
                eligibleDriftCount: 0, coverage: .missing, recordedAt: recordedAt
            )
        }
        var seconds: [BehaviorClassification: Int] = [:]
        var eligibleDriftCount = 0
        var currentDriftSeconds = 0
        var currentDriftLastEpoch: Int64?
        var previousEpoch: Int64?
        for (index, observation) in observations.enumerated() {
            let nextEpoch = index + 1 < observations.count ? observations[index + 1].epoch : observation.epoch + 60
            let duration = max(1, min(120, Int(nextEpoch - observation.epoch)))
            seconds[observation.classification, default: 0] += duration
            let isDrift = observation.classification == .gaming || observation.classification == .distracting
            let continuesEpisode = previousEpoch.map { observation.epoch - $0 <= 180 } ?? true
            if isDrift {
                if !continuesEpisode {
                    if currentDriftSeconds >= 600,
                       let currentDriftLastEpoch,
                       hasIncompletePlannedWork(at: currentDriftLastEpoch, completions: plannedCompletions) {
                        eligibleDriftCount += 1
                    }
                    currentDriftSeconds = 0
                }
                currentDriftSeconds += duration
                currentDriftLastEpoch = observation.epoch
            } else {
                if currentDriftSeconds >= 600,
                   let currentDriftLastEpoch,
                   hasIncompletePlannedWork(at: currentDriftLastEpoch, completions: plannedCompletions) {
                    eligibleDriftCount += 1
                }
                currentDriftSeconds = 0
                currentDriftLastEpoch = nil
            }
            previousEpoch = observation.epoch
        }
        if currentDriftSeconds >= 600,
           let currentDriftLastEpoch,
           hasIncompletePlannedWork(at: currentDriftLastEpoch, completions: plannedCompletions) {
            eligibleDriftCount += 1
        }
        let minutes: (BehaviorClassification) -> Int = { classification in
            Int((Double(seconds[classification, default: 0]) / 60).rounded())
        }
        let observedMinutes = Int((Double(seconds.values.reduce(0, +)) / 60).rounded())
        return BaselineObservationDay(
            localDay: localDay,
            observedMinutes: observedMinutes,
            workMinutes: minutes(.work),
            gamingMinutes: minutes(.gaming),
            distractingMinutes: minutes(.distracting),
            unknownMinutes: minutes(.unknown) + minutes(.idle),
            eligibleDriftCount: eligibleDriftCount,
            coverage: observedMinutes >= 30 ? .complete : .limited,
            recordedAt: recordedAt
        )
    }

    private static func hasIncompletePlannedWork(
        at epoch: Int64,
        completions: [PlannedTaskCompletion]
    ) -> Bool {
        let observedAt = Date(timeIntervalSince1970: TimeInterval(epoch))
        return completions.contains { completion in
            completion.completedAt.map { $0 > observedAt } ?? true
        }
    }

    private static func report(for days: [BaselineObservationDay]) -> BaselineObservationReport {
        let complete = days.filter(\.countsTowardBaseline)
        let workTotal = complete.reduce(0) { $0 + $1.workMinutes }
        let gamingTotal = complete.reduce(0) { $0 + $1.gamingMinutes }
        let observedTotal = complete.reduce(0) { $0 + $1.observedMinutes }
        let unknownTotal = complete.reduce(0) { $0 + $1.unknownMinutes }
        return BaselineObservationReport(
            averageObservedWorkMinutes: complete.isEmpty ? 0 : workTotal / complete.count,
            gamingDayCount: complete.filter { $0.gamingMinutes > 0 }.count,
            totalGamingMinutes: gamingTotal,
            eligibleDriftCount: complete.reduce(0) { $0 + $1.eligibleDriftCount },
            unknownSharePercent: observedTotal == 0 ? 0 : Int((Double(unknownTotal) / Double(observedTotal) * 100).rounded())
        )
    }

    private static func isValidDay(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private enum Binding { case text(String), integer(Int64) }

    private func execute(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.write) }
        defer { sqlite3_finalize(statement) }
        for (offset, binding) in bindings.enumerated() {
            switch binding {
            case let .text(value): bind(value, statement, Int32(offset + 1))
            case let .integer(value): sqlite3_bind_int64(statement, Int32(offset + 1), value)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, baselineSQLiteTransient) }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func databaseError(_ operation: BaselineObservationStoreError.Operation) -> BaselineObservationStoreError {
        .database(operation, String(cString: sqlite3_errmsg(database)))
    }
}

public enum BaselineObservationStoreError: LocalizedError, Sendable {
    public enum Operation: String, Sendable { case read, write }
    case openDatabase
    case invalidLocalDay
    case invalidStoredDay
    case database(Operation, String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "The local baseline record could not be opened."
        case .invalidLocalDay: "The baseline day must use a valid YYYY-MM-DD local date."
        case .invalidStoredDay: "A stored baseline day is unreadable. The original behavior record remains unchanged."
        case let .database(operation, detail): "The baseline could not \(operation.rawValue) local data. \(detail)"
        }
    }
}
