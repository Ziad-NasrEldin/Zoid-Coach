import Foundation
import SQLite3
import ZoidCoachCore

public struct StoredEstimateLearningAggregate: Equatable, Sendable {
    public let context: EstimateLearningContext
    public let proposal: EstimateLearningProposal
    public let evidenceIDs: [String]
    public let confidence: Double
    public let updatedAtUTC: Date

    public init(
        context: EstimateLearningContext,
        proposal: EstimateLearningProposal,
        evidenceIDs: [String],
        confidence: Double,
        updatedAtUTC: Date
    ) {
        self.context = context
        self.proposal = proposal
        self.evidenceIDs = evidenceIDs
        self.confidence = confidence
        self.updatedAtUTC = updatedAtUTC
    }
}

public struct StoredWorkWindowLearningAggregate: Equatable, Sendable {
    public let timeZoneIdentifier: String
    public let proposal: PreferredWorkWindowProposal
    public let evidenceIDs: [String]
    public let confidence: Double
    public let updatedAtUTC: Date

    public init(
        timeZoneIdentifier: String,
        proposal: PreferredWorkWindowProposal,
        evidenceIDs: [String],
        confidence: Double,
        updatedAtUTC: Date
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.proposal = proposal
        self.evidenceIDs = evidenceIDs
        self.confidence = confidence
        self.updatedAtUTC = updatedAtUTC
    }
}

public final class LearningAggregateStore: @unchecked Sendable {
    private enum AggregateType: String {
        case estimate
        case preferredWorkWindow = "preferred_work_window"
    }

