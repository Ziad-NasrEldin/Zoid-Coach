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
    case responsePauseActive
    case fiveMinuteSnoozeActive
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

    private struct StoredBehaviorPromptEnvelope: Decodable {
        let payload: [String: String]
    }

    private enum IntentionalOverrideState: Equatable {
        case none
        case active
        case ended(responseEpoch: Int64)
        case expired(responseEpoch: Int64)
    }

    private enum FiveMinuteSnoozeState: Equatable {
        case none
        case active(responseEpoch: Int64)
        case elapsed(responseEpoch: Int64, promptID: String)
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
        let taskStartGrace = TimeInterval(policy.gaming.taskStartGraceMinutes * 60)
        if !sustainedBeforeTask,
           taskStartGrace > 0,
           let taskStartedAt = try activeTaskStartedAt(),
           date.timeIntervalSince(taskStartedAt) < taskStartGrace {
            return .suppressed(.taskStartGrace)
        }
        let idleGrace = TimeInterval(policy.gaming.returnFromIdleGraceMinutes * 60)
        if !sustainedBeforeTask,
           idleGrace > 0,
           try isWithinReturnFromIdleGrace(localDay: localDay, now: date, graceInterval: idleGrace) {
            return .suppressed(.returnFromIdleGrace)
        }
        guard session.minutes >= 10 else { return .suppressed(.belowThreshold) }
        guard gamingStatus.unlockedRemainingMinutes == 0 else { return .suppressed(.gamingIsUnlocked) }
        guard let task = try incompletePriorityTask(localDay: localDay) else {
            return .suppressed(.noIncompletePriorityWork)
        }

        let decisionKeyPrefix = "gaming-drift:\(localDay):"
        let baseDecisionKey = "\(decisionKeyPrefix)\(session.startedAtEpoch)"
        if try hasEndedWorkdayResponse(decisionKeyPrefix: decisionKeyPrefix) {
            return .suppressed(.workdayClosed)
        }
        let snooze = try fiveMinuteSnoozeState(decisionKey: baseDecisionKey, at: date)
        if case .active = snooze {
            return .suppressed(.fiveMinuteSnoozeActive)
        }
        let override = try intentionalOverrideState(
            decisionKeyPrefix: decisionKeyPrefix,
            localDay: localDay,
            at: date,
            durationMinutes: policy.gaming.intentionalOverrideMinutes
        )
        guard override != .active else { return .suppressed(.intentionalOverrideActive) }

        let decisionKey: String
        let isFiveMinuteFollowUp: Bool
        switch snooze {
        case let .elapsed(responseEpoch, _):
            decisionKey = "\(baseDecisionKey):after-five-more:\(responseEpoch)"
            isFiveMinuteFollowUp = true
        case .none, .active:
            isFiveMinuteFollowUp = false
            switch override {
            case let .ended(responseEpoch), let .expired(responseEpoch):
                decisionKey = "\(baseDecisionKey):after-intentional:\(responseEpoch)"
            case .none, .active:
                decisionKey = baseDecisionKey
            }
        }
        if try hasPrompt(decisionKey: decisionKey) {
            return .suppressed(.sessionAlreadyHandled)
        }
        let prefix = decisionKeyPrefix
        let level = policy.gaming.coachingLevel
        let isBelowDailyPromptCap = try promptCount(decisionKeyPrefix: prefix) < policy.gaming.dailyPromptCap
        guard isFiveMinuteFollowUp || isBelowDailyPromptCap else {
            try recordQuietDrift(localDay: localDay, session: session, at: date)
            return .suppressed(.dailyLimitReached)
        }
        if !isFiveMinuteFollowUp,
           try hasActiveResponsePause(decisionKeyPrefix: prefix, at: date) {
            return .suppressed(.responsePauseActive)
        }
        let completedIntentionalOverride: Bool
        switch override {
        case .ended, .expired: completedIntentionalOverride = true
        case .none, .active: completedIntentionalOverride = false
        }
        if !isFiveMinuteFollowUp,
           !completedIntentionalOverride,
           let latestCreatedAt = try latestPromptCreatedAt(decisionKeyPrefix: prefix),
           date.timeIntervalSince(latestCreatedAt) < TimeInterval(policy.gaming.promptCooldownMinutes * 60) {
            return .suppressed(.cooldownActive)
        }

        let title = isFiveMinuteFollowUp
            ? "Your five minutes are up"
            : (level == .gentle ? "Ready for an easy return?" : "Is this gaming intentional?")
        let summary = isFiveMinuteFollowUp
            ? "The five-minute extension has ended. The current session contains \(session.minutes) observed minutes in \(session.application), and \(task.title) remains unfinished. This shows activity, not why it happened or what you intended."
            : "The current session contains \(session.minutes) observed minutes in \(session.application) while \(task.title) remains unfinished. This shows activity, not why it happened or what you intended."
        var actions = [PromptAction(kind: .returnToActiveTask, title: "Return to \(task.title)", role: .primary)]
        if level == .gentle {
            actions.append(PromptAction(kind: .startShortSprint, title: "Start a 10-minute recovery sprint"))
            if !isFiveMinuteFollowUp {
                actions.append(PromptAction(kind: .fiveMoreMinutes, title: "Five more minutes"))
            }
        } else {
            actions.append(PromptAction(kind: .startWorkSprint, title: "Start a 20-minute work sprint"))
        }
        if level == .accountability, try hasActiveTask() {
            actions.append(PromptAction(kind: .startBreak, title: "Take a break"))
        }
        actions.append(PromptAction(
            kind: .rescheduleTask,
            title: "Reschedule \(task.title)",
            role: .destructive,
            requiresConfirmation: true
        ))
        actions.append(PromptAction(kind: .continueIntentionally, title: "Continue intentionally"))
        if isFiveMinuteFollowUp {
            actions.append(PromptAction(kind: .endWorkday, title: "I am done today"))
        }
        var payload = [
            "localDay": localDay,
            "taskID": task.id,
            "taskTitle": task.title,
            "application": session.application,
            "observedGamingMinutes": String(session.minutes),
            "evidenceStartedAtEpoch": String(session.startedAtEpoch),
            "evidenceLatestAtEpoch": String(session.latestAtEpoch),
            "behaviorPromptContractVersion": BehaviorPromptPresentationPolicy.contractVersion,
            "uncertaintyHandling": "Limited source coverage suppresses the intervention",
            "sessionStartedAtEpoch": String(session.startedAtEpoch),
            "coachingLevel": level.rawValue,
            "allowsDismissal": "true"
        ]
        if case let .elapsed(_, promptID) = snooze {
            payload["followUpForPromptID"] = promptID
            payload["snoozeDurationMinutes"] = "5"
        }
        let result = try prompts.enqueue(PromptDraft(
            decisionKey: decisionKey,
            type: PromptNotificationCategory.gamingDrift.rawValue,
            title: title,
            summary: summary,
            actions: actions,
            payload: payload,
            expiresAt: date.addingTimeInterval(30 * 60)
        ))
        return .queued(result.episode, wasInserted: result.wasInserted)
    }

    private func recordQuietDrift(localDay: String, session: GamingSession, at date: Date) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO quiet_drift_episodes (
            local_day,
            session_started_epoch,
            latest_observed_epoch,
            application,
            observed_minutes,
            recorded_at_utc,
            updated_at_utc
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(local_day, session_started_epoch) DO UPDATE SET
            latest_observed_epoch = MAX(quiet_drift_episodes.latest_observed_epoch, excluded.latest_observed_epoch),
            application = excluded.application,
            observed_minutes = MAX(quiet_drift_episodes.observed_minutes, excluded.observed_minutes),
            updated_at_utc = excluded.updated_at_utc;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        let timestamp = formatter.string(from: date)
        bind(localDay, statement, 1)
        sqlite3_bind_int64(statement, 2, session.startedAtEpoch)
        sqlite3_bind_int64(statement, 3, session.latestAtEpoch)
        bind(String(session.application.prefix(240)), statement, 4)
        sqlite3_bind_int(statement, 5, Int32(session.minutes))
        bind(timestamp, statement, 6)
        bind(timestamp, statement, 7)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
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

    private func isWithinReturnFromIdleGrace(
        localDay: String,
        now: Date,
        graceInterval: TimeInterval
    ) throws -> Bool {
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
              now.timeIntervalSince1970 - Double(latest.epoch) <= graceInterval,
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

    private func fiveMinuteSnoozeState(
        decisionKey: String,
        at date: Date
    ) throws -> FiveMinuteSnoozeState {
        var statement: OpaquePointer?
        let sql = """
        SELECT response.responded_at_utc, episode.id
        FROM prompt_responses response
        JOIN prompt_episodes episode ON episode.id = response.prompt_id
        WHERE response.response = ?
          AND (episode.decision_key = ? OR episode.decision_key LIKE ?)
        ORDER BY response.responded_at_utc DESC, response.id DESC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(PromptActionKind.fiveMoreMinutes.rawValue, statement, 1)
        bind(decisionKey, statement, 2)
        bind("resolved:%:" + decisionKey, statement, 3)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = text(statement, 0),
              let respondedAt = formatter.date(from: raw),
              let promptID = text(statement, 1) else { return .none }

        let responseEpoch = Int64(respondedAt.timeIntervalSince1970)
        if date.timeIntervalSince(respondedAt) < 5 * 60 {
            return .active(responseEpoch: responseEpoch)
        }
        return .elapsed(responseEpoch: responseEpoch, promptID: promptID)
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

    private func hasActiveResponsePause(decisionKeyPrefix: String, at date: Date) throws -> Bool {
        var statement: OpaquePointer?
        let sql = """
        SELECT response.responded_at_utc, response.response, episode.payload_json
        FROM prompt_responses response
        JOIN prompt_episodes episode ON episode.id = response.prompt_id
        WHERE episode.prompt_type = ?
          AND (episode.decision_key LIKE ? OR episode.decision_key LIKE ?)
        ORDER BY response.responded_at_utc DESC, response.id DESC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(PromptNotificationCategory.gamingDrift.rawValue, statement, 1)
        bind(decisionKeyPrefix + "%", statement, 2)
        bind("resolved:%:" + decisionKeyPrefix + "%", statement, 3)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawDate = text(statement, 0),
              let respondedAt = formatter.date(from: rawDate),
              let rawAction = text(statement, 1),
              let action = PromptActionKind(rawValue: rawAction),
              let rawPayload = text(statement, 2),
              let envelope = try? JSONDecoder().decode(
                  StoredBehaviorPromptEnvelope.self,
                  from: Data(rawPayload.utf8)
              )
        else { return false }

        switch action {
        case .fiveMoreMinutes, .continueIntentionally, .endWorkday:
            return false
        default:
            break
        }
        let level = envelope.payload["coachingLevel"].flatMap(CoachingLevel.init(rawValue:)) ?? .gentle
        let pauseMinutes = level == .gentle ? 15 : 20
        return date.timeIntervalSince(respondedAt) < TimeInterval(pauseMinutes * 60)
    }

    private func hasEndedWorkdayResponse(decisionKeyPrefix: String) throws -> Bool {
        var statement: OpaquePointer?
        let sql = """
        SELECT 1
        FROM prompt_responses response
        JOIN prompt_episodes episode ON episode.id = response.prompt_id
        WHERE response.response = ?
          AND episode.prompt_type = ?
          AND (episode.decision_key LIKE ? OR episode.decision_key LIKE ?)
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        bind(PromptActionKind.endWorkday.rawValue, statement, 1)
        bind(PromptNotificationCategory.gamingDrift.rawValue, statement, 2)
        bind(decisionKeyPrefix + "%", statement, 3)
        bind("resolved:%:" + decisionKeyPrefix + "%", statement, 4)
        return sqlite3_step(statement) == SQLITE_ROW
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
