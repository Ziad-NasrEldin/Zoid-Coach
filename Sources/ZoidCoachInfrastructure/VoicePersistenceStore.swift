import Foundation
import SQLite3
import ZoidCoachCore

public final class VoicePersistenceStore: @unchecked Sendable {
    private let database: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSRecursiveLock()

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            throw VoicePersistenceStoreError.openDatabase
        }
        self.database = database
        sqlite3_busy_timeout(database, 5_000)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit { sqlite3_close(database) }

    public func save(_ session: VoiceSession) throws {
        let sql = """
        INSERT INTO voice_sessions(id, payload, started_at_utc, ended_at_utc)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            payload = excluded.payload,
            started_at_utc = excluded.started_at_utc,
            ended_at_utc = excluded.ended_at_utc;
        """
        try execute(sql) { statement in
            bind(session.id, statement, 1)
            bind(try encoder.encode(session), statement, 2)
            bind(timestamp(session.startedAt), statement, 3)
            bind(session.endedAt.map(timestamp), statement, 4)
        }
    }

    public func session(id: String) throws -> VoiceSession? {
        try decodeOne(
            "SELECT payload FROM voice_sessions WHERE id = ?;",
            as: VoiceSession.self
        ) { statement in bind(id, statement, 1) }
    }

    public func append(_ turn: ConversationTurn) throws {
        let sql = """
        INSERT OR REPLACE INTO conversation_turns(id, session_id, role, text, is_final, created_at_utc)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        try execute(sql) { statement in
            bind(turn.id, statement, 1)
            bind(turn.sessionID, statement, 2)
            bind(turn.role.rawValue, statement, 3)
            bind(turn.text, statement, 4)
            sqlite3_bind_int(statement, 5, turn.isFinal ? 1 : 0)
            bind(timestamp(turn.createdAt), statement, 6)
        }
    }

    public func turns(sessionID: String) throws -> [ConversationTurn] {
        let sql = """
        SELECT id, session_id, role, text, is_final, created_at_utc
        FROM conversation_turns
        WHERE session_id = ?
        ORDER BY created_at_utc, id;
        """
        return try query(sql, bind: { statement in bind(sessionID, statement, 1) }) { statement in
            guard let role = ConversationRole(rawValue: string(statement, 2)),
                  let createdAt = date(string(statement, 5)) else {
                throw VoicePersistenceStoreError.decode
            }
            return ConversationTurn(
                id: string(statement, 0),
                sessionID: string(statement, 1),
                role: role,
                text: string(statement, 3),
                isFinal: sqlite3_column_int(statement, 4) == 1,
                createdAt: createdAt
            )
        }
    }

    public func pruneTranscripts(olderThan cutoff: Date) throws {
        try execute("DELETE FROM conversation_turns WHERE created_at_utc < ?;") { statement in
            bind(timestamp(cutoff), statement, 1)
        }
    }

    public func save(_ fact: ConversationMemoryFact) throws {
        let sql = """
        INSERT INTO conversation_memory_facts(id, payload, kind, is_confirmed, expires_at_utc, created_at_utc, updated_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            payload = excluded.payload,
            kind = excluded.kind,
            is_confirmed = excluded.is_confirmed,
            expires_at_utc = excluded.expires_at_utc,
            updated_at_utc = excluded.updated_at_utc;
        """
        try execute(sql) { statement in
            bind(fact.id, statement, 1)
            bind(try encoder.encode(fact), statement, 2)
            bind(fact.kind.rawValue, statement, 3)
            sqlite3_bind_int(statement, 4, fact.isConfirmed ? 1 : 0)
            bind(fact.expiresAt.map(timestamp), statement, 5)
            bind(timestamp(fact.createdAt), statement, 6)
            bind(timestamp(fact.updatedAt), statement, 7)
        }
    }

    public func activeMemoryFacts(at date: Date) throws -> [ConversationMemoryFact] {
        try decodeMany(
            """
            SELECT payload FROM conversation_memory_facts
            WHERE expires_at_utc IS NULL OR expires_at_utc > ?
            ORDER BY updated_at_utc DESC, id;
            """,
            as: ConversationMemoryFact.self
        ) { statement in bind(timestamp(date), statement, 1) }
    }

    public func memoryFact(id: String) throws -> ConversationMemoryFact? {
        try decodeOne(
            "SELECT payload FROM conversation_memory_facts WHERE id = ?;",
            as: ConversationMemoryFact.self
        ) { statement in bind(id, statement, 1) }
    }

    public func deleteAllTranscripts() throws {
        try execute("DELETE FROM conversation_turns;")
    }

    public func deleteMemoryFact(id: String) throws {
        try execute("DELETE FROM conversation_memory_facts WHERE id = ?;") { statement in
            bind(id, statement, 1)
        }
    }

    public func save(_ ledger: VoiceUsageLedger, updatedAt: Date) throws {
        let sql = """
        INSERT INTO voice_usage_ledgers(period_start_utc, payload, updated_at_utc)
        VALUES (?, ?, ?)
        ON CONFLICT(period_start_utc) DO UPDATE SET
            payload = excluded.payload,
            updated_at_utc = excluded.updated_at_utc;
        """
        try execute(sql) { statement in
            bind(timestamp(ledger.periodStart), statement, 1)
            bind(try encoder.encode(ledger), statement, 2)
            bind(timestamp(updatedAt), statement, 3)
        }
    }

    public func latestUsageLedger() throws -> VoiceUsageLedger? {
        try decodeOne(
            "SELECT payload FROM voice_usage_ledgers ORDER BY period_start_utc DESC LIMIT 1;",
            as: VoiceUsageLedger.self
        )
    }

    public func save(_ job: CodexJob) throws {
        let updatedAt = job.finishedAt ?? job.startedAt ?? job.createdAt
        let sql = """
        INSERT INTO codex_jobs(id, state, payload, created_at_utc, updated_at_utc)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            payload = excluded.payload,
            updated_at_utc = excluded.updated_at_utc;
        """
        try execute(sql) { statement in
            bind(job.id, statement, 1)
            bind(job.state.rawValue, statement, 2)
            bind(try encoder.encode(job), statement, 3)
            bind(timestamp(job.createdAt), statement, 4)
            bind(timestamp(updatedAt), statement, 5)
        }
    }

    public func codexJob(id: String) throws -> CodexJob? {
        try decodeOne("SELECT payload FROM codex_jobs WHERE id = ?;", as: CodexJob.self) { statement in
            bind(id, statement, 1)
        }
    }

    public func codexJobs(states: [CodexJobState]? = nil) throws -> [CodexJob] {
        let all = try decodeMany(
            "SELECT payload FROM codex_jobs ORDER BY updated_at_utc DESC, id;",
            as: CodexJob.self
        )
        guard let states else { return all }
        return all.filter { states.contains($0.state) }
    }

    public func save(
        _ invocation: VoiceToolInvocation,
        riskLevel: ToolRiskLevel,
        decision: VoiceToolDecision
    ) throws {
        let sql = """
        INSERT OR REPLACE INTO voice_tool_invocations(
            id, session_id, tool_name, risk_level, decision, payload, requested_at_utc
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try execute(sql) { statement in
            bind(invocation.id, statement, 1)
            bind(invocation.sessionID, statement, 2)
            bind(invocation.toolName, statement, 3)
            bind(riskLevel.rawValue, statement, 4)
            bind(decision.rawValue, statement, 5)
            bind(try encoder.encode(invocation), statement, 6)
            bind(timestamp(invocation.requestedAt), statement, 7)
        }
    }

    public func invocation(id: String) throws -> VoiceToolInvocation? {
        try decodeOne(
            "SELECT payload FROM voice_tool_invocations WHERE id = ?;",
            as: VoiceToolInvocation.self
        ) { statement in bind(id, statement, 1) }
    }

    public func save(_ approval: ApprovalRequest) throws {
        let sql = """
        INSERT INTO voice_approval_requests(id, invocation_id, state, payload, created_at_utc, expires_at_utc, resolved_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            state = excluded.state,
            payload = excluded.payload,
            resolved_at_utc = excluded.resolved_at_utc;
        """
        try execute(sql) { statement in
            bind(approval.id, statement, 1)
            bind(approval.invocationID, statement, 2)
            bind(approval.state.rawValue, statement, 3)
            bind(try encoder.encode(approval), statement, 4)
            bind(timestamp(approval.createdAt), statement, 5)
            bind(timestamp(approval.expiresAt), statement, 6)
            bind(approval.resolvedAt.map(timestamp), statement, 7)
        }
    }

    public func approval(id: String) throws -> ApprovalRequest? {
        try decodeOne(
            "SELECT payload FROM voice_approval_requests WHERE id = ?;",
            as: ApprovalRequest.self
        ) { statement in bind(id, statement, 1) }
    }

    public func recordTransmission(
        _ selection: ScreenContextSelection,
        sessionID: String,
        transmittedAt: Date
    ) throws {
        try execute("""
        INSERT INTO screen_context_transmissions(id, session_id, selection_payload, transmitted_at_utc)
        VALUES (?, ?, ?, ?);
        """) { statement in
            bind(selection.id, statement, 1)
            bind(sessionID, statement, 2)
            bind(try encoder.encode(selection), statement, 3)
            bind(timestamp(transmittedAt), statement, 4)
        }
    }

    private func execute(_ sql: String, bind values: (OpaquePointer) throws -> Void = { _ in }) throws {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw VoicePersistenceStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try values(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VoicePersistenceStoreError.write(errorMessage)
        }
    }

    private func query<Value>(
        _ sql: String,
        bind values: (OpaquePointer) throws -> Void = { _ in },
        row: (OpaquePointer) throws -> Value
    ) throws -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw VoicePersistenceStoreError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try values(statement)
        var result: [Value] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try row(statement))
        }
        return result
    }

    private func decodeOne<Value: Decodable>(
        _ sql: String,
        as type: Value.Type,
        bind values: (OpaquePointer) throws -> Void = { _ in }
    ) throws -> Value? {
        try decodeMany(sql, as: type, bind: values).first
    }

    private func decodeMany<Value: Decodable>(
        _ sql: String,
        as type: Value.Type,
        bind values: (OpaquePointer) throws -> Void = { _ in }
    ) throws -> [Value] {
        try query(sql, bind: values) { statement in
            guard let bytes = sqlite3_column_blob(statement, 0) else {
                throw VoicePersistenceStoreError.decode
            }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            do { return try decoder.decode(type, from: data) }
            catch { throw VoicePersistenceStoreError.decode }
        }
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func bind(_ value: String?, _ statement: OpaquePointer, _ index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bind(value, statement, index)
    }

    private func bind(_ value: Data, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }

    private var errorMessage: String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "Unknown SQLite error"
    }
}

public enum VoicePersistenceStoreError: LocalizedError {
    case openDatabase
    case prepare(String)
    case write(String)
    case decode

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the Zoid Voice database."
        case let .prepare(message): "Could not prepare a Zoid Voice database operation: \(message)"
        case let .write(message): "Could not persist Zoid Voice state: \(message)"
        case .decode: "Could not decode persisted Zoid Voice state."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
