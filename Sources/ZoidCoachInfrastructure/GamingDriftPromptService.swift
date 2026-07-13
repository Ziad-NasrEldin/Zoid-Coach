import Foundation
import SQLite3
import ZoidCoachCore

public enum GamingDriftSuppressionReason: String, Equatable, Sendable {
    case observingBaseline
    case coachingDisabled
    case gamingBudgetDisabled
    case automationPaused
    case outsideWorkWindow
    case acceptedBreak
    case workdayClosed
    case limitedCoverage
    case noGamingSession
    case belowThreshold
    case taskStartGrace
    case returnFromIdleGrace
    case neutralSupportingActivity
    case gamingIsUnlocked
    case noIncompletePriorityWork
    case intentionalOverrideActive
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

    private enum IntentionalOverrideState: Equatable {
        case none
        case active
        case ended(responseEpoch: Int64)
        case expired(responseEpoch: Int64)
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
        guard policy.gaming.budgetEnabled else { return .suppressed(.gamingBudgetDisabled) }
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
        if let observation = try latestObservation(localDay: localDay, now: date), observation.isNeutralSupporting {
            return .suppressed(.neutralSupportingActivity)
        }
        guard let session = try currentGamingSession(localDay: localDay, now: date) else {
            return .suppressed(.noGamingSession)
        }
        let sustainedBeforeTask = try activeTaskStartedAt().map {
            session.minutes >= 10 && session.startedAtEpoch < Int64($0.timeIntervalSince1970)
        } ?? false
        if !sustainedBeforeTask,
           let taskStartedAt = try activeTaskStartedAt(),
           date.timeIntervalSince(taskStartedAt) < 180 {
            return .suppressed(.taskStartGrace)
        }
        if !sustainedBeforeTask, try isWithinReturnFromIdleGrace(localDay: localDay, now: date) {
            return .suppressed(.returnFromIdleGrace)
        }
        guard session.minutes >= 10 else { return .suppressed(.belowThreshold) }
        guard gamingStatus.unlockedRemainingMinutes == 0 else { return .suppressed(.gamingIsUnlocked) }
        guard let task = try incompletePriorityTask(localDay: localDay) else {
            return .suppressed(.noIncompletePriorityWork)
        }

        let decisionKeyPrefix = "gaming-drift:\(localDay):"
        let override = try intentionalOverrideState(
            decisionKeyPrefix: decisionKeyPrefix,
            localDay: localDay,
            at: date,
            durationMinutes: policy.gaming.intentionalOverrideMinutes
        )
        guard override != .active else { return .suppressed(.intentionalOverrideActive) }

        let baseDecisionKey = "\(decisionKeyPrefix)\(session.startedAtEpoch)"
        let decisionKey: String
        switch override {
        case let .ended(responseEpoch), let .expired(responseEpoch):
            decisionKey = "\(baseDecisionKey):after-intentional:\(responseEpoch)"
        case .none, .active:
            decisionKey = baseDecisionKey
        }
        if try hasPrompt(decisionKey: decisionKey) {
            return .suppressed(.sessionAlreadyHandled)
        }
        let prefix = decisionKeyPrefix
        let level = policy.gaming.coachingLevel
        guard try promptCount(decisionKeyPrefix: prefix) < policy.gaming.dailyPromptCap else {
            return .suppressed(.dailyLimitReached)
        }
        let completedIntentionalOverride: Bool
        switch override {
        case .ended, .expired: completedIntentionalOverride = true
        case .none, .active: completedIntentionalOverride = false
        }
        if !completedIntentionalOverride,
           let latestCreatedAt = try latestPromptCreatedAt(decisionKeyPrefix: prefix),
           date.timeIntervalSince(latestCreatedAt) < TimeInterval(policy.gaming.promptCooldownMinutes * 60) {
            return .suppressed(.cooldownActive)
        }

        let title = level == .gentle ? "Ready for an easy return?" : "Is this gaming intentional?"
        let summary = "Observed \(session.minutes) minutes in \(session.application) while \(task.title) remains unfinished. This is an observation, not a judgment."
        var actions = [
            PromptAction(kind: .returnToActiveTask, title: "Return to \(task.title)", role: .primary),
            PromptAction(kind: .fiveMoreMinutes, title: "Five more minutes")
        ]
        if try hasActiveTask() {
            actions.append(PromptAction(kind: .startBreak, title: "Take a break"))
        }
        actions.append(PromptAction(kind: .continueIntentionally, title: "Continue intentionally"))
        let result = try prompts.enqueue(PromptDraft(
            decisionKey: decisionKey,
            type: PromptNotificationCategory.gamingDrift.rawValue,
            title: title,
            summary: summary,
            actions: actions,
            payload: [
                "localDay": localDay,
                "taskID": task.id,
                "taskTitle": task.title,
                "application": session.application,
                "observedGamingMinutes": String(session.minutes),
            "sessionStartedAtEpoch": String(session.startedAtEpoch),
            "coachingLevel": level.rawValue,
            "allowsDismissal": "true"
        ],
            expiresAt: date.addingTimeInterval(30 * 60)
        ))
        return .queued(result.episode, wasInserted: result.wasInserted)
    }

