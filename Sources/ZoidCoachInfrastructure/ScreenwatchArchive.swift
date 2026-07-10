import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import ZoidCoachCore

public struct ScreenwatchIngestionResult: Equatable, Sendable {
    public let insertedCount: Int
    public let totalRecordsRead: Int

    public init(insertedCount: Int, totalRecordsRead: Int) {
        self.insertedCount = insertedCount
        self.totalRecordsRead = totalRecordsRead
    }
}

public struct MeetingAnalysisResult: Equatable, Sendable {
    public let screenshotsProcessed: Int
    public let candidatesCreated: Int

    public init(screenshotsProcessed: Int, candidatesCreated: Int) {
        self.screenshotsProcessed = screenshotsProcessed
        self.candidatesCreated = candidatesCreated
    }
}

public struct StoredMeetingCandidate: Equatable, Sendable, Identifiable {
    public let sourceDay: String
    public let epoch: Int
    public let title: String
    public let start: Date
    public let durationMinutes: Int
    public let confidence: MeetingCandidateConfidence
    public let requiresClarification: Bool
    public let state: String

    public var id: String { "\(sourceDay):\(epoch)" }
}

public final class ScreenwatchArchive: @unchecked Sendable {
    private let database: OpaquePointer
    private let decoder = ScreenwatchLogDecoder()

