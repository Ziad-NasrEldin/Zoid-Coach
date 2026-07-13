import Foundation
import SQLite3
import ZoidCoachCore

public final class DailyReviewStore: @unchecked Sendable {
    private struct Correction {
        let startEpoch: Int64
        let endEpoch: Int64
        let classification: BehaviorClassification
        let taskID: String?
    }

    private let database: OpaquePointer
    private let taskHistory: TaskHistoryStore
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate()
        taskHistory = try TaskHistoryStore(databaseURL: databaseURL)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw DailyReviewStoreError.openDatabase
        }
        database = handle
        self.now = now
        self.timeZone = timeZone
        sqlite3_busy_timeout(database, 5_000)
    }

    deinit { sqlite3_close(database) }

    public func load(sourceDay: String) throws -> DailyReviewSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let corrections = try readCorrections(sourceDay: sourceDay)
        let observations = try readObservations(sourceDay: sourceDay, corrections: corrections)
        let sessions = DailyReviewSessionizer.sessions(from: observations)
        let totals = DailyReviewSessionizer.totals(for: sessions)
        let state = try readReviewState(sourceDay: sourceDay)
        let offlineWork = try readOfflineWork(sourceDay: sourceDay)
        let completedTasks = try completedTasks(sourceDay: sourceDay)
        let plannedTasks = try plannedTasks(sourceDay: sourceDay, completedTasks: completedTasks)
        let coachingInteractions = try coachingInteractions(sourceDay: sourceDay)
        return DailyReviewSnapshot(
            sourceDay: sourceDay,
            sessions: sessions,
            totals: totals,
            hypothesis: Self.hypothesis(for: totals),
            hypothesisState: state.hypothesisState,
            confirmedAt: state.confirmedAt,
            offlineWork: offlineWork,
            completedTasks: completedTasks,
            plannedTasks: plannedTasks,
            coachingInteractions: coachingInteractions
        )
    }

    private func coachingInteractions(sourceDay: String) throws -> [DailyReviewCoachingInteraction] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        guard let dayStart = dayFormatter.date(from: sourceDay),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return [] }

        var statement: OpaquePointer?
        let sql = """
        SELECT episode.id,
               episode.prompt_type,
               episode.title,
               episode.summary,
               episode.created_at_utc,
               response.response,
               response.surface,
               response.responded_at_utc,
               effect.state
        FROM prompt_episodes episode
        LEFT JOIN prompt_responses response ON response.prompt_id = episode.id
        LEFT JOIN prompt_response_effects effect ON effect.response_id = response.id
        WHERE episode.prompt_type IN ('GAMING_DRIFT', 'WAKE_INTERVENTION')
          AND episode.created_at_utc >= ?
          AND episode.created_at_utc < ?
        ORDER BY episode.created_at_utc ASC, episode.id ASC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(Self.timestamp(dayStart), statement, 1)
        bind(Self.timestamp(dayEnd), statement, 2)
        let formatter = ISO8601DateFormatter()
        var interactions: [DailyReviewCoachingInteraction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let promptID = text(statement, 0),
                  let promptType = text(statement, 1),
                  let title = text(statement, 2),
                  let summary = text(statement, 3),
                  let createdAt = text(statement, 4).flatMap(formatter.date(from:))
            else { continue }
            let responseAction = text(statement, 5)
            interactions.append(DailyReviewCoachingInteraction(
                promptID: promptID,
                promptType: promptType,
                title: title,
                summary: summary,
                createdAt: createdAt,
                responseAction: responseAction,
                responseSurface: text(statement, 6),
                respondedAt: text(statement, 7).flatMap(formatter.date(from:)),
                effectWasApplied: responseAction.map { _ in text(statement, 8) == "applied" }
            ))
        }
        return interactions
    }

    private func plannedTasks(
        sourceDay: String,
        completedTasks: [CompletedTaskHistoryEntry]
    ) throws -> [DailyReviewPlannedTaskOutcome] {
        let completedByID = Dictionary(completedTasks.map { ($0.taskID, $0) }, uniquingKeysWith: { first, _ in first })
        var statement: OpaquePointer?
        let sql = """
        SELECT plan.reminder_id,
               COALESCE(NULLIF(source.title, ''), plan.reminder_id),
               plan.is_main_objective,
               plan.estimate_minutes
        FROM daily_plan_entries plan
        LEFT JOIN source_tasks source ON source.source_id = plan.reminder_id
        WHERE plan.day_key = ?
          AND COALESCE(plan.is_optional, 0) = 0
        ORDER BY plan.is_main_objective DESC, plan.rank ASC, plan.reminder_id ASC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var outcomes: [DailyReviewPlannedTaskOutcome] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let taskID = text(statement, 0) else { continue }
            let sourceTitle = text(statement, 1) ?? taskID
            let completed = completedByID[taskID]
            outcomes.append(DailyReviewPlannedTaskOutcome(
                taskID: taskID,
                title: completed?.title ?? sourceTitle,
                isMainObjective: sqlite3_column_int(statement, 2) != 0,
                estimatedMinutes: sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : Int(sqlite3_column_int64(statement, 3)),
                isCompleted: completed != nil
            ))
        }
        return outcomes
    }

    private func completedTasks(sourceDay: String) throws -> [CompletedTaskHistoryEntry] {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: sourceDay) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try taskHistory.completedEntries(for: date, calendar: calendar)
    }

    @discardableResult
    public func saveOfflineWork(
        id: String? = nil,
        sourceDay: String,
        taskID: String?,
        startedAt: Date,
        durationMinutes: Int,
        note: String?
    ) throws -> String {
        guard (1...1_440).contains(durationMinutes) else {
            throw DailyReviewStoreError.invalidOfflineDuration
        }
        let entryID = id ?? UUID().uuidString
        let normalizedTaskID = Self.normalized(taskID)
        let normalizedNote = Self.normalized(note)
        guard normalizedTaskID != nil || normalizedNote != nil else {
            throw DailyReviewStoreError.missingOfflineWorkDescription
        }
        guard (normalizedTaskID?.count ?? 0) <= 200,
              (normalizedNote?.count ?? 0) <= 1_000 else {
            throw DailyReviewStoreError.offlineWorkDescriptionTooLong
        }
        let timestamp = Self.timestamp(now())
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try execute(
                """
                INSERT INTO offline_work_entries(id, source_day, task_id, started_at_utc, duration_minutes, note, created_at_utc, updated_at_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source_day = excluded.source_day,
                    task_id = excluded.task_id,
                    started_at_utc = excluded.started_at_utc,
                    duration_minutes = excluded.duration_minutes,
                    note = excluded.note,
                    updated_at_utc = excluded.updated_at_utc;
                """,
                bindings: [
                    .text(entryID),
                    .text(sourceDay),
                    normalizedTaskID.map(Binding.text) ?? .null,
                    .text(Self.timestamp(startedAt)),
                    .integer(Int64(durationMinutes)),
                    normalizedNote.map(Binding.text) ?? .null,
                    .text(timestamp),
                    .text(timestamp)
                ]
            )
            try reopenReview(sourceDay: sourceDay, timestamp: timestamp)
        }
        return entryID
    }

    public func deleteOfflineWork(id: String, sourceDay: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = Self.timestamp(now())
        try transaction {
            try execute(
                "DELETE FROM offline_work_entries WHERE id = ? AND source_day = ?;",
                bindings: [.text(id), .text(sourceDay)]
            )
            try reopenReview(sourceDay: sourceDay, timestamp: timestamp)
        }
    }

    public func correct(
        _ session: DailyReviewSession,
        to classification: BehaviorClassification,
        taskID: String? = nil,
        from splitDate: Date? = nil,
        applyToFuture: Bool = false
    ) throws {
        let start = max(session.start, splitDate ?? session.start)
        guard start < session.end else { throw DailyReviewStoreError.invalidCorrectionRange }
        if applyToFuture {
            try Self.validateFutureRule(session: session, classification: classification)
        }
        let normalizedTaskID = taskID?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        try transaction {
            try execute(
                "INSERT INTO daily_review_corrections(id, source_day, start_epoch, end_epoch, classification, task_id, created_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?);",
                bindings: [
                    .text(UUID().uuidString),
                    .text(session.sourceDay),
                    .integer(Int64(start.timeIntervalSince1970)),
                    .integer(Int64(session.end.timeIntervalSince1970)),
                    .text(classification.rawValue),
                    normalizedTaskID.flatMap { $0.isEmpty ? nil : .text($0) } ?? .null,
                    .text(Self.timestamp(now()))
                ]
            )
            try execute(
                "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, 'pending', NULL, ?) ON CONFLICT(source_day) DO UPDATE SET hypothesis_state = 'pending', confirmed_at_utc = NULL, updated_at_utc = excluded.updated_at_utc;",
                bindings: [.text(session.sourceDay), .text(Self.timestamp(now()))]
            )
            if applyToFuture {
                _ = try insertClassificationRule(for: session, classification: classification)
            }
        }
    }

    public func classificationRules() throws -> [AppClassificationCorrectionRule] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        let sql = """
        SELECT rule.display_app, rule.normalized_app, rule.classification, rule.source_day,
               rule.source_session_start_epoch, rule.created_at_utc
        FROM app_classification_correction_rules rule
        WHERE rule.state = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM app_classification_correction_rules newer
              WHERE newer.normalized_app = rule.normalized_app
                AND (newer.effective_from_epoch > rule.effective_from_epoch
                  OR (newer.effective_from_epoch = rule.effective_from_epoch AND newer.id > rule.id))
          )
        ORDER BY rule.effective_from_epoch DESC, rule.normalized_app;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        var rules: [AppClassificationCorrectionRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let application = text(statement, 0),
                  let normalizedApplication = text(statement, 1),
                  let rawClassification = text(statement, 2),
                  let classification = BehaviorClassification(rawValue: rawClassification),
                  let sourceDay = text(statement, 3),
                  let createdAt = text(statement, 5).flatMap(ISO8601DateFormatter().date(from:))
            else { continue }
            rules.append(AppClassificationCorrectionRule(
                application: application,
                normalizedApplication: normalizedApplication,
                classification: classification,
                sourceDay: sourceDay,
                sourceSessionStart: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4))),
                createdAt: createdAt,
                updatedAt: createdAt
            ))
        }
        if sqlite3_errcode(database) != SQLITE_OK && sqlite3_errcode(database) != SQLITE_DONE {
            throw databaseError(.read)
        }
        return rules
    }

    @discardableResult
    public func upsertClassificationRule(
        for session: DailyReviewSession,
        classification: BehaviorClassification
    ) throws -> AppClassificationCorrectionRule {
        try Self.validateFutureRule(session: session, classification: classification)
        lock.lock()
        defer { lock.unlock() }
        return try insertClassificationRule(for: session, classification: classification)
    }

    private func insertClassificationRule(
        for session: DailyReviewSession,
        classification: BehaviorClassification
    ) throws -> AppClassificationCorrectionRule {
        let normalizedApplication = BehaviorPolicy.normalize(session.application)
        let effectiveDate = now()
        let timestamp = Self.timestamp(effectiveDate)
        let effectiveFrom = Int64(effectiveDate.timeIntervalSince1970)
        try execute(
            """
            INSERT INTO app_classification_correction_rules(
                normalized_app, display_app, classification, state, source_day,
                source_session_start_epoch, effective_from_epoch, created_at_utc
            ) VALUES (?, ?, ?, 'active', ?, ?, ?, ?);
            """,
            bindings: [
                .text(normalizedApplication),
                .text(session.application),
                .text(classification.rawValue),
                .text(session.sourceDay),
                .integer(Int64(session.start.timeIntervalSince1970)),
                .integer(effectiveFrom),
                .text(timestamp)
            ]
        )
        return AppClassificationCorrectionRule(
            application: session.application,
            normalizedApplication: normalizedApplication,
            classification: classification,
            sourceDay: session.sourceDay,
            sourceSessionStart: session.start,
            createdAt: effectiveDate,
            updatedAt: effectiveDate
        )
    }

    private static func validateFutureRule(
        session: DailyReviewSession,
        classification: BehaviorClassification
    ) throws {
        guard [.work, .gaming, .distracting].contains(classification) else {
            throw DailyReviewStoreError.invalidFutureRuleClassification
        }
        guard !BehaviorPolicy.normalize(session.application).isEmpty else {
            throw DailyReviewStoreError.invalidFutureRuleApplication
        }
    }

    public func removeClassificationRule(normalizedApplication: String) throws {
        let normalized = BehaviorPolicy.normalize(normalizedApplication)
        guard !normalized.isEmpty else {
            throw DailyReviewStoreError.invalidFutureRuleApplication
        }
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT display_app FROM app_classification_correction_rules
            WHERE normalized_app = ? AND state = 'active'
              AND NOT EXISTS (
                  SELECT 1 FROM app_classification_correction_rules newer
                  WHERE newer.normalized_app = app_classification_correction_rules.normalized_app
                    AND (newer.effective_from_epoch > app_classification_correction_rules.effective_from_epoch
                      OR (newer.effective_from_epoch = app_classification_correction_rules.effective_from_epoch
                        AND newer.id > app_classification_correction_rules.id))
              )
            ORDER BY effective_from_epoch DESC, id DESC LIMIT 1;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(normalized, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let application = text(statement, 0) else { return }
        let removalDate = now()
        try execute(
            """
            INSERT INTO app_classification_correction_rules(
                normalized_app, display_app, classification, state, source_day,
                source_session_start_epoch, effective_from_epoch, created_at_utc
            ) VALUES (?, ?, NULL, 'removed', NULL, NULL, ?, ?);
            """,
            bindings: [
                .text(normalized),
                .text(application),
                .integer(Int64(removalDate.timeIntervalSince1970)),
                .text(Self.timestamp(removalDate))
            ]
        )
    }

    @discardableResult
    public func resetClassificationRules() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(.write)
        }
        var shouldCommit = false
        defer {
            if !shouldCommit {
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            }
        }
        let removalDate = now()
        try execute(
            """
            INSERT INTO app_classification_correction_rules(
                normalized_app, display_app, classification, state, source_day,
                source_session_start_epoch, effective_from_epoch, created_at_utc
            )
            SELECT rule.normalized_app, rule.display_app, NULL, 'removed', NULL, NULL, ?, ?
            FROM app_classification_correction_rules rule
            WHERE rule.state = 'active'
              AND NOT EXISTS (
                  SELECT 1 FROM app_classification_correction_rules newer
                  WHERE newer.normalized_app = rule.normalized_app
                    AND (newer.effective_from_epoch > rule.effective_from_epoch
                      OR (newer.effective_from_epoch = rule.effective_from_epoch
                        AND newer.id > rule.id))
              );
            """,
            bindings: [
                .integer(Int64(removalDate.timeIntervalSince1970)),
                .text(Self.timestamp(removalDate))
            ]
        )
        let removed = Int(sqlite3_changes(database))
        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(.write)
        }
        shouldCommit = true
        return removed
    }

    public func setHypothesisState(_ state: DailyReviewHypothesisState, sourceDay: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute(
            "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, ?, NULL, ?) ON CONFLICT(source_day) DO UPDATE SET hypothesis_state = excluded.hypothesis_state, confirmed_at_utc = NULL, updated_at_utc = excluded.updated_at_utc;",
            bindings: [.text(sourceDay), .text(state.rawValue), .text(Self.timestamp(now()))]
        )
    }

    public func confirm(sourceDay: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = Self.timestamp(now())
        try execute(
            "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, 'pending', ?, ?) ON CONFLICT(source_day) DO UPDATE SET confirmed_at_utc = excluded.confirmed_at_utc, updated_at_utc = excluded.updated_at_utc;",
            bindings: [.text(sourceDay), .text(timestamp), .text(timestamp)]
        )
    }

    private func readObservations(
        sourceDay: String,
        corrections: [Correction]
    ) throws -> [DailyReviewSessionizer.Observation] {
        var statement: OpaquePointer?
        let sql = "SELECT epoch, app_name, classification FROM behavior_records WHERE source_day = ? ORDER BY epoch ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var result: [DailyReviewSessionizer.Observation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let epoch = sqlite3_column_int64(statement, 0)
            guard let appPointer = sqlite3_column_text(statement, 1) else { continue }
            let stored = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let correction = corrections.last { epoch >= $0.startEpoch && epoch < $0.endEpoch }
            let classification = correction?.classification
                ?? stored.flatMap(BehaviorClassification.init(rawValue:))
                ?? .unknown
            result.append(.init(
                sourceDay: sourceDay,
                observedAt: Date(timeIntervalSince1970: TimeInterval(epoch)),
                application: String(cString: appPointer),
                classification: classification,
                taskID: correction?.taskID
            ))
        }
        if sqlite3_errcode(database) != SQLITE_OK && sqlite3_errcode(database) != SQLITE_DONE {
            throw databaseError(.read)
        }
        return result
    }

    private func readCorrections(sourceDay: String) throws -> [Correction] {
        var statement: OpaquePointer?
        let sql = "SELECT start_epoch, end_epoch, classification, task_id FROM daily_review_corrections WHERE source_day = ? ORDER BY created_at_utc ASC, rowid ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var result: [Correction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawPointer = sqlite3_column_text(statement, 2),
                  let classification = BehaviorClassification(rawValue: String(cString: rawPointer)) else { continue }
            result.append(Correction(
                startEpoch: sqlite3_column_int64(statement, 0),
                endEpoch: sqlite3_column_int64(statement, 1),
                classification: classification,
                taskID: sqlite3_column_text(statement, 3).map { String(cString: $0) }
            ))
        }
        return result
    }

    private func readOfflineWork(sourceDay: String) throws -> [OfflineWorkEntry] {
        var statement: OpaquePointer?
        let sql = "SELECT id, task_id, started_at_utc, duration_minutes, note, created_at_utc, updated_at_utc FROM offline_work_entries WHERE source_day = ? ORDER BY started_at_utc, id;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        var entries: [OfflineWorkEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(statement, 0),
                  let started = text(statement, 2).flatMap(ISO8601DateFormatter().date(from:)),
                  let created = text(statement, 5).flatMap(ISO8601DateFormatter().date(from:)),
                  let updated = text(statement, 6).flatMap(ISO8601DateFormatter().date(from:)) else { continue }
            entries.append(OfflineWorkEntry(
                id: id,
                sourceDay: sourceDay,
                taskID: text(statement, 1),
                startedAt: started,
                durationMinutes: Int(sqlite3_column_int(statement, 3)),
                note: text(statement, 4),
                createdAt: created,
                updatedAt: updated
            ))
        }
        return entries
    }

    private func reopenReview(sourceDay: String, timestamp: String) throws {
        try execute(
            "INSERT INTO daily_reviews(source_day, hypothesis_state, confirmed_at_utc, updated_at_utc) VALUES (?, 'pending', NULL, ?) ON CONFLICT(source_day) DO UPDATE SET confirmed_at_utc = NULL, updated_at_utc = excluded.updated_at_utc;",
            bindings: [.text(sourceDay), .text(timestamp)]
        )
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func readReviewState(sourceDay: String) throws -> (
        hypothesisState: DailyReviewHypothesisState,
        confirmedAt: Date?
    ) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT hypothesis_state, confirmed_at_utc FROM daily_reviews WHERE source_day = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError(.read) }
        defer { sqlite3_finalize(statement) }
        bind(sourceDay, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return (.pending, nil) }
        let rawState = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "pending"
        let confirmed = sqlite3_column_text(statement, 1)
            .map { String(cString: $0) }
            .flatMap(ISO8601DateFormatter().date(from:))
        return (DailyReviewHypothesisState(rawValue: rawState) ?? .pending, confirmed)
    }

    private static func hypothesis(for totals: [DailyReviewTotal]) -> String? {
        guard !totals.isEmpty else { return nil }
        let work = totals.first { $0.classification == .work }?.minutes ?? 0
        let drift = totals
            .filter { $0.classification == .gaming || $0.classification == .distracting }
            .reduce(0) { $0 + $1.minutes }
        if drift > work {
            return "Observed gaming and distracting time exceeded observed work time. This may indicate that the planned work was difficult to start."
        }
        return "Observed work time was the largest covered category. This may indicate that today’s plan matched the available capacity."
    }

    private enum Binding {
        case text(String)
        case integer(Int64)
        case null
    }

    private func execute(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError(.write) }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            switch value {
            case let .text(text): bind(text, statement, Int32(offset + 1))
            case let .integer(integer): sqlite3_bind_int64(statement, Int32(offset + 1), integer)
            case .null: sqlite3_bind_null(statement, Int32(offset + 1))
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError(.write) }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(.write)
        }
        do {
            try operation()
            guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw databaseError(.write)
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func databaseError(_ operation: DailyReviewStoreError.Operation) -> DailyReviewStoreError {
        DailyReviewStoreError.database(operation, String(cString: sqlite3_errmsg(database)))
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

public enum DailyReviewStoreError: LocalizedError {
    public enum Operation: String, Sendable { case read, write }
    case openDatabase
    case invalidCorrectionRange
    case invalidOfflineDuration
    case missingOfflineWorkDescription
    case offlineWorkDescriptionTooLong
    case invalidFutureRuleClassification
    case invalidFutureRuleApplication
    case database(Operation, String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase:
            "The local review database could not be opened."
        case .invalidCorrectionRange:
            "The selected split point does not leave any activity to correct."
        case .invalidOfflineDuration:
            "Away-from-Mac work must be between 1 minute and 24 hours."
        case .missingOfflineWorkDescription:
            "Add a task or a short note so this intentional work can be distinguished from missing telemetry."
        case .offlineWorkDescriptionTooLong:
            "Keep the task under 200 characters and the note under 1,000 characters."
        case .invalidFutureRuleClassification:
            "Future app rules can be Work, Gaming, or Distracting. Idle and Unknown remain observation states."
        case .invalidFutureRuleApplication:
            "This activity does not include an application name that can become a future rule."
        case let .database(operation, detail):
            "The daily review could not \(operation.rawValue) local data. \(detail)"
        }
    }
}

private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
}
