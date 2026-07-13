import Foundation
import SQLite3
import ZoidCoachCore

public enum NotificationDeliveryOutcome: String, Codable, CaseIterable, Sendable {
    case authorizationUnavailable = "authorization_unavailable"
    case acceptedBySystem = "accepted_by_system"
    case deliveredByFixture = "delivered_by_fixture"
    case schedulingFailed = "scheduling_failed"
}

public struct NotificationDeliveryRecord: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let requestIdentifier: String
    public let promptID: String
    public let category: String
    public let outcome: NotificationDeliveryOutcome
    public let scheduledFor: Date?
    public let recordedAt: Date
    public let attempt: Int
    public let replacedPriorRequest: Bool
    public let redactedError: String?

    public init(
        id: Int64,
        requestIdentifier: String,
        promptID: String,
        category: String,
        outcome: NotificationDeliveryOutcome,
        scheduledFor: Date?,
        recordedAt: Date,
        attempt: Int,
        replacedPriorRequest: Bool,
        redactedError: String?
    ) {
        self.id = id
        self.requestIdentifier = requestIdentifier
        self.promptID = promptID
        self.category = category
        self.outcome = outcome
        self.scheduledFor = scheduledFor
        self.recordedAt = recordedAt
        self.attempt = attempt
        self.replacedPriorRequest = replacedPriorRequest
        self.redactedError = redactedError
    }
}

public final class NotificationDeliveryLedger: @unchecked Sendable {
    public static let defaultRetentionDays = 30

