import Foundation
import SQLite3
import ZoidCoachCore
import ZoidCoachInfrastructure

struct AIBudgetStatus: Equatable, Sendable {
    let dailyUsed: Int
    let monthlyUsed: Int
    let dailyLimit: Int
    let monthlyLimit: Int
    let nextDailyReset: Date
    let nextMonthlyReset: Date

    var isDisabled: Bool {
        dailyLimit == 0 || monthlyLimit == 0
    }

    var isExhausted: Bool {
        !isDisabled && (dailyUsed >= dailyLimit || monthlyUsed >= monthlyLimit)
    }

    var scopeMessage: String {
        "One shared budget covers all providers and models. Switching provider or model does not reset or bypass it."
    }

    var fallbackMessage: String {
        if isDisabled {
            return "General AI is disabled. Local planning, tracking, coaching rules, and reviews continue, and no paid request is sent."
        }
        if isExhausted {
            return "The saved request budget is exhausted, so local planning, tracking, coaching rules, and reviews continue and no paid request is sent."
        }
        return "General AI requests remain available within the saved limits."
    }
}

struct AIBudgetStatusService {
    private let databaseURL: URL
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(databaseURL: URL = RuntimeEnvironment.current().databaseURL) {
        self.databaseURL = databaseURL
    }

    func load(now: Date = Date()) throws -> AIBudgetStatus {
        let policy = try PolicyStore(databaseURL: databaseURL, readOnly: true).current()?.policy
            ?? UserPolicy.defaults()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(for: now)
        guard let nextDailyReset = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw AIBudgetStatusServiceError.invalidResetBoundary
        }
        let monthComponents = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: monthComponents),
              let nextMonthlyReset = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            throw AIBudgetStatusServiceError.invalidResetBoundary
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw AIBudgetStatusServiceError.openDatabase
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)

        return AIBudgetStatus(
            dailyUsed: try requestCount(in: startOfDay..<nextDailyReset, database: database),
            monthlyUsed: try requestCount(in: startOfMonth..<nextMonthlyReset, database: database),
            dailyLimit: policy.privacy.effectiveAIDailyRequestBudget,
            monthlyLimit: policy.privacy.effectiveAIMonthlyRequestBudget,
            nextDailyReset: nextDailyReset,
            nextMonthlyReset: nextMonthlyReset
        )
    }

    private func requestCount(in range: Range<Date>, database: OpaquePointer) throws -> Int {
        let sql = "SELECT COUNT(*) FROM model_runs WHERE started_at_utc >= ? AND started_at_utc < ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AIBudgetStatusServiceError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: range.lowerBound), to: statement, at: 1)
        bind(formatter.string(from: range.upperBound), to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AIBudgetStatusServiceError.read
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT)
        }
    }
}

enum AIBudgetStatusServiceError: Error {
    case openDatabase
    case read
    case invalidResetBoundary
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