    private func hasActiveTask() throws -> Bool {
        guard try tableExists("task_execution_states") else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM task_execution_states WHERE state = 'active' LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func activeTaskStartedAt() throws -> Date? {
        guard try tableExists("task_activity_intervals") else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT started_at FROM task_activity_intervals WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let startedAt = text(statement, 0)
        else { return nil }
        return formatter.date(from: startedAt)
    }

    private struct ObservationContext {
        let epoch: Int64
        let app: String
        let windowTitle: String
        let url: String

        var isNeutralSupporting: Bool {
            let normalizedApp = app.lowercased()
            let normalizedTitle = windowTitle.lowercased()
            let normalizedURL = url.lowercased()
            let neutralAppNames = [
                "system settings", "system preferences", "1password", "bitwarden", "keychain access",
                "finder", "slack", "messages", "mail", "microsoft teams", "zoom", "zoom.us"
            ]
            let isNeutralApp = neutralAppNames.contains { neutralName in
                normalizedApp == neutralName
                    || normalizedApp.hasPrefix("\(neutralName) ")
                    || normalizedApp.hasPrefix("\(neutralName) -")
            }
            if isNeutralApp { return true }
            let fileDialogTitles = [
                "open", "open file", "open document", "save", "save as", "save file",
                "choose a file", "choose file", "choose folder"
            ]
            let isFileDialog = fileDialogTitles.contains(normalizedTitle)
            return isFileDialog || normalizedURL.hasPrefix("file://")
        }
    }

    private func latestObservation(localDay: String, now: Date) throws -> ObservationContext? {
        guard try tableExists("behavior_records") else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT epoch, app_name, window_title, url FROM behavior_records WHERE source_day = ? ORDER BY epoch DESC LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let epoch = sqlite3_column_int64(statement, 0)
        guard now.timeIntervalSince1970 - Double(epoch) <= 180 else { return nil }
        return ObservationContext(
            epoch: epoch,
            app: text(statement, 1) ?? "",
            windowTitle: text(statement, 2) ?? "",
            url: text(statement, 3) ?? ""
        )
    }

    private func isWithinReturnFromIdleGrace(localDay: String, now: Date) throws -> Bool {
        guard try tableExists("behavior_records") else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT epoch, classification FROM behavior_records WHERE source_day = ? ORDER BY epoch DESC LIMIT 2;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        var rows: [(epoch: Int64, classification: String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(statement, 0), text(statement, 1)))
        }
        guard let latest = rows.first,
              now.timeIntervalSince1970 - Double(latest.epoch) <= 60,
              rows.count > 1
        else { return false }
        let previous = rows[1]
        return previous.classification == BehaviorClassification.idle.rawValue
            || latest.epoch - previous.epoch > 300
    }

    private func intentionalOverrideState(
        decisionKeyPrefix: String,
        localDay: String,
        at date: Date,
        durationMinutes: Int
    ) throws -> IntentionalOverrideState {
        var statement: OpaquePointer?
        let sql = """
        SELECT response.responded_at_utc
        FROM prompt_responses response
        JOIN prompt_episodes episode ON episode.id = response.prompt_id
        WHERE response.response = ?
          AND (episode.decision_key LIKE ? OR episode.decision_key LIKE ?)
        ORDER BY response.responded_at_utc DESC, response.id DESC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(PromptActionKind.continueIntentionally.rawValue, statement, 1)
        bind(decisionKeyPrefix + "%", statement, 2)
        bind("resolved:%:" + decisionKeyPrefix + "%", statement, 3)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = text(statement, 0),
              let respondedAt = formatter.date(from: raw) else { return .none }

        let responseEpoch = Int64(respondedAt.timeIntervalSince1970)
        if try hasAlignedWorkForTwoMinutes(localDay: localDay, after: responseEpoch) {
            return .ended(responseEpoch: responseEpoch)
        }
        if date.timeIntervalSince(respondedAt) >= TimeInterval(durationMinutes * 60) {
            return .expired(responseEpoch: responseEpoch)
        }
        return .active
    }

    private func hasAlignedWorkForTwoMinutes(localDay: String, after epoch: Int64) throws -> Bool {
        var statement: OpaquePointer?
        let sql = """
        SELECT behavior.epoch,
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
          AND behavior.epoch > ?
        ORDER BY behavior.epoch ASC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(localDay, statement, 1)
        sqlite3_bind_int64(statement, 2, epoch)
        var workStartedAt: Int64?
        var previousEpoch: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            let observedEpoch = sqlite3_column_int64(statement, 0)
            let classification = text(statement, 1)
            guard classification == BehaviorClassification.work.rawValue else {
                workStartedAt = nil
                previousEpoch = nil
                continue
            }
            if previousEpoch.map({ observedEpoch - $0 > 180 }) == true {
                workStartedAt = observedEpoch
            } else if workStartedAt == nil {
                workStartedAt = observedEpoch
            }
            previousEpoch = observedEpoch
            if let workStartedAt, observedEpoch - workStartedAt + 60 >= 120 {
                return true
            }
        }
        return false
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
