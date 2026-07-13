import Foundation
import EventKit
import ZoidCoachCore

public final class TodayDashboardAgent: @unchecked Sendable {
    private let reminders: ReminderSnapshotStore
    private let plans: AutonomousPlanStore
    private let execution: TaskExecutionStore
    private let archive: ScreenwatchArchive
    private let snapshots: TodaySnapshotStore
    private let learning: LearningAggregateStore
    private let outbox: ActionOutboxStore
    private let taskHistory: TaskHistoryStore
    private let userPolicyStore: PolicyStore
    private let checkpoints: ProcessingCheckpointStore
    private let planningInvitations: PlanningInvitationService
    private let recommendationFeedback: RecommendationFeedbackStore

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
        let policyStore = try PolicyStore(databaseURL: databaseURL)
        userPolicyStore = policyStore
        plans = try AutonomousPlanStore(
            databaseURL: databaseURL,
            timeZoneIdentifier: {
                (try? policyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
            }
        )
        execution = try TaskExecutionStore(databaseURL: databaseURL)
        archive = try ScreenwatchArchive(databaseURL: databaseURL)
        snapshots = try TodaySnapshotStore(databaseURL: databaseURL)
        learning = try LearningAggregateStore(databaseURL: databaseURL)
        outbox = try ActionOutboxStore(databaseURL: databaseURL)
        taskHistory = try TaskHistoryStore(databaseURL: databaseURL)
        checkpoints = try ProcessingCheckpointStore(databaseURL: databaseURL)
        recommendationFeedback = try RecommendationFeedbackStore(databaseURL: databaseURL)
        planningInvitations = PlanningInvitationService(
            store: try PromptInboxStore(databaseURL: databaseURL)
        )
    }

