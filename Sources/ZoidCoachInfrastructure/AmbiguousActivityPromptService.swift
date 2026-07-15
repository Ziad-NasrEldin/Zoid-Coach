import Foundation
import SQLite3
import ZoidCoachCore

private let ambiguousSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum AmbiguousActivityPromptSuppressionReason: Equatable, Sendable {
    case noCurrentAmbiguity
    case staleEvidence
    case noActiveTask
    case belowMaterialThreshold
    case alreadyHandled
}

public enum AmbiguousActivityPromptResult: Equatable, Sendable {
    case suppressed(AmbiguousActivityPromptSuppressionReason)
    case queued(PromptEpisode, wasInserted: Bool)
}

public enum AmbiguousActivityResponseEffect: Equatable, Sendable {
    case none
    case classified(promptID: String, classification: BehaviorClassification, taskID: String?)
    case keptUnknown(promptID: String)
}

/// Creates one factual, optional confirmation only after ambiguity has overlapped
/// an actively tracked task for long enough to change coaching decisions.
public final class AmbiguousActivityPromptService: @unchecked Sendable {
    public static let promptType = "AMBIGUOUS_ACTIVITY"
    public static let materialThresholdMinutes = 10

    private struct ObservationSession {
        let sourceDay: String
        let startEpoch: Int64
        let latestEpoch: Int64
        let application: String
        let observationCount: Int
    }

    private struct ActiveTask {
        let id: String
        let title: String
        let startedAtEpoch: Int64
    }

