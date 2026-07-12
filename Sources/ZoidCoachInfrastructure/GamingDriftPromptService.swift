import Foundation
import SQLite3
import ZoidCoachCore

public enum GamingDriftSuppressionReason: String, Equatable, Sendable {
    case observingBaseline
    case coachingDisabled
    case automationPaused
    case outsideWorkWindow
    case acceptedBreak
    case workdayClosed
    case limitedCoverage
    case noGamingSession
    case belowThreshold
    case gamingIsUnlocked
    case noIncompletePriorityWork
    case sessionAlreadyHandled
    case dailyLimitReached
    case cooldownActive
}

public enum GamingDriftPromptResult: Equatable, Sendable {
    case suppressed(GamingDriftSuppressionReason)
    case queued(PromptEpisode, wasInserted: Bool)
}

public final class GamingDriftPromptService: @unchecked Sendable {
    private struct GamingSession {
        let startedAtEpoch: Int64
        let latestAtEpoch: Int64
        let minutes: Int
        let application: String
    }

    private struct PriorityTask {
        let id: String
        let title: String
    }

    private let database: OpaquePointer
    private let prompts: PromptInboxStore
    private let now: @Sendable () -> Date
    private let formatter = ISO8601DateFormatter()

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        promptStore: PromptInboxStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            throw GamingDriftPromptServiceError.openDatabase
        }
        database = handle
        sqlite3_busy_timeout(database, 5_000)
        prompts = promptStore
        self.now = now
    }

    deinit { sqlite3_close(database) }

    public func produce(
        policy: UserPolicy,
        gamingStatus: GamingStatus,
        baselineStatus: BaselineObservationStatus
    ) throws -> GamingDriftPromptResult {
        let date = now()
        let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier) ?? .current
        let localDay = Self.localDay(date, timeZone: timeZone)

        guard policy.operatingMode != .observe else { return .suppressed(.coachingDisabled) }
        guard !policy.automationPause.isPaused else { return .suppressed(.automationPaused) }
        guard !baselineStatus.suppressesBehaviorPrompts else {
            return .suppressed(.observingBaseline)
        }
        guard Self.isWithinWorkWindow(date, policy: policy, timeZone: timeZone) else {
            return .suppressed(.outsideWorkWindow)
        }
        switch try openPauseReason() {
        case .break: return .suppressed(.acceptedBreak)
        case .endingWorkday: return .suppressed(.workdayClosed)
        default: break
        }
        guard !gamingStatus.confidenceIsLimited else { return .suppressed(.limitedCoverage) }
        guard let session = try currentGamingSession(localDay: localDay, now: date) else {
            return .suppressed(.noGamingSession)
        }
        guard session.minutes >= 10 else { return .suppressed(.belowThreshold) }
        guard gamingStatus.unlockedRemainingMinutes == 0 else { return .suppressed(.gamingIsUnlocked) }
        guard let task = try incompletePriorityTask(localDay: localDay) else {
            return .suppressed(.noIncompletePriorityWork)
        }

        let decisionKey = "gaming-drift:\(localDay):\(session.startedAtEpoch)"
        if try hasPrompt(decisionKey: decisionKey) {
            return .suppressed(.sessionAlreadyHandled)
        }
        let prefix = "gaming-drift:\(localDay):"
        let level = policy.gaming.coachingLevel
        guard try promptCount(decisionKeyPrefix: prefix) < level.maximumDailyPrompts else {
            return .suppressed(.dailyLimitReached)
        }
        if let latestCreatedAt = try latestPromptCreatedAt(decisionKeyPrefix: prefix),
           date.timeIntervalSince(latestCreatedAt) < TimeInterval(level.cooldownMinutes * 60) {
            return .suppressed(.cooldownActive)
        }

        let title = level == .gentle ? "Ready for an easy return?" : "Is this gaming intentional?"
        let summary = "Observed \(session.minutes) minutes in \(session.application) while \(task.title) remains unfinished. This is an observation, not a judgment."
        let result = try prompts.enqueue(PromptDraft(
            decisionKey: decisionKey,
            type: PromptNotificationCategory.gamingDrift.rawValue,
            title: title,
            summary: summary,
            actions: [
                PromptAction(kind: .returnToActiveTask, title: "Return to \(task.title)", role: .primary),
                PromptAction(kind: .fiveMoreMinutes, title: "Five more minutes"),
                PromptAction(kind: .startBreak, title: "Take a break"),
                PromptAction(kind: .continueIntentionally, title: "Continue intentionally")
            ],
            payload: [
                "localDay": localDay,
                "taskID": task.id,
                "taskTitle": task.title,
                "application": session.application,
                "observedGamingMinutes": String(session.minutes),
                "sessionStartedAtEpoch": String(session.startedAtEpoch),
                "coachingLevel": level.rawValue
            ],
            expiresAt: date.addingTimeInterval(30 * 60)
        ))
        return .queued(result.episode, wasInserted: result.wasInserted)
    }

    private func currentGamingSession(localDay: String, now: Date) throws -> GamingSession? {
        var statement: OpaquePointer?
        let sql = """
        SELECT behavior.epoch, behavior.app_name,
               COALESCE(
                   (SELECT correction.classification
                    FROM daily_review_corrections correction
                    WHERE correction.source_day = behavior.source_day
                      AND behavior.epoch >= correction.start_epoch
                      AND behavior.epoch < correction.end_epoch
                    ORDER BY correction.created_at_utc DESC, correction.rowid DESC LIMIT 1),
                   behavior.classification
               )
        FROM behavior_records behavior
        WHERE behavior.source_day = ?
        ORDER BY behavior.epoch DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var gamingRows: [(epoch: Int64, app: String)] = []
        var previousEpoch: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            let epoch = sqlite3_column_int64(statement, 0)
            let app = text(statement, 1) ?? "a gaming app"
            let classification = text(statement, 2)
            if gamingRows.isEmpty {
                guard classification == BehaviorClassification.gaming.rawValue,
                      now.timeIntervalSince1970 - Double(epoch) <= 180 else { return nil }
            } else if classification != BehaviorClassification.gaming.rawValue
                        || previousEpoch.map({ $0 - epoch > 180 }) == true {
                break
            }
            gamingRows.append((epoch, app))
            previousEpoch = epoch
        }
        guard let latest = gamingRows.first, let first = gamingRows.last else { return nil }
        return GamingSession(
            startedAtEpoch: first.epoch,
            latestAtEpoch: latest.epoch,
            minutes: max(1, Int((latest.epoch - first.epoch + 60) / 60)),
            application: latest.app.isEmpty ? "a gaming app" : latest.app
        )
    }

    private func incompletePriorityTask(localDay: String) throws -> PriorityTask? {
        var statement: OpaquePointer?
        let sql = """
        SELECT plan.reminder_id, COALESCE(NULLIF(source.title, ''), 'your priority task')
        FROM daily_plan_entries plan
        LEFT JOIN source_tasks source ON source.source_id = plan.reminder_id
        LEFT JOIN task_execution_states execution ON execution.task_id = plan.reminder_id
        WHERE plan.day_key = ?
          AND COALESCE(plan.is_optional, 0) = 0
          AND plan.blocked_reason IS NULL
          AND plan.deferred_until_utc IS NULL
          AND COALESCE(execution.state, 'ready') NOT IN ('completed', 'blocked', 'rescheduled')
          AND NOT EXISTS (
              SELECT 1 FROM task_history history
              WHERE history.task_id = plan.reminder_id AND history.state = 'completed'
          )
        ORDER BY plan.is_main_objective DESC, plan.rank ASC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let id = text(statement, 0), let title = text(statement, 1) else { return nil }
        return PriorityTask(id: id, title: title)
    }

    private func openPauseReason() throws -> TaskPauseReason? {
        guard try tableExists("task_pause_events") else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT reason FROM task_pause_events WHERE resumed_at IS NULL ORDER BY paused_at DESC LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = text(statement, 0) else { return nil }
        return TaskPauseReason(rawValue: raw)
    }

    private func promptCount(decisionKeyPrefix: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT COUNT(*) FROM prompt_episodes WHERE decision_key LIKE ? OR decision_key LIKE ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(decisionKeyPrefix + "%", statement, 1)
        bind("resolved:%:" + decisionKeyPrefix + "%", statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func hasPrompt(decisionKey: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM prompt_episodes WHERE decision_key = ? OR decision_key LIKE ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(decisionKey, statement, 1)
        bind("resolved:%:" + decisionKey, statement, 2)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func latestPromptCreatedAt(decisionKeyPrefix: String) throws -> Date? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT created_at_utc FROM prompt_episodes WHERE decision_key LIKE ? OR decision_key LIKE ? ORDER BY created_at_utc DESC, id DESC LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(decisionKeyPrefix + "%", statement, 1)
        bind("resolved:%:" + decisionKeyPrefix + "%", statement, 2)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = text(statement, 0) else { return nil }
        return formatter.date(from: raw)
    }

    private func tableExists(_ name: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(name, statement, 1)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func scalar(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, gamingSQLiteTransient) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func databaseError() -> GamingDriftPromptServiceError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    private static func localDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isWithinWorkWindow(_ date: Date, policy: UserPolicy, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return false }
        let localTime = LocalTime(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
        return policy.schedule.workWindows.contains { window in
            guard window.weekdays.contains(weekday) else { return false }
            if window.end < window.start {
                return localTime >= window.start || localTime <= window.end
            }
            return localTime >= window.start && localTime <= window.end
        }
    }
}

public enum GamingDriftPromptServiceError: LocalizedError, Sendable {
    case openDatabase
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .openDatabase: "The local coaching evidence store could not be opened."
        case .database: "The local coaching evidence could not be read safely."
        }
    }
}

private let gamingSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
