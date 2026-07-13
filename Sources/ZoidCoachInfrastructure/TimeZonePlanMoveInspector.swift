import Foundation
import SQLite3
import ZoidCoachCore

public struct TimeZonePlanMoveWarning: Equatable, Sendable {
    public let sourceTimeZoneIdentifier: String
    public let destinationTimeZoneIdentifier: String
    public let sourceDayKey: String
    public let destinationDayKey: String
    public let taskCount: Int
    public let referenceDate: Date

    public init(
        sourceTimeZoneIdentifier: String,
        destinationTimeZoneIdentifier: String,
        sourceDayKey: String,
        destinationDayKey: String,
        taskCount: Int,
        referenceDate: Date
    ) {
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.destinationTimeZoneIdentifier = destinationTimeZoneIdentifier
        self.sourceDayKey = sourceDayKey
        self.destinationDayKey = destinationDayKey
        self.taskCount = taskCount
        self.referenceDate = referenceDate
    }

    public var confirmationMessage: String {
        let taskLabel = taskCount == 1 ? "1 planned task" : "\(taskCount) planned tasks"
        return "\(taskLabel) currently belong to \(sourceDayKey) in \(sourceTimeZoneIdentifier). In \(destinationTimeZoneIdentifier), this instant is \(destinationDayKey). Saving changes which local plan day Zoid 666 treats as current."
    }
}

public struct TimeZonePlanMoveInspector: Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) {
        self.databaseURL = databaseURL
    }

    public func warning(
        from sourceTimeZoneIdentifier: String,
        to destinationTimeZoneIdentifier: String,
        at date: Date = Date()
    ) throws -> TimeZonePlanMoveWarning? {
        guard sourceTimeZoneIdentifier != destinationTimeZoneIdentifier else { return nil }
        guard let sourceTimeZone = TimeZone(identifier: sourceTimeZoneIdentifier),
              let destinationTimeZone = TimeZone(identifier: destinationTimeZoneIdentifier)
        else { throw TimeZonePlanMoveInspectorError.invalidTimeZone }
        let sourceDayKey = Self.dayKey(for: date, timeZone: sourceTimeZone)
        let destinationDayKey = Self.dayKey(for: date, timeZone: destinationTimeZone)
        guard sourceDayKey != destinationDayKey else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw TimeZonePlanMoveInspectorError.openDatabase
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT COUNT(*) FROM daily_plan_entries WHERE day_key = ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw TimeZonePlanMoveInspectorError.inspectPlan
        }
        defer { sqlite3_finalize(statement) }
        _ = sourceDayKey.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TimeZonePlanMoveInspectorError.inspectPlan
        }
        let taskCount = Int(sqlite3_column_int(statement, 0))
        guard taskCount > 0 else { return nil }
        return TimeZonePlanMoveWarning(
            sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
            destinationTimeZoneIdentifier: destinationTimeZoneIdentifier,
            sourceDayKey: sourceDayKey,
            destinationDayKey: destinationDayKey,
            taskCount: taskCount,
            referenceDate: date
        )
    }

    private static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

public enum TimeZonePlanMoveInspectorError: LocalizedError, Equatable {
    case invalidTimeZone
    case openDatabase
    case inspectPlan

    public var errorDescription: String? {
        switch self {
        case .invalidTimeZone:
            "The selected policy time zone is invalid."
        case .openDatabase:
            "The current plan could not be opened for a time-zone safety check."
        case .inspectPlan:
            "The current plan could not be checked for a local-day change."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