    public func snapshot(now: Date = Date()) throws -> TodaySnapshot {
        let previousSnapshot = try snapshots.load(for: now)
        if let active = try execution.activeTask(now: now),
           try reminders.sourceKind(forID: active.taskID) == nil,
           previousSnapshot?.taskRows.contains(where: { $0.taskID == active.taskID }) == true {
            try execution.pauseForDeletedReminder(taskID: active.taskID, at: now)
        }
        let plan = try plans.loadDailyPlan(for: now)
        let reminderSnapshots = try reminders.loadIncomplete()
        let reminderByID = Dictionary(uniqueKeysWithValues: reminderSnapshots.map { ($0.id, $0) })
        let executionByID = try execution.snapshot(for: reminderSnapshots.map(\.id), now: now)
        let behaviorObservations = try archive.behaviorObservations(for: now)
        let behavior = BehaviorSessionizer().summarize(observations: behaviorObservations, now: now)
        let active = try execution.activeTask(now: now)
        var rows = plan.compactMap { entry -> TodayTaskRow? in
            guard let reminder = reminderByID[entry.reminderID] else { return nil }
            let current = executionByID[entry.reminderID]
            guard current?.state != .completed else { return nil }
            return TodayTaskRow(
                taskID: reminder.id,
                title: reminder.title,
                estimateMinutes: entry.estimateMinutes,
                dueDate: reminder.dueDate,
                urgency: TaskUrgency.resolve(dueDate: reminder.dueDate, priority: reminderPriority(reminder.priority), referenceDate: now),
                state: current?.state ?? .ready,
                elapsedMinutes: current?.elapsedMinutes ?? 0,
                activeTimeComparison: activeTimeComparison(
                    taskID: reminder.id,
                    active: active,
                    observations: behaviorObservations,
                    now: now
                ),
                latestPauseReason: current?.latestPauseReason,
                acceptedBreak: current?.acceptedBreak,
                sprint: current?.sprint,
                isMainObjective: entry.isMainObjective,
                isOptional: entry.isOptional == true,
                blockedReason: entry.blockedReason,
                deferredUntil: entry.deferredUntil,
                learnedEstimateSuggestion: learnedEstimateSuggestion(
                    for: reminder,
                    currentEstimateMinutes: entry.estimateMinutes
                )
            )
        }
        let gamingPolicy = try userPolicyStore.currentGamingPolicy()
        let rewardMinutes = try snapshots.priorityRewardMinutes(policy: gamingPolicy, day: now)
        let gaming = GamingStatusCalculator().status(
            policy: gamingPolicy,
            gamingMinutes: behavior.summary.meaningfulGamingMinutes,
            appliedRewardMinutes: rewardMinutes,
            coverage: behavior.coverage
        )
        let activeIsUnplanned = active.map { active in
            !plan.contains(where: { $0.reminderID == active.taskID })
        } ?? false
        if activeIsUnplanned,
           let active,
           let reminder = reminderByID[active.taskID],
           !rows.contains(where: { $0.taskID == active.taskID }) {
            let executionSnapshot = try execution.snapshot(for: [active.taskID], now: now)[active.taskID]
            rows.append(TodayTaskRow(
                taskID: reminder.id,
                title: reminder.title,
                estimateMinutes: 30,
                dueDate: reminder.dueDate,
                urgency: TaskUrgency.resolve(
                    dueDate: reminder.dueDate,
                    priority: reminderPriority(reminder.priority),
                    referenceDate: now
                ),
                state: executionSnapshot?.state ?? .active,
                elapsedMinutes: executionSnapshot?.elapsedMinutes ?? 0,
                activeTimeComparison: activeTimeComparison(
                    taskID: reminder.id,
                    active: active,
                    observations: behaviorObservations,
                    now: now
                ),
                latestPauseReason: executionSnapshot?.latestPauseReason,
                acceptedBreak: executionSnapshot?.acceptedBreak,
                sprint: executionSnapshot?.sprint,
                isMainObjective: false,
                learnedEstimateSuggestion: learnedEstimateSuggestion(
                    for: reminder,
                    currentEstimateMinutes: 30
                )
            ))
        }
        if let previousSnapshot {
            for previousRow in previousSnapshot.taskRows where !rows.contains(where: { $0.taskID == previousRow.taskID }) {
                guard reminderByID[previousRow.taskID] == nil,
                      try reminders.sourceKind(forID: previousRow.taskID) == nil,
                      let current = try execution.snapshot(for: [previousRow.taskID], now: now)[previousRow.taskID],
                      current.state == .paused,
                      current.latestPauseReason == .reminderDeleted
                else { continue }
                rows.append(deletedReminderRow(from: previousRow, execution: current))
            }
        }
        let timeZoneIdentifier = (try? userPolicyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
        let suppressedRecommendationIDs = try recommendationFeedback.suppressedTaskIDs(
            at: now,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let recommendation = active == nil
            ? NextTaskRecommender().recommend(
                tasks: rows.filter { !suppressedRecommendationIDs.contains($0.taskID) },
                referenceDate: now,
                availableMinutes: 60,
                coverage: behavior.coverage
            )
            : NextTaskRecommendation(
                taskID: active?.taskID,
                sentence: "Continue the active task before starting another one.",
                reasons: [],
                coverageUncertainty: behavior.coverage.isLimited ? behavior.coverage.explanation : nil
            )
        let plannedIDs = Set(rows.map(\.taskID))
        var eligibilityCalendar = Calendar(identifier: .gregorian)
        eligibilityCalendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let unplanned = reminderSnapshots
            .filter {
                !plannedIDs.contains($0.id)
                    && executionByID[$0.id]?.state != .completed
                    && TodayReminderEligibility.isVisible(
                        dueDate: $0.dueDate,
                        referenceDate: now,
                        calendar: eligibilityCalendar
                    )
            }
            .map {
                TodayReminderQueueRow(
                    reminderID: $0.id,
                    title: $0.title,
                    listID: $0.listID,
                    listName: $0.listName,
                    dueDate: $0.dueDate,
                    priority: $0.priority
                )
            }
        let reminderPermission = Self.permissionSnapshot(for: .reminder)
        let calendarPermission = Self.permissionSnapshot(for: .event)
        let sourceSnapshots = [
            SourceFreshnessSnapshot(
                sourceID: "reminders",
                state: reminderPermission.state,
                detail: "\(reminderPermission.detail); \(reminderSnapshots.count) normalized incomplete reminders",
                lastUpdatedAt: try reminders.lastUpdatedAt()
            ),
            SourceFreshnessSnapshot(
                sourceID: "calendar",
                state: calendarPermission.state,
                detail: calendarPermission.detail,
                lastUpdatedAt: try checkpoints.checkpoint(sourceID: "calendar-source")?.lastSuccessAt
            ),
            SourceFreshnessSnapshot(sourceID: "screenwatch", state: behavior.coverage.isLimited ? "limited" : "current", detail: behavior.coverage.explanation, lastUpdatedAt: behavior.coverage.lastObservationAt),
            SourceFreshnessSnapshot(sourceID: "agent", state: "running", detail: "Today snapshot generated by ZoidCoachAgent", lastUpdatedAt: now)
        ]
        let localDay = Self.localDayKey(now, timeZoneIdentifier: timeZoneIdentifier)
        let planningStatus = try planningInvitations.status(
            localDay: localDay,
            hasPlan: !plan.isEmpty,
            hasActiveUnplannedTask: activeIsUnplanned
        )
        let snapshot = TodaySnapshot(
            localDate: now,
            timeZoneIdentifier: timeZoneIdentifier,
            mainObjective: rows.first(where: \.isMainObjective)?.title,
            taskRows: rows,
            activeTask: active,
            activeTaskContext: active.map { _ in
                ActiveTaskContextAssessor().assess(observations: behaviorObservations, now: now)
            },
            recommendation: recommendation,
            behavior: behavior.summary,
            coverage: behavior.coverage,
            gaming: gaming,
            sourceFreshnessExplanation: sourceSnapshots.map { "\($0.sourceID): \($0.state)" }.joined(separator: " · "),
            unplannedReminders: unplanned,
            sources: sourceSnapshots,
            planningStatus: planningStatus
        )
        try snapshots.save(snapshot, for: now)
        return snapshot
    }

    private func deletedReminderRow(
        from previous: TodayTaskRow,
        execution current: TaskExecutionSnapshot
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: previous.taskID,
            title: previous.title,
            estimateMinutes: previous.estimateMinutes,
            dueDate: previous.dueDate,
            urgency: previous.urgency,
            state: .paused,
            elapsedMinutes: current.elapsedMinutes,
            latestPauseReason: .reminderDeleted,
            sprint: current.sprint,
            isMainObjective: previous.isMainObjective,
            isLocked: previous.isLocked,
            isOptional: previous.isOptional ?? false,
            blockedReason: previous.blockedReason,
            deferredUntil: previous.deferredUntil,
            learnedEstimateSuggestion: previous.learnedEstimateSuggestion
        )
    }

    @discardableResult
    public func apply(
        _ command: TaskActivityCommand,
        taskID: String,
        blockedReason: String? = nil,
        now: Date = Date()
    ) throws -> TodaySnapshot {
        let previousSnapshot = try snapshots.load(for: now)
        let previousExecution = try execution.snapshot(for: [taskID], now: now)[taskID]
        let activeBefore = try execution.activeTask(now: now)
        let reminderBefore = try reminders.loadIncomplete().first(where: { $0.id == taskID })
        let sourceKind = try reminders.sourceKind(forID: taskID)
        try execution.apply(command, taskID: taskID, blockedReason: blockedReason, at: now)
        if command == .block {
            let plan = try plans.loadDailyPlan(for: now)
            let executionByID = try execution.snapshot(for: plan.map(\.reminderID), now: now)
            let availableReminderIDs = Set(try reminders.loadIncomplete().map(\.id))
            let eligibleTaskIDs = plan.compactMap { entry -> String? in
                guard availableReminderIDs.contains(entry.reminderID),
                      entry.blockedReason == nil,
                      entry.deferredUntil == nil || entry.deferredUntil! <= now
                else { return nil }
                switch executionByID[entry.reminderID]?.state ?? .ready {
                case .ready, .paused:
                    return entry.reminderID
                case .active, .blocked, .completed, .rescheduled:
                    return nil
                }
            }
            try plans.promoteReplacementMainObjective(
                afterBlocking: taskID,
                eligibleTaskIDs: eligibleTaskIDs,
                for: now
            )
        }
        switch command {
        case .complete:
            if sourceKind == .local {
                try reminders.completeLocal(id: taskID, completedAt: now)
            } else {
                _ = try outbox.enqueue(
                    type: .completeReminder,
                    entityID: taskID,
                    desiredState: .completeReminder,
                    planVersion: 1
                )
            }
            try taskHistory.record(
                taskID: taskID,
                state: .completed,
                title: reminderBefore?.title,
                sourceKind: reminderBefore?.sourceKind,
                at: now
            )
        case .reschedule:
            try taskHistory.record(taskID: taskID, state: .postponed, at: now)
        case .start, .startSprint10, .startSprint20, .startSprint25:
            try taskHistory.record(taskID: taskID, state: .selected, at: now)
        case .pause, .pauseForBreak, .pauseForExternalInterruption, .pauseDoneForNow, .pauseForEndOfDay, .resume, .block, .continueOpenEnded:
            break
        }
        if command == .complete,
           let current = try snapshots.load(for: now),
           current.taskRows.first(where: { $0.taskID == taskID })?.isMainObjective == true {
            let gamingPolicy = try userPolicyStore.currentGamingPolicy()
            if gamingPolicy.priorityTaskRewardMinutes > 0 {
                _ = try snapshots.applyPriorityRewardIfNeeded(
                    taskID: taskID,
                    policy: gamingPolicy,
                    day: now
                )
            }
        }
        if command == .complete,
           previousExecution?.state != .completed,
           let row = previousSnapshot?.taskRows.first(where: { $0.taskID == taskID }) {
            let coverage = previousSnapshot?.coverage.isLimited == true ? 0.5 : 1.0
            let context = EstimateLearningContext(taskType: taskType(for: row.title), project: reminderBefore?.listName)
            let sampleID = "task-completion:\(taskID):\(Int(now.timeIntervalSince1970))"
            let sample = EstimateLearningSample(
                id: sampleID,
                context: context,
                estimatedMinutes: row.estimateMinutes,
                actualAlignedMinutes: max(1, activeBefore?.taskID == taskID ? activeBefore?.elapsedMinutes ?? row.elapsedMinutes : row.elapsedMinutes),
                trackingCoverage: coverage,
                completedAt: now
            )
            _ = try learning.recordEstimateSample(sample, evidenceID: sampleID)
            _ = try learning.updateEstimateAggregate(context: context, currentEstimateMinutes: row.estimateMinutes)
            if let startedAt = activeBefore?.taskID == taskID ? activeBefore?.startedAt : nil, startedAt < now {
                let workSample = WorkWindowLearningSample(
                    id: "work-window:\(taskID):\(Int(startedAt.timeIntervalSince1970))",
                    startedAt: startedAt,
                    endedAt: now,
                    trackingCoverage: coverage
                )
                let timeZoneIdentifier = (try? userPolicyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
                _ = try learning.recordWorkWindowSample(workSample, timeZoneIdentifier: timeZoneIdentifier)
                _ = try learning.updatePreferredWorkWindowAggregate(timeZoneIdentifier: timeZoneIdentifier)
            }
        }
        return try snapshot(now: now)
    }

    public func startSprint(taskID: String, durationMinutes: Int, now: Date = Date()) throws -> TodaySnapshot {
        let reminderExists = try reminders.loadIncomplete().contains(where: { $0.id == taskID })
        guard reminderExists else { throw TodayDashboardAgentError.unavailableTask }
        try execution.startSprint(taskID: taskID, durationMinutes: durationMinutes, at: now)
        try taskHistory.record(taskID: taskID, state: .selected, at: now)
        return try snapshot(now: now)
    }

    public func startUnplannedTask(_ taskID: String, now: Date = Date()) throws -> TodaySnapshot {
        let policy = try userPolicyStore.current()?.policy ?? UserPolicy.defaults()
        let localDay = Self.localDayKey(now, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        let incomplete = try reminders.loadIncomplete()
        guard incomplete.contains(where: { $0.id == taskID }) else {
            throw TodayDashboardAgentError.unavailableTask
        }
        _ = try planningInvitations.beginUnplannedDay(
            localDay: localDay,
            itemCount: incomplete.count,
            expiresAt: Self.endOfDay(now, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        )
        return try apply(.start, taskID: taskID, now: now)
    }

    public func skipPlanning(now: Date = Date()) throws -> TodaySnapshot {
        let policy = try userPolicyStore.current()?.policy ?? UserPolicy.defaults()
        let localDay = Self.localDayKey(now, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        _ = try planningInvitations.beginUnplannedDay(
            localDay: localDay,
            itemCount: try reminders.loadIncomplete().count,
            expiresAt: Self.endOfDay(now, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        )
        return try snapshot(now: now)
    }

    public func reminderCompletionSyncState(taskID: String) throws -> ReminderCompletionSyncState {
        let command = try outbox.latestCommand(type: .completeReminder, entityID: taskID)
        let taskTitle = try command.flatMap { _ in
            try taskHistory.latestCompletedEntry(for: taskID)?.title
        }
        return ReminderCompletionSyncState(
            taskID: taskID,
            command: command,
            taskTitle: taskTitle
        )
    }

    public func retryReminderCompletion(taskID: String) throws -> ReminderCompletionSyncState {
        let state = try reminderCompletionSyncState(taskID: taskID)
        guard state.canRetry, let commandID = state.commandID else {
            throw TodayDashboardAgentError.completionNotRetryable
        }
        try outbox.retryFailed(commandID: commandID)
        return try reminderCompletionSyncState(taskID: taskID)
    }

    public func cachedSnapshot(for day: Date = Date()) throws -> TodaySnapshot? {
        try snapshots.load(for: day)
    }

    private func activeTimeComparison(
        taskID: String,
        active: ActiveTaskSnapshot?,
        observations: [BehaviorObservation],
        now: Date
    ) -> ActiveTaskTimeComparison? {
        guard let active, active.taskID == taskID, let activeSince = active.startedAt else { return nil }
        return ActiveTaskTimeComparison(
            elapsedMinutes: active.elapsedMinutes,
            activeSince: activeSince,
            observations: observations,
            now: now
        )
    }

    private func reminderPriority(_ rawValue: Int) -> ReminderPriority {
        ReminderPriority.fromEventKit(rawValue)
    }

    private static func permissionSnapshot(for entityType: EKEntityType) -> (state: String, detail: String) {
        switch EKEventStore.authorizationStatus(for: entityType) {
        case .fullAccess:
            return ("available", entityType == .event ? "Agent has full Apple Calendar access" : "Agent has full Apple Reminders access")
        case .writeOnly:
            return ("limited", "Agent has write-only Apple Calendar access and cannot inspect existing commitments")
        case .denied:
            return ("blocked", entityType == .event ? "Apple Calendar permission is denied" : "Apple Reminders permission is denied")
        case .restricted:
            return ("blocked", entityType == .event ? "Apple Calendar access is restricted" : "Apple Reminders access is restricted")
        case .notDetermined:
            return ("not_connected", entityType == .event ? "Apple Calendar permission has not been granted" : "Apple Reminders permission has not been granted")
        case .authorized:
            return ("available", entityType == .event ? "Agent has Apple Calendar access" : "Agent has Apple Reminders access")
        @unknown default:
            return ("unknown", "EventKit returned an unknown permission state")
        }
    }

    private func taskType(for title: String) -> String? {
        title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).first.map { $0.lowercased() }
    }

    private func learnedEstimateSuggestion(
        for reminder: ReminderSourceSnapshot,
        currentEstimateMinutes: Int
    ) -> LearnedEstimateSuggestion? {
        let context = EstimateLearningContext(
            taskType: taskType(for: reminder.title),
            project: reminder.listName
        )
        guard let aggregate = try? learning.estimateAggregate(for: context),
              let samples = try? learning.estimateEvidenceSamples(for: context)
        else { return nil }
        let evidenceIDs = Set(aggregate.proposal.evidenceIDs)
        let eligibleActualMinutes = samples
            .filter { evidenceIDs.contains($0.id) }
            .map(\.actualAlignedMinutes)
        guard eligibleActualMinutes.count == aggregate.proposal.sampleCount,
              let minimumActualMinutes = eligibleActualMinutes.min(),
              let maximumActualMinutes = eligibleActualMinutes.max()
        else { return nil }
        let policy = EstimateLearningPolicy()
        let scaledMinutes = Double(max(1, currentEstimateMinutes)) * aggregate.proposal.appliedRatio
        let roundedMinutes = Int((scaledMinutes / 5).rounded() * 5)
        let recommendedMinutes = min(
            max(roundedMinutes, policy.minimumRecommendedMinutes),
            policy.maximumRecommendedMinutes
        )
        return LearnedEstimateSuggestion(
            recommendedMinutes: recommendedMinutes,
            sampleCount: aggregate.proposal.sampleCount,
            minimumActualMinutes: minimumActualMinutes,
            maximumActualMinutes: maximumActualMinutes,
            confidence: aggregate.confidence
        )
    }

    private static func localDayKey(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func endOfDay(_ date: Date, timeZoneIdentifier: String) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }
}

public enum TodayDashboardAgentError: LocalizedError, Equatable {
    case unavailableTask
    case completionNotRetryable

    public var errorDescription: String? {
        switch self {
        case .unavailableTask:
            "That Reminder is no longer available. Refresh tasks and choose another one."
        case .completionNotRetryable:
            "This completion is not waiting for a manual retry. Refresh its sync status before trying again."
        }
    }
}