    private let database: OpaquePointer
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
            throw LearningAggregateStoreError.openDatabase
        }
        database = handle
        self.now = now
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit {
        sqlite3_close(database)
    }

    @discardableResult
    public func recordEstimateSample(
        _ sample: EstimateLearningSample,
        evidenceID: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> Bool {
        let payload = EstimateSamplePayload(sample: sample, evidenceID: evidenceID ?? sample.id)
        return try recordSample(
            id: sample.id,
            type: .estimate,
            contextKey: try Self.contextKey(sample.context),
            estimatedValue: Double(sample.estimatedMinutes),
            actualValue: Double(sample.actualAlignedMinutes),
            localMinuteOfDay: nil,
            timeZoneIdentifier: timeZoneIdentifier,
            evidenceID: payload.evidenceID,
            occurredAt: sample.completedAt,
            payload: payload
        )
    }

    @discardableResult
    public func recordWorkWindowSample(
        _ sample: WorkWindowLearningSample,
        timeZoneIdentifier: String,
        evidenceID: String? = nil
    ) throws -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw LearningAggregateStoreError.invalidTimeZone(timeZoneIdentifier)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: sample.startedAt)
        let localMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let payload = WorkWindowSamplePayload(
            sample: sample,
            timeZoneIdentifier: timeZoneIdentifier,
            evidenceID: evidenceID ?? sample.id
        )
        return try recordSample(
            id: sample.id,
            type: .preferredWorkWindow,
            contextKey: timeZoneIdentifier,
            estimatedValue: nil,
            actualValue: sample.endedAt.timeIntervalSince(sample.startedAt) / 60,
            localMinuteOfDay: localMinute,
            timeZoneIdentifier: timeZoneIdentifier,
            evidenceID: payload.evidenceID,
            occurredAt: sample.startedAt,
            payload: payload
        )
    }

    @discardableResult
    public func updateEstimateAggregate(
        context: EstimateLearningContext,
        currentEstimateMinutes: Int,
        policy: EstimateLearningPolicy = EstimateLearningPolicy()
    ) throws -> EstimateLearningProposal? {
        lock.lock()
        defer { lock.unlock() }
        let contextKey = try Self.contextKey(context)
        let samples: [EstimateLearningSample] = try samplePayloads(
            type: .estimate,
            contextKey: contextKey,
            as: EstimateSamplePayload.self
        ).map(\.sample)
        guard let proposal = EstimateLearner(clock: FixedReplayClock(now: now())).proposal(
            for: context,
            currentEstimateMinutes: currentEstimateMinutes,
            samples: samples,
            policy: policy
        ) else { return nil }
        try upsertAggregate(
            type: .estimate,
            key: contextKey,
            sampleCount: proposal.sampleCount,
            medianValue: Double(proposal.recommendedEstimateMinutes),
            confidence: Self.confidence(sampleCount: proposal.sampleCount, limit: policy.rollingSampleLimit),
            policyVersion: proposal.policyVersion,
            proposal: proposal,
            rollback: proposal.rollbackEstimateMinutes
        )
        return proposal
    }

    @discardableResult
    public func updatePreferredWorkWindowAggregate(
        timeZoneIdentifier: String,
        rollbackWindow: WeeklyWorkWindow? = nil,
        policy: PreferredWorkWindowLearningPolicy = PreferredWorkWindowLearningPolicy()
    ) throws -> PreferredWorkWindowProposal? {
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw LearningAggregateStoreError.invalidTimeZone(timeZoneIdentifier)
        }
        lock.lock()
        defer { lock.unlock() }
        let samples: [WorkWindowLearningSample] = try samplePayloads(
            type: .preferredWorkWindow,
            contextKey: timeZoneIdentifier,
            as: WorkWindowSamplePayload.self
        ).map(\.sample)
        guard let proposal = PreferredWorkWindowLearner(clock: FixedReplayClock(now: now())).proposal(
            samples: samples,
            timeZoneIdentifier: timeZoneIdentifier,
            rollbackWindow: rollbackWindow,
            policy: policy
        ) else { return nil }
        let startMinute = proposal.preferredWindow.start.hour * 60 + proposal.preferredWindow.start.minute
        try upsertAggregate(
            type: .preferredWorkWindow,
            key: timeZoneIdentifier,
            sampleCount: proposal.sampleCount,
            medianValue: Double(startMinute),
            confidence: Self.confidence(sampleCount: proposal.sampleCount, limit: policy.rollingSampleLimit),
            policyVersion: proposal.policyVersion,
            proposal: proposal,
            rollback: proposal.rollbackWindow
        )
        return proposal
    }

    public func estimateAggregate(for context: EstimateLearningContext) throws -> StoredEstimateLearningAggregate? {
        lock.lock()
        defer { lock.unlock() }
        guard let row = try aggregate(type: .estimate, key: Self.contextKey(context)) else { return nil }
        let proposal = try decode(EstimateLearningProposal.self, from: row.proposalJSON)
        let samples: [EstimateSamplePayload] = try samplePayloads(
            type: .estimate,
            contextKey: Self.contextKey(context),
            as: EstimateSamplePayload.self
        )
        let evidenceBySample = Dictionary(uniqueKeysWithValues: samples.map { ($0.sample.id, $0.evidenceID) })
        return StoredEstimateLearningAggregate(
            context: context,
            proposal: proposal,
            evidenceIDs: proposal.evidenceIDs.compactMap { evidenceBySample[$0] },
            confidence: row.confidence,
            updatedAtUTC: row.updatedAtUTC
        )
    }

    public func preferredWorkWindowAggregate(
        timeZoneIdentifier: String
    ) throws -> StoredWorkWindowLearningAggregate? {
        lock.lock()
        defer { lock.unlock() }
        guard let row = try aggregate(type: .preferredWorkWindow, key: timeZoneIdentifier) else { return nil }
        let proposal = try decode(PreferredWorkWindowProposal.self, from: row.proposalJSON)
        let samples: [WorkWindowSamplePayload] = try samplePayloads(
            type: .preferredWorkWindow,
            contextKey: timeZoneIdentifier,
            as: WorkWindowSamplePayload.self
        )
        let evidenceBySample = Dictionary(uniqueKeysWithValues: samples.map { ($0.sample.id, $0.evidenceID) })
        return StoredWorkWindowLearningAggregate(
            timeZoneIdentifier: timeZoneIdentifier,
            proposal: proposal,
            evidenceIDs: proposal.evidenceIDs.compactMap { evidenceBySample[$0] },
            confidence: row.confidence,
            updatedAtUTC: row.updatedAtUTC
        )
    }

    public func learnedEstimate(
        for context: EstimateLearningContext,
        fallbackMinutes: Int
    ) throws -> Int {
        try estimateAggregate(for: context)?.proposal.recommendedEstimateMinutes ?? fallbackMinutes
    }

    public func rollbackEstimate(for context: EstimateLearningContext) throws -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let row = try aggregate(type: .estimate, key: Self.contextKey(context)),
              let rollbackJSON = row.rollbackJSON else { return nil }
        return try decode(Int.self, from: rollbackJSON)
    }

    public func rollbackWorkWindow(timeZoneIdentifier: String) throws -> WeeklyWorkWindow? {
        lock.lock()
        defer { lock.unlock() }
        guard let row = try aggregate(type: .preferredWorkWindow, key: timeZoneIdentifier),
              let rollbackJSON = row.rollbackJSON else { return nil }
        return try decode(WeeklyWorkWindow.self, from: rollbackJSON)
    }

    private func recordSample<Payload: Encodable>(
        id: String,
        type: AggregateType,
        contextKey: String,
        estimatedValue: Double?,
        actualValue: Double,
        localMinuteOfDay: Int?,
        timeZoneIdentifier: String,
        evidenceID: String,
        occurredAt: Date,
        payload: Payload
    ) throws -> Bool {
        let payloadJSON = try encode(payload)
        lock.lock()
        defer { lock.unlock() }
        if let existing = try existingSamplePayload(id: id) {
            guard existing == payloadJSON else { throw LearningAggregateStoreError.sampleConflict(id) }
            return false
        }
        try execute(
            """
            INSERT INTO learning_samples(
                id, sample_type, context_key, estimated_value, actual_value,
                local_minute_of_day, timezone_identifier, evidence_id,
                occurred_at_utc, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(id), .text(type.rawValue), .text(contextKey),
                estimatedValue.map(SQLiteBinding.real) ?? .null,
                .real(actualValue),
                localMinuteOfDay.map(SQLiteBinding.integer) ?? .null,
                .text(timeZoneIdentifier), .text(evidenceID),
                .text(Self.timestamp(occurredAt)), .text(payloadJSON)
            ]
        )
        return true
    }

    private func samplePayloads<Payload: Decodable>(
        type: AggregateType,
        contextKey: String,
        as _: Payload.Type
    ) throws -> [Payload] {
        let sql = """
        SELECT payload_json
        FROM learning_samples
        WHERE sample_type = ? AND context_key = ? AND payload_json IS NOT NULL
        ORDER BY occurred_at_utc DESC, id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        try bind([.text(type.rawValue), .text(contextKey)], to: statement)
        var result: [Payload] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let pointer = sqlite3_column_text(statement, 0) else {
                    throw LearningAggregateStoreError.corruptData
                }
                result.append(try decode(Payload.self, from: String(cString: pointer)))
            case SQLITE_DONE:
                return result
            default:
                throw databaseError(.read)
            }
        }
    }

    private func upsertAggregate<Proposal: Encodable, Rollback: Encodable>(
        type: AggregateType,
        key: String,
        sampleCount: Int,
        medianValue: Double,
        confidence: Double,
        policyVersion: Int,
        proposal: Proposal,
        rollback: Rollback?
    ) throws {
        try execute(
            """
            INSERT INTO learning_aggregates(
                aggregate_type, aggregate_key, sample_count, median_value,
                confidence, policy_version, updated_at_utc, proposal_json, rollback_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(aggregate_type, aggregate_key) DO UPDATE SET
                sample_count = excluded.sample_count,
                median_value = excluded.median_value,
                confidence = excluded.confidence,
                policy_version = excluded.policy_version,
                updated_at_utc = excluded.updated_at_utc,
                proposal_json = excluded.proposal_json,
                rollback_json = excluded.rollback_json;
            """,
            bindings: [
                .text(type.rawValue), .text(key), .integer(sampleCount), .real(medianValue),
                .real(confidence), .integer(policyVersion), .text(Self.timestamp(now())),
                .text(try encode(proposal)),
                try rollback.map { .text(try encode($0)) } ?? .null
            ]
        )
    }

    private func aggregate(type: AggregateType, key: String) throws -> AggregateRow? {
        let sql = """
        SELECT confidence, updated_at_utc, proposal_json, rollback_json
        FROM learning_aggregates
        WHERE aggregate_type = ? AND aggregate_key = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        try bind([.text(type.rawValue), .text(key)], to: statement)
        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            guard let updatedPointer = sqlite3_column_text(statement, 1),
                  let proposalPointer = sqlite3_column_text(statement, 2),
                  let updatedAt = Self.parseTimestamp(String(cString: updatedPointer)) else {
                throw LearningAggregateStoreError.corruptData
            }
            return AggregateRow(
                confidence: sqlite3_column_double(statement, 0),
                updatedAtUTC: updatedAt,
                proposalJSON: String(cString: proposalPointer),
                rollbackJSON: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            )
        default:
            throw databaseError(.read)
        }
    }

    private func existingSamplePayload(id: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT payload_json FROM learning_samples WHERE id = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        try bind([.text(id)], to: statement)
        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            guard let pointer = sqlite3_column_text(statement, 0) else {
                throw LearningAggregateStoreError.corruptData
            }
            return String(cString: pointer)
        default:
            throw databaseError(.read)
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.write) }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case let .integer(value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case let .real(value):
                result = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw databaseError(.write) }
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        do {
            let data = try encoder.encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw LearningAggregateStoreError.encode("Encoded JSON was not UTF-8.")
            }
            return string
        } catch let error as LearningAggregateStoreError {
            throw error
        } catch {
            throw LearningAggregateStoreError.encode(error.localizedDescription)
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        do {
            guard let data = json.data(using: .utf8) else { throw LearningAggregateStoreError.corruptData }
            return try decoder.decode(type, from: data)
        } catch let error as LearningAggregateStoreError {
            throw error
        } catch {
            throw LearningAggregateStoreError.decode(error.localizedDescription)
        }
    }

    private func databaseError(_ operation: LearningAggregateStoreError.Operation) -> LearningAggregateStoreError {
        let message = sqlite3_errmsg(database).map(String.init(cString:)) ?? "Unknown SQLite error"
        return .database(operation, message)
    }

    private static func contextKey(_ context: EstimateLearningContext) throws -> String {
        let encoder = makeEncoder()
        let data = try encoder.encode(context)
        guard let key = data.base64EncodedString(options: []).addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) else { throw LearningAggregateStoreError.encode("Could not create a context key.") }
        return key
    }

    private static func confidence(sampleCount: Int, limit: Int) -> Double {
        min(max(Double(sampleCount) / Double(max(limit, 1)), 0), 1)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func timestamp(_ date: Date) -> String {
        preciseFormatter().string(from: date)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        preciseFormatter().date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func preciseFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private struct EstimateSamplePayload: Codable, Equatable {
    let sample: EstimateLearningSample
    let evidenceID: String
}

private struct WorkWindowSamplePayload: Codable, Equatable {
    let sample: WorkWindowLearningSample
    let timeZoneIdentifier: String
    let evidenceID: String
}

private struct AggregateRow {
    let confidence: Double
    let updatedAtUTC: Date
    let proposalJSON: String
    let rollbackJSON: String?
}

private enum SQLiteBinding {
    case integer(Int)
    case real(Double)
    case text(String)
    case null
}

public enum LearningAggregateStoreError: Error, Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case read
        case write
    }

    case openDatabase
    case database(Operation, String)
    case invalidTimeZone(String)
    case sampleConflict(String)
    case corruptData
    case encode(String)
    case decode(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
