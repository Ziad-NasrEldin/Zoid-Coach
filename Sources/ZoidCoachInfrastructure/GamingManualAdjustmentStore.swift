import Foundation
import SQLite3
import ZoidCoachCore

public final class GamingManualAdjustmentStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let formatter = ISO8601DateFormatter()
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        databaseURL: URL,
        readOnly: Bool = false,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.now = now
        if !readOnly {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate()
        }
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            throw GamingManualAdjustmentStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit {
        sqlite3_close(database)
    }

    public func record(
        _ request: GamingManualAdjustmentRequest
    ) throws -> GamingManualAdjustmentReceipt {
        lock.lock()
        defer { lock.unlock() }
        let normalized = try normalizedRequest(request)
        let localDay = dayKey(
            request.day,
            timeZoneIdentifier: request.timeZoneIdentifier
        )
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            throw GamingManualAdjustmentStoreError.write
        }
        var committed = false
        defer {
            if !committed {
                sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            }
        }

        if let existing = try adjustment(id: normalized.requestID) {
            guard existing.localDay == localDay,
                  existing.minutes == normalized.minutes,
                  existing.note == normalized.note else {
                throw GamingManualAdjustmentStoreError.idempotencyConflict
            }
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw GamingManualAdjustmentStoreError.write
            }
            committed = true
            return GamingManualAdjustmentReceipt(adjustment: existing, replayed: true)
        }

        let existingNet = try netMinutes(localDay: localDay)
        let resultingNet = existingNet + normalized.minutes
        guard resultingNet >= 0 else {
            throw GamingManualAdjustmentStoreError.removalExceedsManualGrant
        }
        guard resultingNet <= 1_440 else {
            throw GamingManualAdjustmentStoreError.dailyLimitExceeded
        }

        let recordedAt = formatter.date(from: formatter.string(from: now())) ?? now()
        let adjustment = GamingManualAdjustment(
            id: normalized.requestID,
            localDay: localDay,
            minutes: normalized.minutes,
            note: normalized.note,
            recordedAt: recordedAt
        )
        try insert(adjustment)
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw GamingManualAdjustmentStoreError.write
        }
        committed = true
        return GamingManualAdjustmentReceipt(adjustment: adjustment, replayed: false)
    }

    public func adjustments(
        for day: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> [GamingManualAdjustment] {
        lock.lock()
        defer { lock.unlock() }
        return try adjustments(localDay: dayKey(day, timeZoneIdentifier: timeZoneIdentifier))
    }

    public func netMinutes(
        for day: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return try netMinutes(localDay: dayKey(day, timeZoneIdentifier: timeZoneIdentifier))
    }

    public func gamingStatus(
        applyingAdjustmentsFor day: Date,
        timeZoneIdentifier: String,
        to status: GamingStatus
    ) throws -> GamingStatus {
        lock.lock()
        defer { lock.unlock() }
        return status.applyingManualAdjustment(
            try netMinutes(localDay: dayKey(day, timeZoneIdentifier: timeZoneIdentifier))
        )
    }

    private func normalizedRequest(
        _ request: GamingManualAdjustmentRequest
    ) throws -> GamingManualAdjustmentRequest {
        let requestID = request.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = request.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requestID.hasPrefix("gaming-adjustment-v1:"),
              requestID.count <= 160,
              request.minutes != 0,
              (-240...240).contains(request.minutes),
              TimeZone(identifier: request.timeZoneIdentifier) != nil,
              (note?.count ?? 0) <= 160 else {
            throw GamingManualAdjustmentStoreError.invalidRequest
        }
        return GamingManualAdjustmentRequest(
            requestID: requestID,
            day: request.day,
            timeZoneIdentifier: request.timeZoneIdentifier,
            minutes: request.minutes,
            note: note?.isEmpty == true ? nil : note
        )
    }

    private func insert(_ adjustment: GamingManualAdjustment) throws {
        let sql = "INSERT INTO gaming_manual_adjustments(request_id, local_day, minutes, note, recorded_at_utc) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw GamingManualAdjustmentStoreError.write
        }
        defer { sqlite3_finalize(statement) }
        bind(adjustment.id, statement, 1)
        bind(adjustment.localDay, statement, 2)
        sqlite3_bind_int(statement, 3, Int32(adjustment.minutes))
        if let note = adjustment.note {
            bind(note, statement, 4)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        bind(formatter.string(from: adjustment.recordedAt), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw GamingManualAdjustmentStoreError.write
        }
    }

    private func adjustment(id: String) throws -> GamingManualAdjustment? {
        let sql = "SELECT local_day, minutes, note, recorded_at_utc FROM gaming_manual_adjustments WHERE request_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw GamingManualAdjustmentStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(id, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodedAdjustment(statement, id: id)
    }

    private func adjustments(localDay: String) throws -> [GamingManualAdjustment] {
        let sql = "SELECT request_id, minutes, note, recorded_at_utc FROM gaming_manual_adjustments WHERE local_day = ? ORDER BY recorded_at_utc, rowid;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw GamingManualAdjustmentStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var result: [GamingManualAdjustment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let recordedPointer = sqlite3_column_text(statement, 3),
                  let recordedAt = formatter.date(from: String(cString: recordedPointer)) else {
                throw GamingManualAdjustmentStoreError.read
            }
            let note = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            result.append(GamingManualAdjustment(
                id: String(cString: idPointer),
                localDay: localDay,
                minutes: Int(sqlite3_column_int(statement, 1)),
                note: note,
                recordedAt: recordedAt
            ))
        }
        return result
    }

    private func netMinutes(localDay: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT COALESCE(SUM(minutes), 0) FROM gaming_manual_adjustments WHERE local_day = ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw GamingManualAdjustmentStoreError.read
        }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw GamingManualAdjustmentStoreError.read
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func decodedAdjustment(
        _ statement: OpaquePointer,
        id: String
    ) throws -> GamingManualAdjustment {
        guard let dayPointer = sqlite3_column_text(statement, 0),
              let recordedPointer = sqlite3_column_text(statement, 3),
              let recordedAt = formatter.date(from: String(cString: recordedPointer)) else {
            throw GamingManualAdjustmentStoreError.read
        }
        return GamingManualAdjustment(
            id: id,
            localDay: String(cString: dayPointer),
            minutes: Int(sqlite3_column_int(statement, 1)),
            note: sqlite3_column_text(statement, 2).map { String(cString: $0) },
            recordedAt: recordedAt
        )
    }

    private func dayKey(_ date: Date, timeZoneIdentifier: String) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.string(from: date)
    }

    private func bind(
        _ value: String,
        _ statement: OpaquePointer,
        _ index: Int32
    ) {
        _ = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT)
        }
    }
}

public enum GamingManualAdjustmentStoreError: LocalizedError, Equatable {
    case openDatabase
    case invalidRequest
    case idempotencyConflict
    case removalExceedsManualGrant
    case dailyLimitExceeded
    case read
    case write

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            "The local gaming allowance ledger could not be opened."
        case .invalidRequest:
            "Choose between 1 and 240 minutes."
        case .idempotencyConflict:
            "That gaming-time adjustment was already used for a different change."
        case .removalExceedsManualGrant:
            "You cannot remove more time than was manually granted today."
        case .dailyLimitExceeded:
            "Manual gaming time cannot exceed 1,440 minutes in one day."
        case .read:
            "The current manual gaming allowance could not be read."
        case .write:
            "The manual gaming allowance could not be saved."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
