import Foundation
import SQLite3
import ZoidCoachCore

public struct ActionEnqueueResult: Equatable, Sendable {
    public let command: ActionCommand
    public let wasInserted: Bool

    public init(command: ActionCommand, wasInserted: Bool) {
        self.command = command
        self.wasInserted = wasInserted
    }
}

public final class ActionOutboxStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let formatter = ISO8601DateFormatter()
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String
    private let timeZone: TimeZone

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString },
        timeZone: TimeZone = .current
    ) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else { throw ActionOutboxStoreError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.now = now
        self.makeID = makeID
        self.timeZone = timeZone
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit { sqlite3_close(database) }

    public func enqueue(
        type: ActionCommandType,
        entityID: String,
        desiredState: ActionDesiredState,
        planVersion: Int
    ) throws -> ActionEnqueueResult {
        let idempotencyKey = try ActionIdempotencyKey.make(type: type, entityID: entityID, desiredState: desiredState, planVersion: planVersion)
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        if let existing = try command(idempotencyKey: idempotencyKey) {
            committed = true
            return ActionEnqueueResult(command: existing, wasInserted: false)
        }
        let date = now()
        let command = ActionCommand(
            id: makeID(),
            idempotencyKey: idempotencyKey,
            type: type,
            entityID: entityID,
            desiredState: desiredState,
            createdAt: date,
            updatedAt: date
        )
        let sql = """
        INSERT OR IGNORE INTO action_commands
        (id, idempotency_key, action_type, entity_id, desired_state_json, state, attempt_count, next_attempt_at_utc, created_at_utc, updated_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, 0, NULL, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(command.id, statement, 1)
        bind(command.idempotencyKey, statement, 2)
        bind(type.rawValue, statement, 3)
        bind(entityID, statement, 4)
        bind(String(decoding: try encoder.encode(desiredState), as: UTF8.self), statement, 5)
        bind(ActionCommandState.pending.rawValue, statement, 6)
        bind(formatter.string(from: date), statement, 7)
        bind(formatter.string(from: date), statement, 8)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ActionOutboxStoreError.write(errorMessage) }
        if sqlite3_changes(database) == 0, let existing = try self.command(idempotencyKey: idempotencyKey) {
            committed = true
            return ActionEnqueueResult(command: existing, wasInserted: false)
        }
        try appendAuditEvent(
            type: "action.enqueued",
            entityID: command.id,
            occurredAt: date,
            payload: ["actionType": type.rawValue, "targetEntityID": entityID, "idempotencyKey": idempotencyKey]
        )
        committed = true
        return ActionEnqueueResult(command: command, wasInserted: true)
    }

    public func claimNextReady() throws -> ActionCommand? {
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        let date = now()
        let sql = """
        SELECT id FROM action_commands
        WHERE state IN ('pending', 'retryable_failure')
          AND (next_attempt_at_utc IS NULL OR next_attempt_at_utc <= ?)
        ORDER BY created_at_utc ASC, id ASC
        LIMIT 1;
        """
        var select: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &select, nil) == SQLITE_OK,
              let select
        else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(select) }
        bind(formatter.string(from: date), select, 1)
        guard sqlite3_step(select) == SQLITE_ROW,
              let idPointer = sqlite3_column_text(select, 0)
        else {
            committed = true
            return nil
        }
        let id = String(cString: idPointer)
        let update = "UPDATE action_commands SET state = 'executing', attempt_count = attempt_count + 1, updated_at_utc = ? WHERE id = ? AND state IN ('pending', 'retryable_failure');"
        try execute(update, bindings: [formatter.string(from: date), id])
        guard sqlite3_changes(database) == 1,
              let claimed = try command(id: id)
        else { throw ActionOutboxStoreError.claimConflict }
        try insertAttempt(command: claimed, state: .executing, startedAt: date)
        try appendAuditEvent(type: "action.executing", entityID: claimed.id, occurredAt: date, payload: ["attempt": String(claimed.attemptCount)])
        committed = true
        return claimed
    }

    public func markSucceeded(_ command: ActionCommand, platformIdentifier: String? = nil) throws {
        try finish(command, state: .succeeded, platformIdentifier: platformIdentifier, redactedError: nil, nextAttemptAt: nil)
    }

    public func markFailed(_ command: ActionCommand, retryable: Bool, redactedError: String, retryAt: Date? = nil) throws {
        let state: ActionCommandState = retryable ? .retryableFailure : .terminalFailure
        try finish(command, state: state, platformIdentifier: nil, redactedError: redactedError, nextAttemptAt: retryable ? retryAt : nil)
    }

    public func cancel(commandID: String) throws {
        let date = now()
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        try execute(
            "UPDATE action_commands SET state = 'cancelled', updated_at_utc = ? WHERE id = ? AND state IN ('pending', 'retryable_failure');",
            bindings: [formatter.string(from: date), commandID]
        )
        guard sqlite3_changes(database) == 1 else { throw ActionOutboxStoreError.invalidTransition }
        try appendAuditEvent(type: "action.cancelled", entityID: commandID, occurredAt: date, payload: [:])
        committed = true
    }

    public func executingCommands() throws -> [ActionCommand] {
        try commands(where: "state = 'executing'")
    }

    public func recentCommands(limit: Int = 100) throws -> [ActionCommand] {
        try commands(where: "1 = 1", suffix: "ORDER BY created_at_utc DESC LIMIT \(max(1, limit))")
    }

    public func command(commandID: String) throws -> ActionCommand? {
        try command(id: commandID)
    }

    public func attempts(commandID: String) throws -> [ActionAttempt] {
        let sql = """
        SELECT id, command_id, attempt_number, state, platform_identifier, redacted_error, started_at_utc, finished_at_utc
        FROM action_attempts WHERE command_id = ? ORDER BY attempt_number ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(commandID, statement, 1)
        var attempts: [ActionAttempt] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0),
              let storedCommandID = text(statement, 1),
              let stateRaw = text(statement, 3),
              let state = ActionCommandState(rawValue: stateRaw),
              let startedRaw = text(statement, 6),
              let startedAt = formatter.date(from: startedRaw) {
            attempts.append(ActionAttempt(
                id: id,
                commandID: storedCommandID,
                attemptNumber: Int(sqlite3_column_int(statement, 2)),
                state: state,
                platformIdentifier: text(statement, 4),
                redactedError: text(statement, 5),
                startedAt: startedAt,
                finishedAt: text(statement, 7).flatMap(formatter.date(from:))
            ))
        }
        return attempts
    }

    private func finish(_ command: ActionCommand, state: ActionCommandState, platformIdentifier: String?, redactedError: String?, nextAttemptAt: Date?) throws {
        let date = now()
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        var statement: OpaquePointer?
        let sql = "UPDATE action_commands SET state = ?, next_attempt_at_utc = ?, updated_at_utc = ? WHERE id = ? AND state = 'executing';"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(state.rawValue, statement, 1)
        if let nextAttemptAt { bind(formatter.string(from: nextAttemptAt), statement, 2) } else { sqlite3_bind_null(statement, 2) }
        bind(formatter.string(from: date), statement, 3)
        bind(command.id, statement, 4)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw ActionOutboxStoreError.invalidTransition }

        let attemptSQL = """
        UPDATE action_attempts SET state = ?, platform_identifier = ?, redacted_error = ?, finished_at_utc = ?
        WHERE command_id = ? AND attempt_number = ? AND state = 'executing';
        """
        var attempt: OpaquePointer?
        guard sqlite3_prepare_v2(database, attemptSQL, -1, &attempt, nil) == SQLITE_OK, let attempt else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(attempt) }
        bind(state.rawValue, attempt, 1)
        if let platformIdentifier { bind(platformIdentifier, attempt, 2) } else { sqlite3_bind_null(attempt, 2) }
        if let redactedError { bind(redactedError, attempt, 3) } else { sqlite3_bind_null(attempt, 3) }
        bind(formatter.string(from: date), attempt, 4)
        bind(command.id, attempt, 5)
        sqlite3_bind_int(attempt, 6, Int32(command.attemptCount))
        guard sqlite3_step(attempt) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw ActionOutboxStoreError.invalidTransition }
        var auditPayload = ["state": state.rawValue, "attempt": String(command.attemptCount)]
        if let platformIdentifier { auditPayload["platformIdentifier"] = platformIdentifier }
        if redactedError != nil { auditPayload["hasError"] = "true" }
        try appendAuditEvent(type: "action.\(state.rawValue)", entityID: command.id, occurredAt: date, payload: auditPayload)
        committed = true
    }

    private func insertAttempt(command: ActionCommand, state: ActionCommandState, startedAt: Date) throws {
        let sql = "INSERT INTO action_attempts(id, command_id, attempt_number, state, started_at_utc) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(makeID(), statement, 1)
        bind(command.id, statement, 2)
        sqlite3_bind_int(statement, 3, Int32(command.attemptCount))
        bind(state.rawValue, statement, 4)
        bind(formatter.string(from: startedAt), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ActionOutboxStoreError.write(errorMessage) }
    }

    private func command(id: String) throws -> ActionCommand? {
        try oneCommand(where: "id = ?", value: id)
    }

    private func command(idempotencyKey: String) throws -> ActionCommand? {
        try oneCommand(where: "idempotency_key = ?", value: idempotencyKey)
    }

    private func oneCommand(where predicate: String, value: String) throws -> ActionCommand? {
        let sql = Self.commandSelect + " WHERE \(predicate) LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(value, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeCommand(statement)
    }

    private func commands(where predicate: String, suffix: String = "ORDER BY created_at_utc ASC") throws -> [ActionCommand] {
        let sql = Self.commandSelect + " WHERE \(predicate) \(suffix);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        var result: [ActionCommand] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(try decodeCommand(statement)) }
        return result
    }

    private func decodeCommand(_ statement: OpaquePointer) throws -> ActionCommand {
        guard let id = text(statement, 0),
              let idempotencyKey = text(statement, 1),
              let typeRaw = text(statement, 2),
              let type = ActionCommandType(rawValue: typeRaw),
              let entityID = text(statement, 3),
              let desiredJSON = text(statement, 4),
              let desiredState = try? decoder.decode(ActionDesiredState.self, from: Data(desiredJSON.utf8)),
              let stateRaw = text(statement, 5),
              let state = ActionCommandState(rawValue: stateRaw),
              let createdRaw = text(statement, 8),
              let createdAt = formatter.date(from: createdRaw),
              let updatedRaw = text(statement, 9),
              let updatedAt = formatter.date(from: updatedRaw)
        else { throw ActionOutboxStoreError.decode }
        return ActionCommand(
            id: id,
            idempotencyKey: idempotencyKey,
            type: type,
            entityID: entityID,
            desiredState: desiredState,
            state: state,
            attemptCount: Int(sqlite3_column_int(statement, 6)),
            nextAttemptAt: text(statement, 7).flatMap(formatter.date(from:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func execute(_ sql: String, bindings: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() { bind(value, statement, Int32(index + 1)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ActionOutboxStoreError.write(errorMessage) }
    }

    private func appendAuditEvent(type: String, entityID: String?, occurredAt: Date, payload: [String: String]) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: occurredAt)
        let localDay = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let evidenceJSON = "[]"
        let payloadJSON = String(decoding: try encoder.encode(payload), as: UTF8.self)
        let sql = """
        INSERT INTO domain_events
        (id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ActionOutboxStoreError.prepare(errorMessage) }
        defer { sqlite3_finalize(statement) }
        bind(makeID(), statement, 1)
        bind(type, statement, 2)
        if let entityID { bind(entityID, statement, 3) } else { sqlite3_bind_null(statement, 3) }
        bind(localDay, statement, 4)
        bind(timeZone.identifier, statement, 5)
        bind(formatter.string(from: occurredAt), statement, 6)
        bind(evidenceJSON, statement, 7)
        bind(payloadJSON, statement, 8)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ActionOutboxStoreError.write(errorMessage) }
    }

    private func begin() throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ActionOutboxStoreError.write(errorMessage) }
    }

    private func finishTransaction(commit: Bool) {
        _ = sqlite3_exec(database, commit ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(database)) }

    private static let commandSelect = """
    SELECT id, idempotency_key, action_type, entity_id, desired_state_json, state, attempt_count,
           next_attempt_at_utc, created_at_utc, updated_at_utc
    FROM action_commands
    """
}

public enum ActionOutboxStoreError: LocalizedError {
    case openDatabase
    case prepare(String)
    case write(String)
    case decode
    case claimConflict
    case invalidTransition

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the action outbox."
        case let .prepare(message): "Could not prepare an outbox operation: \(message)"
        case let .write(message): "Could not write the action outbox: \(message)"
        case .decode: "A stored action command could not be decoded."
        case .claimConflict: "Another executor claimed this action command."
        case .invalidTransition: "The action command changed state before it could be finalized."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