    public init(databaseURL: URL, readOnly: Bool = false) throws {
        if !readOnly { try AutonomousDatabaseMigrator(databaseURL: databaseURL).migrate() }
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let handle
        else { throw ScreenwatchArchiveError.openDatabase }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func ingestToday(from baseDirectory: URL, now: Date = Date()) throws -> ScreenwatchIngestionResult {
        let dayKey = Self.dayKey(for: now)
        let dayDirectory = baseDirectory.appendingPathComponent(dayKey, isDirectory: true)
        let logURL = dayDirectory.appendingPathComponent("log.jsonl", isDirectory: false)
        guard FileManager.default.fileExists(atPath: logURL.path) else { return ScreenwatchIngestionResult(insertedCount: 0, totalRecordsRead: 0) }

        let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileIdentity = String(describing: attributes[.systemFileNumber] ?? logURL.path)
        let sourceID = "screenwatch:\(logURL.path)"
        let checkpoint = try processingCheckpoint(sourceID: sourceID)
        let offset = checkpoint?.fileIdentity == fileIdentity && (checkpoint?.byteOffset ?? 0) <= fileSize
            ? checkpoint?.byteOffset ?? 0
            : 0
        let handle = try FileHandle(forReadingFrom: logURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        guard let appendedData = try handle.readToEnd(), !appendedData.isEmpty,
              let finalNewline = appendedData.lastIndex(of: 0x0A)
        else { return ScreenwatchIngestionResult(insertedCount: 0, totalRecordsRead: 0) }
        let completeData = appendedData.prefix(through: finalNewline)
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else { throw ScreenwatchArchiveError.insert }
        var committed = false
        defer { _ = sqlite3_exec(database, committed ? "COMMIT;" : "ROLLBACK;", nil, nil, nil) }
        var insertedCount = 0
        var totalRecordsRead = 0
        var lastEpoch: Int?
        for line in completeData.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let observation = try? decoder.decode(Data(line)) else { continue }
            totalRecordsRead += 1
            lastEpoch = observation.epoch
            if try insert(observation, dayKey: dayKey, dayDirectory: dayDirectory) {
                insertedCount += 1
                if let screenshotPath = screenshotPath(for: observation, in: dayDirectory) {
                    try indexScreenshot(path: screenshotPath, observation: observation, dayKey: dayKey, now: now)
                }
            }
        }
        try updateProcessingCheckpoint(
            sourceID: sourceID,
            fileIdentity: fileIdentity,
            byteOffset: offset + UInt64(completeData.count),
            lastRecordEpoch: lastEpoch,
            now: now
        )
        committed = true
        return ScreenwatchIngestionResult(insertedCount: insertedCount, totalRecordsRead: totalRecordsRead)
    }

    public func analyzePendingWhatsAppScreenshots(
        using recognizer: any ScreenshotTextRecognizing = ScreenshotTextRecognizer(),
        cipher: (any EvidenceCiphering)? = nil
    ) async throws -> MeetingAnalysisResult {
        let pending = try pendingWhatsAppScreenshots()
        let extractor = MeetingCandidateExtractor()
        var candidatesCreated = 0
        let evidenceCipher: any EvidenceCiphering
        if let cipher {
            evidenceCipher = cipher
        } else {
            evidenceCipher = try LocalEvidenceCipher()
        }

        for screenshot in pending {
            do {
                let result = try await recognizer.recognize(in: screenshot.path)
                let evidenceHash = try persistOCRResult(result, for: screenshot, cipher: evidenceCipher)
                try recordAnalysis(for: screenshot, outcome: "recognized")
                guard let candidate = extractor.extract(
                    from: result.text,
                    observedAt: Date(timeIntervalSince1970: TimeInterval(screenshot.epoch))
                ) else { continue }
                let insertion = try insert(candidate: candidate, source: screenshot)
                if insertion.inserted {
                    try linkMeetingEvidence(source: screenshot, evidenceHash: evidenceHash)
                }
                if insertion.shouldPrompt {
                    candidatesCreated += 1
                }
            } catch {
                try recordAnalysis(for: screenshot, outcome: "unreadable")
                try? updateScreenshotOCRState(artifactID: "\(screenshot.sourceDay):\(screenshot.epoch)", state: "unreadable")
            }
        }

        return MeetingAnalysisResult(screenshotsProcessed: pending.count, candidatesCreated: candidatesCreated)
    }

    public func unresolvedMeetingCandidates() throws -> [StoredMeetingCandidate] {
        let sql = """
        SELECT source_day, epoch, title, start_at, duration_minutes, confidence, requires_clarification, state
        FROM meeting_candidates
        WHERE state IN ('ready_for_confirmation', 'needs_clarification')
        ORDER BY start_at ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }

        let formatter = ISO8601DateFormatter()
        var candidates: [StoredMeetingCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceDay = columnText(statement, at: 0),
                  let title = columnText(statement, at: 2),
                  let startRaw = columnText(statement, at: 3),
                  let start = formatter.date(from: startRaw),
                  let confidenceRaw = columnText(statement, at: 5),
                  let confidence = confidence(from: confidenceRaw),
                  let state = columnText(statement, at: 7)
            else { continue }
            candidates.append(
                StoredMeetingCandidate(
                    sourceDay: sourceDay,
                    epoch: Int(sqlite3_column_int64(statement, 1)),
                    title: title,
                    start: start,
                    durationMinutes: Int(sqlite3_column_int(statement, 4)),
                    confidence: confidence,
                    requiresClarification: sqlite3_column_int(statement, 6) == 1,
                    state: state
                )
            )
        }
        return candidates
    }

    public func meetingCandidate(id: String) throws -> StoredMeetingCandidate? {
        guard let separator = id.lastIndex(of: ":"),
              let epoch = Int(id[id.index(after: separator)...])
        else { return nil }
        let sourceDay = String(id[..<separator])
        let sql = """
        SELECT source_day, epoch, title, start_at, duration_minutes, confidence, requires_clarification, state
        FROM meeting_candidates WHERE source_day = ? AND epoch = ? LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(epoch))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let title = columnText(statement, at: 2),
              let startRaw = columnText(statement, at: 3),
              let start = ISO8601DateFormatter().date(from: startRaw),
              let confidenceRaw = columnText(statement, at: 5),
              let confidence = confidence(from: confidenceRaw),
              let state = columnText(statement, at: 7)
        else { return nil }
        return StoredMeetingCandidate(
            sourceDay: sourceDay,
            epoch: epoch,
            title: title,
            start: start,
            durationMinutes: Int(sqlite3_column_int(statement, 4)),
            confidence: confidence,
            requiresClarification: sqlite3_column_int(statement, 6) == 1,
            state: state
        )
    }