    private let database: OpaquePointer
    private let lock = NSRecursiveLock()
    private let formatter = ISO8601DateFormatter()
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
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw NotificationDeliveryLedgerError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.now = now
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    public func record(
        requestIdentifier: String,
        promptID: String,
        category: String,
        outcome: NotificationDeliveryOutcome,
        scheduledFor: Date? = nil,
        error: String? = nil
    ) throws -> NotificationDeliveryRecord {
        lock.lock()
        defer { lock.unlock() }

        let safeRequestID = Self.boundedIdentifier(requestIdentifier)
        let safePromptID = Self.boundedIdentifier(promptID)
        let safeCategory = Self.boundedIdentifier(category)
        guard !safeRequestID.isEmpty, !safePromptID.isEmpty, !safeCategory.isEmpty else {
            throw NotificationDeliveryLedgerError.invalidRecord
        }

        let nextAttempt = try attemptCount(requestIdentifier: safeRequestID) + 1
        let replacedPriorRequest = try hasAcceptedRequest(requestIdentifier: safeRequestID)
        let date = now()
        let sql = """
        INSERT INTO notification_delivery_events (
            request_identifier, prompt_id, category, outcome, scheduled_for,
            recorded_at, attempt, replaced_prior_request, redacted_error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql) else { throw NotificationDeliveryLedgerError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(safeRequestID, to: statement, at: 1)
        bind(safePromptID, to: statement, at: 2)
        bind(safeCategory, to: statement, at: 3)
        bind(outcome.rawValue, to: statement, at: 4)
        bind(scheduledFor.map(formatter.string(from:)), to: statement, at: 5)
        bind(formatter.string(from: date), to: statement, at: 6)
        sqlite3_bind_int(statement, 7, Int32(nextAttempt))
        sqlite3_bind_int(statement, 8, replacedPriorRequest ? 1 : 0)
        bind(Self.redacted(error), to: statement, at: 9)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NotificationDeliveryLedgerError.write(errorMessage)
        }
        return NotificationDeliveryRecord(
            id: sqlite3_last_insert_rowid(database),
            requestIdentifier: safeRequestID,
            promptID: safePromptID,
            category: safeCategory,
            outcome: outcome,
            scheduledFor: scheduledFor,
            recordedAt: date,
            attempt: nextAttempt,
            replacedPriorRequest: replacedPriorRequest,
            redactedError: Self.redacted(error)
        )
    }

    public func recent(limit: Int = 20) throws -> [NotificationDeliveryRecord] {
        lock.lock()
        defer { lock.unlock() }
        let safeLimit = min(max(limit, 1), 100)
        guard let statement = prepare("""
            SELECT id, request_identifier, prompt_id, category, outcome,
                   scheduled_for, recorded_at, attempt, replaced_prior_request, redacted_error
            FROM notification_delivery_events
            ORDER BY recorded_at DESC, id DESC
            LIMIT ?;
            """) else { throw NotificationDeliveryLedgerError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(safeLimit))
        var records: [NotificationDeliveryRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let outcomeRaw = text(statement, at: 4),
                  let outcome = NotificationDeliveryOutcome(rawValue: outcomeRaw),
                  let requestIdentifier = text(statement, at: 1),
                  let promptID = text(statement, at: 2),
                  let category = text(statement, at: 3),
                  let recordedRaw = text(statement, at: 6),
                  let recordedAt = formatter.date(from: recordedRaw)
            else { continue }
            records.append(NotificationDeliveryRecord(
                id: sqlite3_column_int64(statement, 0),
                requestIdentifier: requestIdentifier,
                promptID: promptID,
                category: category,
                outcome: outcome,
                scheduledFor: text(statement, at: 5).flatMap(formatter.date(from:)),
                recordedAt: recordedAt,
                attempt: Int(sqlite3_column_int(statement, 7)),
                replacedPriorRequest: sqlite3_column_int(statement, 8) == 1,
                redactedError: text(statement, at: 9)
            ))
        }
        return records
    }

    public func containsAcceptedDelivery(requestIdentifier: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return try hasAcceptedRequest(
            requestIdentifier: Self.boundedIdentifier(requestIdentifier)
        )
    }

    @discardableResult
    public func enforceRetention(days: Int = defaultRetentionDays) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let safeDays = min(max(days, 1), 365)
        let cutoff = now().addingTimeInterval(-TimeInterval(safeDays * 86_400))
        guard let statement = prepare("DELETE FROM notification_delivery_events WHERE recorded_at < ?;") else {
            throw NotificationDeliveryLedgerError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(formatter.string(from: cutoff), to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NotificationDeliveryLedgerError.write(errorMessage)
        }
        return Int(sqlite3_changes(database))
    }

    private func attemptCount(requestIdentifier: String) throws -> Int {
        guard let statement = prepare("SELECT COUNT(*) FROM notification_delivery_events WHERE request_identifier = ?;") else {
            throw NotificationDeliveryLedgerError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(requestIdentifier, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotificationDeliveryLedgerError.read(errorMessage)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func hasAcceptedRequest(requestIdentifier: String) throws -> Bool {
        guard let statement = prepare("""
            SELECT EXISTS(
                SELECT 1 FROM notification_delivery_events
                WHERE request_identifier = ?
                  AND outcome IN ('accepted_by_system', 'delivered_by_fixture')
            );
            """) else { throw NotificationDeliveryLedgerError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(requestIdentifier, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NotificationDeliveryLedgerError.read(errorMessage)
        }
        return sqlite3_column_int(statement, 0) == 1
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func text(_ statement: OpaquePointer?, at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private var errorMessage: String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "unknown sqlite error"
    }

    private static func boundedIdentifier(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    private static func redacted(_ error: String?) -> String? {
        guard let error else { return nil }
        let collapsed = error
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: #"(?:/[^\s]+)+"#, with: "[path]", options: .regularExpression)
            .replacingOccurrences(of: #"[\w.+-]+@[\w.-]+"#, with: "[address]", options: .regularExpression)
        return String(collapsed.prefix(240))
    }
}

public enum NotificationDeliveryLedgerError: LocalizedError, Equatable {
    case openDatabase
    case invalidRecord
    case prepare(String)
    case read(String)
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Notification delivery history could not open local storage."
        case .invalidRecord: "Notification delivery history rejected an invalid record."
        case .prepare: "Notification delivery history is unavailable."
        case .read: "Notification delivery history could not be read."
        case .write: "Notification delivery history could not be updated."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
