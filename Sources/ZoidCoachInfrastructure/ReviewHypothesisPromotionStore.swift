import Foundation
import SQLite3

public struct StoredReviewHypothesisPromotion: Equatable, Sendable {
    public let candidateID: String
    public let hypothesis: String
    public let sourceDay: String
    public let evidence: [String]
    public let promotedAt: Date

    public init(
        candidateID: String,
        hypothesis: String,
        sourceDay: String,
        evidence: [String],
        promotedAt: Date
    ) {
        self.candidateID = candidateID
        self.hypothesis = hypothesis
        self.sourceDay = sourceDay
        self.evidence = evidence
        self.promotedAt = promotedAt
    }
}

public enum ReviewHypothesisPromotionStoreError: LocalizedError, Equatable {
    case missingDatabase
    case openDatabase
    case invalidCandidate
    case candidateConflict(String)
    case encodeEvidence
    case decodeEvidence
    case read(String)
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .missingDatabase:
            "The Zoid 666 database is not available for hypothesis learning."
        case .openDatabase:
            "The Zoid 666 database could not be opened for hypothesis learning."
        case .invalidCandidate:
            "The review hypothesis is incomplete and cannot be learned."
        case let .candidateConflict(id):
            "A different learned hypothesis already uses candidate ID \(id)."
        case .encodeEvidence:
            "The review evidence could not be prepared for local storage."
        case .decodeEvidence:
            "The stored review evidence could not be read."
        case let .read(message):
            "The learned review hypothesis could not be read: \(message)"
        case let .write(message):
            "The learned review hypothesis could not be saved: \(message)"
        }
    }
}

public final class ReviewHypothesisPromotionStore: @unchecked Sendable {
    private let databaseURL: URL
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        databaseURL: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ReviewHypothesisPromotionStoreError.missingDatabase
        }
        self.databaseURL = databaseURL
        self.now = now
    }

    @discardableResult
    public func promote(
        candidateID: String,
        hypothesis: String,
        sourceDay: String,
        evidence: [String]
    ) throws -> Bool {
        let normalizedID = candidateID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHypothesis = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceDay = sourceDay.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEvidence = evidence
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedID.isEmpty,
              normalizedID.count <= 240,
              !normalizedHypothesis.isEmpty,
              normalizedHypothesis.count <= 2_000,
              !normalizedSourceDay.isEmpty,
              normalizedSourceDay.count <= 64,
              !normalizedEvidence.isEmpty else {
            throw ReviewHypothesisPromotionStoreError.invalidCandidate
        }

        lock.lock()
        defer { lock.unlock() }
        let database = try open(readOnly: false)
        defer { sqlite3_close(database) }

        if let existing = try read(candidateID: normalizedID, database: database) {
            guard existing.hypothesis == normalizedHypothesis,
                  existing.sourceDay == normalizedSourceDay,
                  existing.evidence == normalizedEvidence else {
                throw ReviewHypothesisPromotionStoreError.candidateConflict(normalizedID)
            }
            return false
        }

        let evidenceData: Data
        do {
            evidenceData = try JSONEncoder().encode(normalizedEvidence)
        } catch {
            throw ReviewHypothesisPromotionStoreError.encodeEvidence
        }
        var statement: OpaquePointer?
        let sql = """
        INSERT OR IGNORE INTO review_hypothesis_promotions(
            candidate_id, hypothesis, source_day, evidence_json, promoted_at_utc
        ) VALUES (?, ?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ReviewHypothesisPromotionStoreError.write(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        bind(normalizedID, statement, 1)
        bind(normalizedHypothesis, statement, 2)
        bind(normalizedSourceDay, statement, 3)
        _ = evidenceData.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
        }
        bind(Self.timestamp(now()), statement, 5)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ReviewHypothesisPromotionStoreError.write(errorMessage(database))
        }
        guard sqlite3_changes(database) == 0 else { return true }
        guard let existing = try read(candidateID: normalizedID, database: database),
              existing.hypothesis == normalizedHypothesis,
              existing.sourceDay == normalizedSourceDay,
              existing.evidence == normalizedEvidence else {
            throw ReviewHypothesisPromotionStoreError.candidateConflict(normalizedID)
        }
        return false
    }

    public func promotion(candidateID: String) throws -> StoredReviewHypothesisPromotion? {
        lock.lock()
        defer { lock.unlock() }
        let database = try open(readOnly: true)
        defer { sqlite3_close(database) }
        return try read(candidateID: candidateID, database: database)
    }

    private func read(
        candidateID: String,
        database: OpaquePointer
    ) throws -> StoredReviewHypothesisPromotion? {
        var statement: OpaquePointer?
        let sql = """
        SELECT hypothesis, source_day, evidence_json, promoted_at_utc
        FROM review_hypothesis_promotions
        WHERE candidate_id = ?
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ReviewHypothesisPromotionStoreError.read(errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }
        bind(candidateID, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let hypothesis = text(statement, 0),
              let sourceDay = text(statement, 1),
              let evidenceData = data(statement, 2),
              let promotedAtRaw = text(statement, 3),
              let promotedAt = ISO8601DateFormatter().date(from: promotedAtRaw) else {
            throw ReviewHypothesisPromotionStoreError.read("Stored fields are incomplete.")
        }
        let evidence: [String]
        do {
            evidence = try JSONDecoder().decode([String].self, from: evidenceData)
        } catch {
            throw ReviewHypothesisPromotionStoreError.decodeEvidence
        }
        return StoredReviewHypothesisPromotion(
            candidateID: candidateID,
            hypothesis: hypothesis,
            sourceDay: sourceDay,
            evidence: evidence,
            promotedAt: promotedAt
        )
    }

    private func open(readOnly: Bool) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw ReviewHypothesisPromotionStoreError.openDatabase
        }
        sqlite3_busy_timeout(database, 5_000)
        return database
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func data(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