    public func recentBehaviorEvidence(since: Date, limit: Int = 12) throws -> [PlanningBehaviorEvidence] {
        let sql = """
        SELECT app_name, COUNT(*) AS observation_count
        FROM behavior_records
        WHERE epoch >= ?
        GROUP BY app_name
        ORDER BY observation_count DESC, app_name ASC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970))
        sqlite3_bind_int(statement, 2, Int32(max(1, limit)))
        var evidence: [PlanningBehaviorEvidence] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let application = columnText(statement, at: 0) else { continue }
            evidence.append(PlanningBehaviorEvidence(application: application, observationCount: Int(sqlite3_column_int(statement, 1))))
        }
        return evidence
    }

    public func behaviorObservations(for day: Date, classifier: BehaviorClassifier = BehaviorClassifier()) throws -> [BehaviorObservation] {
        let interval = Calendar.current.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        let sql = "SELECT epoch, app_name FROM behavior_records WHERE epoch >= ? AND epoch < ? ORDER BY epoch ASC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(interval.start.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(interval.end.timeIntervalSince1970))
        var observations: [BehaviorObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let application = columnText(statement, at: 1) {
            observations.append(
                BehaviorObservation(
                    observedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                    application: application,
                    classification: classifier.classify(application: application)
                )
            )
        }
        return observations
    }

    public func updateMeetingCandidate(_ candidate: StoredMeetingCandidate, state: String) throws {
        let sql = "UPDATE meeting_candidates SET state = ? WHERE source_day = ? AND epoch = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind(state, to: statement, at: 1)
        bind(candidate.sourceDay, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, Int64(candidate.epoch))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func createSchema() throws {
        let schema = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS behavior_records (
            source_day TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            time_label TEXT NOT NULL,
            app_name TEXT NOT NULL,
            window_title TEXT NOT NULL,
            url TEXT NOT NULL,
            has_screenshot INTEGER NOT NULL,
            screenshot_path TEXT,
            ingested_at TEXT NOT NULL,
            PRIMARY KEY (source_day, epoch)
        );
        CREATE INDEX IF NOT EXISTS behavior_records_epoch ON behavior_records(epoch);
        CREATE TABLE IF NOT EXISTS screenshot_analyses (
            source_day TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            outcome TEXT NOT NULL,
            processed_at TEXT NOT NULL,
            PRIMARY KEY (source_day, epoch)
        );
        CREATE TABLE IF NOT EXISTS meeting_candidates (
            source_day TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            title TEXT NOT NULL,
            start_at TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            confidence TEXT NOT NULL,
            requires_clarification INTEGER NOT NULL,
            state TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (source_day, epoch)
        );
        CREATE INDEX IF NOT EXISTS meeting_candidates_start_at ON meeting_candidates(start_at);
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else { throw ScreenwatchArchiveError.createSchema }
    }

    private func insert(_ observation: ScreenwatchObservation, dayKey: String, dayDirectory: URL) throws -> Bool {
        let sql = "INSERT OR IGNORE INTO behavior_records (source_day, epoch, time_label, app_name, window_title, url, has_screenshot, screenshot_path, ingested_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }

        bind(dayKey, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(observation.epoch))
        bind(observation.timeLabel, to: statement, at: 3)
        bind(observation.appName, to: statement, at: 4)
        bind(observation.windowTitle, to: statement, at: 5)
        bind(observation.url, to: statement, at: 6)
        sqlite3_bind_int(statement, 7, observation.hasScreenshot ? 1 : 0)
        if let screenshotPath = screenshotPath(for: observation, in: dayDirectory) {
            bind(screenshotPath.path, to: statement, at: 8)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        bind(ISO8601DateFormatter().string(from: Date()), to: statement, at: 9)

        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
        return sqlite3_changes(database) == 1
    }

    private func indexScreenshot(path: URL, observation: ScreenwatchObservation, dayKey: String, now: Date) throws {
        let data = try Data(contentsOf: path, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fingerprint = perceptualFingerprint(data) ?? "sha256:\(String(digest.prefix(16)))"
        let retentionUntil = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(30 * 86_400)
        let sql = """
        INSERT OR IGNORE INTO screenshot_artifacts
        (id, behavior_day, behavior_epoch, path, content_hash, perceptual_fingerprint, ocr_state, extractor_version, retention_until_utc, created_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, 'pending', 1, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind("\(dayKey):\(observation.epoch)", to: statement, at: 1)
        bind(dayKey, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, Int64(observation.epoch))
        bind(path.path, to: statement, at: 4)
        bind(digest, to: statement, at: 5)
        bind(fingerprint, to: statement, at: 6)
        bind(ISO8601DateFormatter().string(from: retentionUntil), to: statement, at: 7)
        bind(ISO8601DateFormatter().string(from: now), to: statement, at: 8)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func perceptualFingerprint(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64)
        guard let context = CGContext(
            data: &pixels,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var bits: UInt64 = 0
        for pixel in pixels {
            bits = (bits << 1) | (Int(pixel) >= average ? 1 : 0)
        }
        return String(format: "ahash:%016llx", bits)
    }

    private func processingCheckpoint(sourceID: String) throws -> (fileIdentity: String?, byteOffset: UInt64)? {
        let sql = "SELECT file_identity, byte_offset FROM processing_checkpoints WHERE source_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let identity = sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : columnText(statement, at: 0)
        return (identity, UInt64(max(0, sqlite3_column_int64(statement, 1))))
    }

    private func updateProcessingCheckpoint(sourceID: String, fileIdentity: String, byteOffset: UInt64, lastRecordEpoch: Int?, now: Date) throws {
        let sql = """
        INSERT INTO processing_checkpoints
        (source_id, file_identity, byte_offset, last_record_epoch, last_success_at_utc, diagnostic)
        VALUES (?, ?, ?, ?, ?, NULL)
        ON CONFLICT(source_id) DO UPDATE SET
            file_identity = excluded.file_identity,
            byte_offset = excluded.byte_offset,
            last_record_epoch = COALESCE(excluded.last_record_epoch, processing_checkpoints.last_record_epoch),
            last_success_at_utc = excluded.last_success_at_utc,
            diagnostic = NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind(sourceID, to: statement, at: 1)
        bind(fileIdentity, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, Int64(byteOffset))
        if let lastRecordEpoch { sqlite3_bind_int64(statement, 4, Int64(lastRecordEpoch)) } else { sqlite3_bind_null(statement, 4) }
        bind(ISO8601DateFormatter().string(from: now), to: statement, at: 5)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func screenshotPath(for observation: ScreenwatchObservation, in dayDirectory: URL) -> URL? {
        guard observation.hasScreenshot else { return nil }
        for extensionName in ["webp", "jpg", "jpeg"] {
            let candidate = dayDirectory.appendingPathComponent("\(observation.timeLabel).\(extensionName)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func pendingWhatsAppScreenshots() throws -> [PendingScreenshot] {
        let sql = """
        SELECT record.source_day, record.epoch, record.screenshot_path
        FROM behavior_records AS record
        LEFT JOIN screenshot_analyses AS analysis
          ON analysis.source_day = record.source_day AND analysis.epoch = record.epoch
        WHERE LOWER(record.app_name) LIKE '%whatsapp%'
          AND record.screenshot_path IS NOT NULL
          AND analysis.epoch IS NULL
        ORDER BY record.epoch ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareRead }
        defer { sqlite3_finalize(statement) }

        var screenshots: [PendingScreenshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sourceDay = columnText(statement, at: 0),
                  let screenshotPath = columnText(statement, at: 2)
            else { continue }
            screenshots.append(
                PendingScreenshot(
                    sourceDay: sourceDay,
                    epoch: Int(sqlite3_column_int64(statement, 1)),
                    path: URL(fileURLWithPath: screenshotPath)
                )
            )
        }
        return screenshots
    }

    private func recordAnalysis(for screenshot: PendingScreenshot, outcome: String) throws {
        let sql = "INSERT OR REPLACE INTO screenshot_analyses (source_day, epoch, outcome, processed_at) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind(screenshot.sourceDay, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(screenshot.epoch))
        bind(outcome, to: statement, at: 3)
        bind(ISO8601DateFormatter().string(from: Date()), to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func persistOCRResult(_ result: ScreenshotOCRResult, for screenshot: PendingScreenshot, cipher: any EvidenceCiphering) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let plaintext = try encoder.encode(result)
        let encrypted = try cipher.encrypt(plaintext)
        let evidenceHash = SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined()
        let artifactID = "\(screenshot.sourceDay):\(screenshot.epoch)"
        let sql = """
        INSERT OR REPLACE INTO extracted_facts
        (id, artifact_id, fact_type, schema_version, confidence, encrypted_payload, evidence_hash, created_at_utc)
        VALUES (?, ?, 'ocr_text_blocks', ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind("ocr:\(artifactID):v\(result.recognizerVersion)", to: statement, at: 1)
        bind(artifactID, to: statement, at: 2)
        sqlite3_bind_int(statement, 3, Int32(result.recognizerVersion))
        sqlite3_bind_double(statement, 4, result.averageConfidence)
        _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(encrypted.count), SQLITE_TRANSIENT) }
        bind(evidenceHash, to: statement, at: 6)
        bind(ISO8601DateFormatter().string(from: Date()), to: statement, at: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
        try updateScreenshotOCRState(artifactID: artifactID, state: "recognized")
        return evidenceHash
    }

    private func updateScreenshotOCRState(artifactID: String, state: String) throws {
        let sql = "UPDATE screenshot_artifacts SET ocr_state = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind(state, to: statement, at: 1)
        bind(artifactID, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func linkMeetingEvidence(source: PendingScreenshot, evidenceHash: String) throws {
        let sql = "INSERT OR IGNORE INTO meeting_evidence(candidate_id, artifact_id, evidence_hash) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        let identifier = "\(source.sourceDay):\(source.epoch)"
        bind(identifier, to: statement, at: 1)
        bind(identifier, to: statement, at: 2)
        bind(evidenceHash, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func insert(candidate: MeetingCandidate, source: PendingScreenshot) throws -> (inserted: Bool, shouldPrompt: Bool) {
        let policy = MeetingCandidatePolicy()
        let fingerprint = policy.fingerprint(candidate)
        let state: String
        if candidate.requiresClarification || candidate.confidenceScore < policy.readyThreshold {
            state = candidate.confidenceScore >= policy.editableThreshold ? "needs_clarification" : "low_confidence"
        } else {
            state = "ready_for_confirmation"
        }
        let sql = """
        INSERT OR IGNORE INTO meeting_candidates
        (source_day, epoch, title, start_at, duration_minutes, confidence, confidence_score, requires_clarification, state, created_at,
         candidate_fingerprint, participants_json, start_expression, location, call_link, timezone_identifier, expires_at_utc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }

        bind(source.sourceDay, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(source.epoch))
        bind(candidate.title, to: statement, at: 3)
        bind(ISO8601DateFormatter().string(from: candidate.start), to: statement, at: 4)
        sqlite3_bind_int(statement, 5, Int32(candidate.durationMinutes))
        bind(String(describing: candidate.confidence), to: statement, at: 6)
        sqlite3_bind_double(statement, 7, candidate.confidenceScore)
        sqlite3_bind_int(statement, 8, candidate.requiresClarification ? 1 : 0)
        bind(state, to: statement, at: 9)
        bind(ISO8601DateFormatter().string(from: Date()), to: statement, at: 10)
        bind(fingerprint, to: statement, at: 11)
        bind(String(decoding: try JSONEncoder().encode(candidate.participants), as: UTF8.self), to: statement, at: 12)
        bind(candidate.startExpression, to: statement, at: 13)
        if let location = candidate.location { bind(location, to: statement, at: 14) } else { sqlite3_bind_null(statement, 14) }
        if let callLink = candidate.callLink { bind(callLink, to: statement, at: 15) } else { sqlite3_bind_null(statement, 15) }
        bind(candidate.timezoneIdentifier, to: statement, at: 16)
        bind(ISO8601DateFormatter().string(from: candidate.start), to: statement, at: 17)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
        let inserted = sqlite3_changes(database) == 1
        try appendMeetingAudit(
            type: inserted ? "meeting_candidate.\(state)" : "meeting_candidate.duplicate_suppressed",
            candidateID: "\(source.sourceDay):\(source.epoch)",
            sourceDay: source.sourceDay,
            fingerprint: fingerprint
        )
        return (inserted, inserted && state != "low_confidence")
    }

    private func appendMeetingAudit(type: String, candidateID: String, sourceDay: String, fingerprint: String) throws {
        let sql = """
        INSERT INTO domain_events
        (id, event_type, entity_id, local_day, timezone_identifier, occurred_at_utc, schema_version, evidence_ids_json, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, 1, '[]', ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ScreenwatchArchiveError.prepareInsert }
        defer { sqlite3_finalize(statement) }
        bind(UUID().uuidString, to: statement, at: 1)
        bind(type, to: statement, at: 2)
        bind(candidateID, to: statement, at: 3)
        bind(sourceDay, to: statement, at: 4)
        bind(TimeZone.current.identifier, to: statement, at: 5)
        bind(ISO8601DateFormatter().string(from: Date()), to: statement, at: 6)
        bind("{\"fingerprint\":\"\(fingerprint)\"}", to: statement, at: 7)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw ScreenwatchArchiveError.insert }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private func confidence(from value: String) -> MeetingCandidateConfidence? {
        switch value {
        case "high": .high
        case "medium": .medium
        case "low": .low
        default: nil
        }
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct PendingScreenshot: Sendable {
    let sourceDay: String
    let epoch: Int
    let path: URL
}

public enum ScreenwatchArchiveError: LocalizedError {
    case openDatabase
    case createSchema
    case prepareInsert
    case prepareRead
    case insert

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "Could not open the local Zoid Coach database"
        case .createSchema: "Could not initialize behavior-record storage"
        case .prepareInsert: "Could not prepare behavior-record storage"
        case .prepareRead: "Could not read pending screenshot analysis"
        case .insert: "Could not persist a behavior record"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
