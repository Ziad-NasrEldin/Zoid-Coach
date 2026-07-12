import Foundation
import SQLite3
import ZoidCoachCore

private let coverageSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class DailySourceCoverageStore: @unchecked Sendable {
    private struct Observation {
        let epoch: Int64
        let classification: BehaviorClassification
    }

    private struct Segment {
        let start: Date
        let end: Date
        let classification: BehaviorClassification
    }

    private struct Interval {
        let start: Date
        let end: Date
    }

    private let database: OpaquePointer
    private let now: @Sendable () -> Date
    private let timestampFormatter = ISO8601DateFormatter()
    private let lock = NSLock()

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw DailySourceCoverageStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.now = now
    }

    deinit { sqlite3_close(database) }

    public func load(
        day: Date,
        calendar suppliedCalendar: Calendar = .current
    ) throws -> DailySourceCoverage {
        lock.lock()
        defer { lock.unlock() }
        let calendar = suppliedCalendar
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw DailySourceCoverageStoreError.invalidDay
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let localDay = dayFormatter.string(from: dayStart)

        let observations = try readObservations(localDay: localDay)
        let segments = Self.segments(
            observations: observations,
            dayStart: dayStart,
            dayEnd: min(dayEnd, now())
        )
        let taskIntervals = Self.merge(
            try readTaskIntervals(dayStart: dayStart, dayEnd: dayEnd)
        )
        let activeSeconds = Self.totalSeconds(taskIntervals)
        let observedTaskSeconds = Self.overlapSeconds(
            segments.map { Interval(start: $0.start, end: $0.end) },
            with: taskIntervals
        )
        let alignedSeconds = Self.overlapSeconds(
            segments.filter { $0.classification == .work }.map { Interval(start: $0.start, end: $0.end) },
            with: taskIntervals
        )
        let categorySeconds = Dictionary(grouping: segments, by: \.classification)
            .mapValues { values in values.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } }
        let minutes: (TimeInterval) -> Int = { max(0, Int(($0 / 60).rounded())) }
        let source = try readLatestScreenwatchSource(before: dayEnd)

        return DailySourceCoverage(
            localDay: localDay,
            activeTaskMinutes: minutes(activeSeconds),
            observedTaskMinutes: minutes(observedTaskSeconds),
            alignedTaskMinutes: minutes(alignedSeconds),
            missingTaskMinutes: minutes(max(0, activeSeconds - observedTaskSeconds)),
            workMinutes: minutes(categorySeconds[.work, default: 0]),
            gamingMinutes: minutes(categorySeconds[.gaming, default: 0]),
            distractingMinutes: minutes(categorySeconds[.distracting, default: 0]),
            idleMinutes: minutes(categorySeconds[.idle, default: 0]),
            unknownMinutes: minutes(categorySeconds[.unknown, default: 0]),
            source: source
        )
    }

    private func readObservations(localDay: String) throws -> [Observation] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT behavior.epoch,
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
            WHERE behavior.source_day = ?
            ORDER BY behavior.epoch;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var observations: [Observation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = text(statement, 1),
                  let classification = BehaviorClassification(rawValue: raw)
            else { continue }
            observations.append(Observation(
                epoch: sqlite3_column_int64(statement, 0),
                classification: classification
            ))
        }
        return observations
    }

    private func readTaskIntervals(dayStart: Date, dayEnd: Date) throws -> [Interval] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT started_at, ended_at
            FROM task_activity_intervals
            WHERE started_at < ?
              AND (ended_at IS NULL OR ended_at > ?)
            ORDER BY started_at;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(timestampFormatter.string(from: dayEnd), statement, 1)
        bind(timestampFormatter.string(from: dayStart), statement, 2)
        var intervals: [Interval] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let startText = text(statement, 0),
                  let rawStart = timestampFormatter.date(from: startText)
            else { continue }
            let rawEnd = text(statement, 1).flatMap(timestampFormatter.date(from:)) ?? min(now(), dayEnd)
            let start = max(rawStart, dayStart)
            let end = min(rawEnd, dayEnd)
            if end > start { intervals.append(Interval(start: start, end: end)) }
        }
        return intervals
    }

    private func readLatestScreenwatchSource(before dayEnd: Date) throws -> DailyCoverageSourceState? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT state, detail, evidence, checked_at
            FROM source_checkpoints
            WHERE source_id LIKE 'screenwatch%'
              AND checked_at < ?
            ORDER BY checked_at DESC, id DESC
            LIMIT 1;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(timestampFormatter.string(from: dayEnd), statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let state = text(statement, 0),
              let detail = text(statement, 1),
              let evidence = text(statement, 2)
        else { return nil }
        return DailyCoverageSourceState(
            state: state,
            detail: detail,
            evidence: evidence,
            checkedAt: text(statement, 3).flatMap(timestampFormatter.date(from:))
        )
    }

    private static func segments(
        observations: [Observation],
        dayStart: Date,
        dayEnd: Date
    ) -> [Segment] {
        guard dayEnd > dayStart else { return [] }
        return observations.enumerated().compactMap { index, observation in
            let rawStart = Date(timeIntervalSince1970: TimeInterval(observation.epoch))
            let nextEpoch = index + 1 < observations.count
                ? observations[index + 1].epoch
                : observation.epoch + 60
            let cappedEnd = Date(timeIntervalSince1970: TimeInterval(min(nextEpoch, observation.epoch + 120)))
            let start = max(dayStart, rawStart)
            let end = min(dayEnd, cappedEnd)
            guard end > start else { return nil }
            return Segment(start: start, end: end, classification: observation.classification)
        }
    }

    private static func merge(_ intervals: [Interval]) -> [Interval] {
        var merged: [Interval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = Interval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func totalSeconds(_ intervals: [Interval]) -> TimeInterval {
        merge(intervals).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private static func overlapSeconds(_ lhs: [Interval], with rhs: [Interval]) -> TimeInterval {
        let left = merge(lhs)
        let right = merge(rhs)
        var total: TimeInterval = 0
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count && rightIndex < right.count {
            let start = max(left[leftIndex].start, right[rightIndex].start)
            let end = min(left[leftIndex].end, right[rightIndex].end)
            if end > start { total += end.timeIntervalSince(start) }
            if left[leftIndex].end <= right[rightIndex].end {
                leftIndex += 1
            } else {
                rightIndex += 1
            }
        }
        return total
    }

    private enum Operation: String, Sendable { case read }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, coverageSQLiteTransient) }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func databaseError(_ operation: Operation) -> DailySourceCoverageStoreError {
        .database(operation.rawValue, String(cString: sqlite3_errmsg(database)))
    }
}

public enum DailySourceCoverageStoreError: LocalizedError, Sendable {
    case openDatabase
    case invalidDay
    case database(String, String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            "The local coverage record is not available yet."
        case .invalidDay:
            "The selected review day could not be resolved in the configured time zone."
        case let .database(operation, detail):
            "The coverage review could not \(operation) local evidence. \(detail)"
        }
    }
}
