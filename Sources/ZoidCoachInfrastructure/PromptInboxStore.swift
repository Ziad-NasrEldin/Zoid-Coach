import Foundation
import SQLite3
import ZoidCoachCore

public struct PromptEnqueueResult: Equatable, Sendable {
    public let episode: PromptEpisode
    public let wasInserted: Bool

    public init(episode: PromptEpisode, wasInserted: Bool) {
        self.episode = episode
        self.wasInserted = wasInserted
    }
}

public struct PromptResponseResult: Equatable, Sendable {
    public let response: PromptResponse
    public let episode: PromptEpisode
    public let wasApplied: Bool

    public init(response: PromptResponse, episode: PromptEpisode, wasApplied: Bool) {
        self.response = response
        self.episode = episode
        self.wasApplied = wasApplied
    }
}

public final class PromptInboxStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let formatter = ISO8601DateFormatter()
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw PromptInboxStoreError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        self.now = now
        self.makeID = makeID
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit { sqlite3_close(database) }

    public func enqueue(_ draft: PromptDraft) throws -> PromptEnqueueResult {
        guard !draft.decisionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.actions.isEmpty,
              Set(draft.actions.map(\.kind)).count == draft.actions.count
        else { throw PromptInboxStoreError.invalidDraft }
        let date = now()
        guard draft.expiresAt.map({ $0 > date }) ?? true else { throw PromptInboxStoreError.expired }

        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        _ = try expireDueLocked(at: date)
        if let existing = try unresolved(decisionKey: draft.decisionKey) {
            committed = true
            return PromptEnqueueResult(episode: existing, wasInserted: false)
        }

        let detected = PromptEpisode(
            id: makeID(),
            decisionKey: draft.decisionKey,
            type: draft.type,
            title: draft.title,
            summary: draft.summary,
            actions: draft.actions,
            payload: draft.payload,
            createdAt: date,
            expiresAt: draft.expiresAt
        )
        let episode = try detected.applying(.queue, at: date)
        do {
            try insert(episode)
        } catch PromptInboxStoreError.write where sqlite3_errcode(database) == SQLITE_CONSTRAINT {
            if let existing = try unresolved(decisionKey: draft.decisionKey) {
                committed = true
                return PromptEnqueueResult(episode: existing, wasInserted: false)
            }
            throw PromptInboxStoreError.write(errorMessage)
        }
        committed = true
        return PromptEnqueueResult(episode: episode, wasInserted: true)
    }

    @discardableResult
    public func present(promptID: String) throws -> PromptEpisode {
        try expireDue()
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        guard let episode = try episode(id: promptID) else { throw PromptInboxStoreError.notFound }
        if episode.state == .presented {
            committed = true
            return episode
        }
        let presented = try transition(episode, on: .present, at: now())
        try update(presented)
        committed = true
        return presented
    }

    public func respond(
        promptID: String,
        action: PromptActionKind,
        actionToken: String,
        surface: PromptSurface
    ) throws -> PromptResponseResult {
        try expireDue()
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }

        if let existing = try response(actionToken: actionToken) {
            guard existing.promptID == promptID,
                  existing.action == action,
                  let episode = try episode(id: promptID)
            else { throw PromptInboxStoreError.invalidActionToken }
            committed = true
            return PromptResponseResult(response: existing, episode: episode, wasApplied: false)
        }
        guard var episode = try episode(id: promptID) else { throw PromptInboxStoreError.notFound }
        if !episode.state.isUnresolved {
            if let existing = try response(promptID: promptID) {
                committed = true
                return PromptResponseResult(response: existing, episode: episode, wasApplied: false)
            }
            throw PromptInboxStoreError.alreadyResolved
        }
        guard episode.actions.contains(where: { $0.kind == action }),
              PromptResponseToken.make(promptID: promptID, action: action) == actionToken
        else { throw PromptInboxStoreError.invalidActionToken }

        let date = now()
        if episode.state == .queued {
            episode = try transition(episode, on: .present, at: date)
        }
        let responded = try transition(episode, on: .respond, at: date)
        let response = PromptResponse(
            id: makeID(),
            promptID: promptID,
            action: action,
            actionToken: actionToken,
            surface: surface,
            respondedAt: date
        )
        try insert(response)
        try update(responded, releaseDecisionKey: true)
        committed = true
        return PromptResponseResult(response: response, episode: responded, wasApplied: true)
    }

    @discardableResult
    public func dismiss(promptID: String) throws -> PromptEpisode {
        try expireDue()
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        guard let episode = try episode(id: promptID) else { throw PromptInboxStoreError.notFound }
        if episode.state == .dismissed {
            committed = true
            return episode
        }
        let dismissed = try transition(episode, on: .dismiss, at: now())
        try update(dismissed, releaseDecisionKey: true)
        committed = true
        return dismissed
    }

    @discardableResult
    public func expireDue() throws -> Int {
        try begin()
        var committed = false
        defer { finishTransaction(commit: committed) }
        let count = try expireDueLocked(at: now())
        committed = true
        return count
    }

    public func unresolved() throws -> [PromptEpisode] {
        try expireDue()
        return try episodes(where: "state IN ('detected', 'queued', 'presented')", bindings: [])
    }

    public func episode(promptID: String) throws -> PromptEpisode? {
        try episode(id: promptID)
    }

    public func responses(promptID: String) throws -> [PromptResponse] {
        let sql = Self.responseSelect + " WHERE prompt_id = ? ORDER BY responded_at_utc ASC, id ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(promptID, statement, 1)
        var result: [PromptResponse] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(try decodeResponse(statement)) }
        return result
    }

    private func expireDueLocked(at date: Date) throws -> Int {
        let due = try episodes(
            where: "state IN ('detected', 'queued', 'presented') AND expires_at_utc IS NOT NULL AND expires_at_utc <= ?",
            bindings: [formatter.string(from: date)]
        )
        for episode in due {
            let expired = try transition(episode, on: .expire, at: date)
            try update(expired, releaseDecisionKey: true)
        }
        return due.count
    }

    private func transition(_ episode: PromptEpisode, on event: PromptEpisodeEvent, at date: Date) throws -> PromptEpisode {
        do { return try episode.applying(event, at: date) }
        catch let error as PromptStateMachineError { throw PromptInboxStoreError.invalidTransition(error) }
    }

    private func insert(_ episode: PromptEpisode) throws {
        let sql = """
        INSERT INTO prompt_episodes
        (id, decision_key, prompt_type, state, title, summary, action_token, payload_json, created_at_utc, expires_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(episode.id, statement, 1)
        bind(episode.decisionKey, statement, 2)
        bind(episode.type, statement, 3)
        bind(episode.state.rawValue, statement, 4)
        bind(episode.title, statement, 5)
        bind(episode.summary, statement, 6)
        bind(PromptResponseToken.episodeSeed(promptID: episode.id), statement, 7)
        bind(try encodeEnvelope(episode), statement, 8)
        bind(formatter.string(from: episode.createdAt), statement, 9)
        bindOptional(episode.expiresAt.map(formatter.string(from:)), statement, 10)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PromptInboxStoreError.write(errorMessage) }
    }

    private func insert(_ response: PromptResponse) throws {
        let sql = "INSERT INTO prompt_responses(id, prompt_id, action_token, response, surface, responded_at_utc) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(response.id, statement, 1)
        bind(response.promptID, statement, 2)
        bind(response.actionToken, statement, 3)
        bind(response.action.rawValue, statement, 4)
        bind(response.surface.rawValue, statement, 5)
        bind(formatter.string(from: response.respondedAt), statement, 6)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PromptInboxStoreError.write(errorMessage) }
    }

    private func update(_ episode: PromptEpisode, releaseDecisionKey: Bool = false) throws {
        let storedDecisionKey = releaseDecisionKey
            ? "resolved:\(episode.id):\(episode.decisionKey)"
            : episode.decisionKey
        let sql = "UPDATE prompt_episodes SET decision_key = ?, state = ?, payload_json = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(storedDecisionKey, statement, 1)
        bind(episode.state.rawValue, statement, 2)
        bind(try encodeEnvelope(episode), statement, 3)
        bind(episode.id, statement, 4)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
            throw PromptInboxStoreError.write(errorMessage)
        }
    }

    private func unresolved(decisionKey: String) throws -> PromptEpisode? {
        try oneEpisode(
            where: "decision_key = ? AND state IN ('detected', 'queued', 'presented')",
            bindings: [decisionKey]
        )
    }

    private func episode(id: String) throws -> PromptEpisode? {
        try oneEpisode(where: "id = ?", bindings: [id])
    }

    private func oneEpisode(where predicate: String, bindings: [String]) throws -> PromptEpisode? {
        try episodes(where: predicate, bindings: bindings, suffix: "LIMIT 1").first
    }

    private func episodes(where predicate: String, bindings: [String], suffix: String = "ORDER BY created_at_utc ASC, id ASC") throws -> [PromptEpisode] {
        let sql = Self.episodeSelect + " WHERE \(predicate) \(suffix);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() { bind(value, statement, Int32(index + 1)) }
        var result: [PromptEpisode] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(try decodeEpisode(statement)) }
        return result
    }

    private func response(actionToken: String) throws -> PromptResponse? {
        try oneResponse(where: "action_token = ?", value: actionToken)
    }

    private func response(promptID: String) throws -> PromptResponse? {
        try oneResponse(where: "prompt_id = ?", value: promptID)
    }

    private func oneResponse(where predicate: String, value: String) throws -> PromptResponse? {
        let sql = Self.responseSelect + " WHERE \(predicate) ORDER BY responded_at_utc ASC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PromptInboxStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        bind(value, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeResponse(statement)
    }

    private func decodeEpisode(_ statement: OpaquePointer) throws -> PromptEpisode {
        guard let id = text(statement, 0),
              let storedDecisionKey = text(statement, 1),
              let type = text(statement, 2),
              let stateRaw = text(statement, 3),
              let state = PromptEpisodeState(rawValue: stateRaw),
              let title = text(statement, 4),
              let summary = text(statement, 5),
              let payloadJSON = text(statement, 6),
              let createdRaw = text(statement, 7),
              let createdAt = formatter.date(from: createdRaw)
        else { throw PromptInboxStoreError.decode }
        let envelope = try decodeEnvelope(payloadJSON, fallbackDecisionKey: storedDecisionKey)
        return PromptEpisode(
            id: id,
            decisionKey: envelope.decisionKey,
            type: type,
            state: state,
            title: title,
            summary: summary,
            actions: envelope.actions,
            payload: envelope.payload,
            createdAt: createdAt,
            expiresAt: text(statement, 8).flatMap(formatter.date(from:)),
            presentedAt: envelope.presentedAt,
            resolvedAt: envelope.resolvedAt
        )
    }

    private func decodeResponse(_ statement: OpaquePointer) throws -> PromptResponse {
        guard let id = text(statement, 0),
              let promptID = text(statement, 1),
              let token = text(statement, 2),
              let actionRaw = text(statement, 3),
              let action = PromptActionKind(rawValue: actionRaw),
              let surfaceRaw = text(statement, 4),
              let surface = PromptSurface(rawValue: surfaceRaw),
              let respondedRaw = text(statement, 5),
              let respondedAt = formatter.date(from: respondedRaw)
        else { throw PromptInboxStoreError.decode }
        return PromptResponse(
            id: id,
            promptID: promptID,
            action: action,
            actionToken: token,
            surface: surface,
            respondedAt: respondedAt
        )
    }

    private func encodeEnvelope(_ episode: PromptEpisode) throws -> String {
        let envelope = StoredPromptEnvelope(
            decisionKey: episode.decisionKey,
            actions: episode.actions,
            payload: episode.payload,
            presentedAt: episode.presentedAt,
            resolvedAt: episode.resolvedAt
        )
        return String(decoding: try encoder.encode(envelope), as: UTF8.self)
    }

    private func decodeEnvelope(_ json: String, fallbackDecisionKey: String) throws -> StoredPromptEnvelope {
        if let envelope = try? decoder.decode(StoredPromptEnvelope.self, from: Data(json.utf8)) { return envelope }
        let payload = (try? decoder.decode([String: String].self, from: Data(json.utf8))) ?? [:]
        return StoredPromptEnvelope(
            decisionKey: fallbackDecisionKey,
            actions: [],
            payload: payload,
            presentedAt: nil,
            resolvedAt: nil
        )
    }

    private func begin() throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw PromptInboxStoreError.write(errorMessage)
        }
    }

    private func finishTransaction(commit: Bool) {
        _ = sqlite3_exec(database, commit ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func bindOptional(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        if let value { bind(value, statement, index) } else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(database)) }

    private static let episodeSelect = """
    SELECT id, decision_key, prompt_type, state, title, summary, payload_json, created_at_utc, expires_at_utc
    FROM prompt_episodes
    """

    private static let responseSelect = """
    SELECT id, prompt_id, action_token, response, surface, responded_at_utc
    FROM prompt_responses
    """
}

private struct StoredPromptEnvelope: Codable {
    let decisionKey: String
    let actions: [PromptAction]
    let payload: [String: String]
    let presentedAt: Date?
    let resolvedAt: Date?
}

public enum PromptInboxStoreError: LocalizedError, Equatable {
    case openDatabase
    case invalidDraft
    case expired
    case notFound
    case alreadyResolved
    case invalidActionToken
    case invalidTransition(PromptStateMachineError)
    case prepare(String)
    case write(String)
    case decode

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the prompt inbox."
        case .invalidDraft: "The prompt draft is incomplete or has duplicate actions."
        case .expired: "The prompt has already expired."
        case .notFound: "The prompt episode was not found."
        case .alreadyResolved: "The prompt episode has already been resolved."
        case .invalidActionToken: "The response token is not valid for this prompt action."
        case .invalidTransition: "The prompt episode cannot make that state transition."
        case let .prepare(message): "Could not prepare a prompt inbox operation: \(message)"
        case let .write(message): "Could not write the prompt inbox: \(message)"
        case .decode: "Stored prompt inbox data could not be decoded."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