    private let database: OpaquePointer
    private let prompts: PromptInboxStore
    private let reviews: DailyReviewStore
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        promptStore: PromptInboxStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        try AutonomousDatabaseMigrator(databaseURL: databaseURL, now: now).migrate()
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw AmbiguousActivityPromptServiceError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        prompts = promptStore
        reviews = try DailyReviewStore(databaseURL: databaseURL, now: now)
        self.now = now
    }

    deinit { sqlite3_close(database) }

    public func produce() throws -> AmbiguousActivityPromptResult {
        guard let session = try currentUnknownSession() else {
            return .suppressed(.noCurrentAmbiguity)
        }
        guard now().timeIntervalSince1970 - Double(session.latestEpoch) <= 180 else {
            return .suppressed(.staleEvidence)
        }
        guard let task = try activeTask() else {
            return .suppressed(.noActiveTask)
        }
        let materialStart = max(session.startEpoch, task.startedAtEpoch)
        let materialSeconds = session.latestEpoch - materialStart + 60
        guard materialSeconds >= Int64(Self.materialThresholdMinutes * 60) else {
            return .suppressed(.belowMaterialThreshold)
        }

        let decisionKey = "ambiguous-activity:\(session.sourceDay):\(session.startEpoch):\(task.id)"
        guard try !hasPrompt(decisionKey: decisionKey) else {
            return .suppressed(.alreadyHandled)
        }
        let minutes = max(1, Int(materialSeconds / 60))
        let application = session.application.isEmpty ? "an unidentified application" : session.application
        let result = try prompts.enqueue(PromptDraft(
            decisionKey: decisionKey,
            type: Self.promptType,
            title: "Did this support \(task.title)?",
            summary: "Zoid 666 observed about \(minutes) minutes in \(application) while \(task.title) was active. Application and duration alone cannot show your intent. Confirm only if useful, or keep it unknown without changing coaching.",
            actions: [
                PromptAction(kind: .classifyAsSupportingWork, title: "It supported \(task.title)", role: .primary),
                PromptAction(kind: .classifyAsGaming, title: "It was gaming"),
                PromptAction(kind: .keepActivityUnknown, title: "Keep it unknown")
            ],
            payload: [
                "sourceDay": session.sourceDay,
                "sessionStartEpoch": String(session.startEpoch),
                "sessionEndEpoch": String(session.latestEpoch + 60),
                "observationCount": String(session.observationCount),
                "application": application,
                "taskID": task.id,
                "taskTitle": task.title,
                "allowsDismissal": "true"
            ],
            expiresAt: now().addingTimeInterval(30 * 60)
        ))
        return .queued(result.episode, wasInserted: result.wasInserted)
    }

    public func apply(_ result: PromptResponseResult) throws -> AmbiguousActivityResponseEffect {
        guard result.wasApplied, result.episode.type == Self.promptType else { return .none }
        switch result.response.action {
        case .keepActivityUnknown:
            return .keptUnknown(promptID: result.episode.id)
        case .classifyAsSupportingWork, .classifyAsGaming:
            guard let session = Self.session(from: result.episode) else {
                throw AmbiguousActivityPromptServiceError.invalidPromptPayload
            }
            let classification: BehaviorClassification = result.response.action == .classifyAsSupportingWork
                ? .work
                : .gaming
            let taskID = classification == .work ? result.episode.payload["taskID"] : nil
            try reviews.correct(session, to: classification, taskID: taskID)
            return .classified(
                promptID: result.episode.id,
                classification: classification,
                taskID: taskID
            )
        default:
            return .none
        }
    }

    private static func session(from episode: PromptEpisode) -> DailyReviewSession? {
        guard let sourceDay = episode.payload["sourceDay"],
              let startRaw = episode.payload["sessionStartEpoch"], let startEpoch = Int64(startRaw),
              let endRaw = episode.payload["sessionEndEpoch"], let endEpoch = Int64(endRaw),
              let countRaw = episode.payload["observationCount"], let count = Int(countRaw),
              endEpoch > startEpoch, count > 0
        else { return nil }
        let application = episode.payload["application"] ?? "Unidentified application"
        return DailyReviewSession(
            sourceDay: sourceDay,
            start: Date(timeIntervalSince1970: TimeInterval(startEpoch)),
            end: Date(timeIntervalSince1970: TimeInterval(endEpoch)),
            application: application,
            classification: .unknown,
            observationCount: count
        )
    }

    private func currentUnknownSession() throws -> ObservationSession? {
        var statement: OpaquePointer?
        let sql = """
        SELECT behavior.source_day, behavior.epoch, behavior.app_name,
               COALESCE(
                   (SELECT correction.classification
                    FROM daily_review_corrections correction
                    WHERE correction.source_day = behavior.source_day
                      AND behavior.epoch >= correction.start_epoch
                      AND behavior.epoch < correction.end_epoch
                    ORDER BY correction.created_at_utc DESC, correction.rowid DESC LIMIT 1),
                   behavior.classification,
                   'unknown'
               )
        FROM behavior_records behavior
        ORDER BY behavior.epoch DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }

        var rows: [(day: String, epoch: Int64, app: String)] = []
        var latestDay: String?
        var latestApp: String?
        var previousEpoch: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            let day = text(statement, 0) ?? ""
            let epoch = sqlite3_column_int64(statement, 1)
            let app = text(statement, 2) ?? ""
            let classification = text(statement, 3)
            if rows.isEmpty {
                guard classification == BehaviorClassification.unknown.rawValue else { return nil }
                latestDay = day
                latestApp = app
            } else if classification != BehaviorClassification.unknown.rawValue
                        || day != latestDay
                        || app != latestApp
                        || previousEpoch.map({ $0 - epoch > 180 }) == true {
                break
            }
            rows.append((day, epoch, app))
            previousEpoch = epoch
        }
        guard let latest = rows.first, let first = rows.last else { return nil }
        return ObservationSession(
            sourceDay: latest.day,
            startEpoch: first.epoch,
            latestEpoch: latest.epoch,
            application: latest.app,
            observationCount: rows.count
        )
    }

    private func activeTask() throws -> ActiveTask? {
        var statement: OpaquePointer?
        let sql = """
        SELECT state.task_id, COALESCE(NULLIF(source.title, ''), 'your active task'), interval.started_at
        FROM task_execution_states state
        JOIN task_activity_intervals interval ON interval.task_id = state.task_id AND interval.ended_at IS NULL
        LEFT JOIN source_tasks source ON source.source_id = state.task_id
        WHERE state.state = 'active'
        ORDER BY interval.started_at DESC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let title = text(statement, 1),
              let startedRaw = text(statement, 2),
              let startedAt = ISO8601DateFormatter().date(from: startedRaw)
        else { return nil }
        return ActiveTask(id: id, title: title, startedAtEpoch: Int64(startedAt.timeIntervalSince1970))
    }

    private func hasPrompt(decisionKey: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            SELECT 1
            FROM prompt_episodes
            WHERE decision_key = ?
               OR (decision_key LIKE 'resolved:%' AND substr(decision_key, -length(?)) = ?)
            LIMIT 1;
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(decisionKey, statement, 1)
        bind(decisionKey, statement, 2)
        bind(decisionKey, statement, 3)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func databaseError() -> AmbiguousActivityPromptServiceError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, ambiguousSQLiteTransient)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }
}

public enum AmbiguousActivityPromptServiceError: Error, Equatable, Sendable {
    case openDatabase
    case invalidPromptPayload
    case database(String)
}
