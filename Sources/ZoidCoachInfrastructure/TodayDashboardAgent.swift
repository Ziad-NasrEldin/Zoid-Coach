import Foundation
import EventKit
import SQLite3
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
    private let mutationOperations: TaskMutationOperationStore
    private let databaseURL: URL
    private let mutationLockRetryDelays: [TimeInterval]
    private let mutationStepObserver: @Sendable (String) throws -> Void

    public init(
        databaseURL: URL = ZoidCoachStorage.databaseURL(),
        mutationLockRetryDelays: [TimeInterval] = [0.10, 0.30, 0.60],
        mutationStepObserver: @escaping @Sendable (String) throws -> Void = { _ in }
    ) throws {
        self.databaseURL = databaseURL
        self.mutationLockRetryDelays = mutationLockRetryDelays.map { max(0, $0) }
        self.mutationStepObserver = mutationStepObserver
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
        mutationOperations = try TaskMutationOperationStore(databaseURL: databaseURL)
        planningInvitations = PlanningInvitationService(
            store: try PromptInboxStore(databaseURL: databaseURL)
        )
    }

    public func snapshot(now: Date = Date()) throws -> TodaySnapshot {
        let previousSnapshot = try snapshots.load(for: now)
        let activeBeforeSourceRefresh = try execution.activeTask(now: now)
        let activeSourceSnapshot = try activeBeforeSourceRefresh.flatMap { try reminders.snapshot(forID: $0.taskID) }
        let activeSourceKind = activeSourceSnapshot?.sourceKind
        let activeCompletionHistory: CompletedTaskHistoryEntry? = try activeBeforeSourceRefresh.flatMap { active in
            try taskHistory.latestCompletedEntry(for: active.taskID).flatMap { entry in
                guard entry.sourceKind == .reminders,
                      active.startedAt.map({ entry.completedAt >= $0 }) ?? true
                else { return nil }
                return entry
            }
        }
        if let active = activeBeforeSourceRefresh,
           activeSourceKind == nil,
           activeCompletionHistory == nil,
            previousSnapshot?.taskRows.contains(where: { $0.taskID == active.taskID }) == true {
            try execution.pauseForDeletedReminder(taskID: active.taskID, at: now)
        }
        let reminderListPolicy = try userPolicyStore.current()?.policy.reminderLists ?? .legacyAllLists
        let reminderSnapshots = try reminders.loadIncomplete().filter { reminder in
            reminder.sourceKind == .local || reminderListPolicy.includes(listID: reminder.listID)
        }
        if let active = activeBeforeSourceRefresh,
            (activeSourceSnapshot?.sourceKind == .reminders && activeSourceSnapshot?.isCompleted == true)
                || activeCompletionHistory != nil {
            let previousRow = previousSnapshot?.taskRows.first(where: { $0.taskID == active.taskID })
            try execution.apply(.complete, taskID: active.taskID, at: now)
            if activeCompletionHistory == nil {
                try taskHistory.record(
                    taskID: active.taskID,
                    state: .completed,
                    title: previousRow?.title ?? activeSourceSnapshot?.title,
                    sourceKind: .reminders,
                    at: now
                )
            }
        }
        let plan = try plans.loadDailyPlan(for: now)
        var reminderByID: [String: ReminderSourceSnapshot] = [:]
        for reminder in reminderSnapshots {
            reminderByID[reminder.id] = reminder
        }
        let executionByID = try execution.snapshot(for: reminderSnapshots.map(\.id), now: now)
        let behaviorObservations = try archive.behaviorObservations(for: now)
        let behavior = BehaviorSessionizer().summarize(observations: behaviorObservations, now: now)
        let active = try execution.activeTask(now: now)
        var seenPlannedReminderIDs: Set<String> = []
        var rows = plan.compactMap { entry -> TodayTaskRow? in
            if !seenPlannedReminderIDs.insert(entry.reminderID).inserted { return nil }
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
        let userPolicy = try userPolicyStore.current()?.policy ?? UserPolicy.defaults()
        let gamingPolicy = userPolicy.gaming
        let rewardMinutes = try snapshots.priorityRewardMinutes(policy: gamingPolicy, day: now)
        let gaming = GamingStatusCalculator().status(
            policy: gamingPolicy,
            gamingMinutes: behavior.summary.meaningfulGamingMinutes,
            appliedRewardMinutes: rewardMinutes,
            coverage: behavior.coverage,
            isWithinWorkWindow: userPolicy.schedule.isWithinWorkWindow(at: now)
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
        if let activeBeforeSourceRefresh,
           let activeSourceSnapshot,
           activeSourceSnapshot.sourceKind == .reminders,
           activeSourceSnapshot.isCompleted,
           !rows.contains(where: { $0.taskID == activeBeforeSourceRefresh.taskID }),
           let current = try execution.snapshot(
               for: [activeBeforeSourceRefresh.taskID],
               now: now
           )[activeBeforeSourceRefresh.taskID],
           current.state == .completed {
            rows.append(externallyCompletedReminderRow(
                from: activeSourceSnapshot,
                execution: current,
                referenceDate: now
            ))
        }
        if let activeBeforeSourceRefresh,
           activeSourceSnapshot == nil,
           let activeCompletionHistory,
           !rows.contains(where: { $0.taskID == activeBeforeSourceRefresh.taskID }),
           let current = try execution.snapshot(
               for: [activeBeforeSourceRefresh.taskID],
               now: now
           )[activeBeforeSourceRefresh.taskID],
           current.state == .completed {
            rows.append(externallyCompletedReminderRow(
                from: activeCompletionHistory,
                execution: current
            ))
        }
        if let previousSnapshot {
            for previousRow in previousSnapshot.taskRows where !rows.contains(where: { $0.taskID == previousRow.taskID }) {
                if let reminder = reminderByID[previousRow.taskID],
                   let current = executionByID[previousRow.taskID],
                   current.state == .paused,
                   previousRow.state == .active || previousRow.state == .paused,
                   try execution.latestIntervalStartedAt(taskID: previousRow.taskID, endingAt: now) != nil {
                    rows.append(TodayTaskRow(
                        taskID: reminder.id,
                        title: reminder.title,
                        estimateMinutes: previousRow.estimateMinutes,
                        dueDate: reminder.dueDate,
                        urgency: TaskUrgency.resolve(
                            dueDate: reminder.dueDate,
                            priority: reminderPriority(reminder.priority),
                            referenceDate: now
                        ),
                        state: .paused,
                        elapsedMinutes: current.elapsedMinutes,
                        latestPauseReason: current.latestPauseReason,
                        acceptedBreak: current.acceptedBreak,
                        sprint: current.sprint,
                        isMainObjective: previousRow.isMainObjective,
                        isLocked: previousRow.isLocked,
                        isOptional: previousRow.isOptional ?? false,
                        blockedReason: previousRow.blockedReason,
                        deferredUntil: previousRow.deferredUntil,
                        learnedEstimateSuggestion: previousRow.learnedEstimateSuggestion
                    ))
                    continue
                }
                guard reminderByID[previousRow.taskID] == nil,
                      let current = try execution.snapshot(for: [previousRow.taskID], now: now)[previousRow.taskID]
                else { continue }
                let sourceKind = try reminders.sourceKind(forID: previousRow.taskID)
                if (sourceKind == .reminders || previousRow.completionReason == .appleReminderCompleted),
                   current.state == .completed {
                    rows.append(externallyCompletedReminderRow(from: previousRow, execution: current))
                } else if sourceKind == nil,
                          current.state == .paused,
                          current.latestPauseReason == .reminderDeleted {
                    rows.append(deletedReminderRow(from: previousRow, execution: current))
                }
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

    private func externallyCompletedReminderRow(
        from previous: TodayTaskRow,
        execution current: TaskExecutionSnapshot
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: previous.taskID,
            title: previous.title,
            estimateMinutes: previous.estimateMinutes,
            dueDate: previous.dueDate,
            urgency: previous.urgency,
            state: .completed,
            elapsedMinutes: current.elapsedMinutes,
            completionReason: .appleReminderCompleted,
            sprint: current.sprint,
            isMainObjective: previous.isMainObjective,
            isLocked: previous.isLocked,
            isOptional: previous.isOptional ?? false,
            blockedReason: previous.blockedReason,
            deferredUntil: previous.deferredUntil,
            learnedEstimateSuggestion: previous.learnedEstimateSuggestion
        )
    }

    private func externallyCompletedReminderRow(
        from history: CompletedTaskHistoryEntry,
        execution current: TaskExecutionSnapshot
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: history.taskID,
            title: history.title,
            estimateMinutes: 30,
            dueDate: nil,
            urgency: .low,
            state: .completed,
            elapsedMinutes: current.elapsedMinutes,
            completionReason: .appleReminderCompleted,
            sprint: current.sprint,
            isMainObjective: false
        )
    }

    private func externallyCompletedReminderRow(
        from source: ReminderSourceSnapshot,
        execution current: TaskExecutionSnapshot,
        referenceDate: Date
    ) -> TodayTaskRow {
        TodayTaskRow(
            taskID: source.id,
            title: source.title,
            estimateMinutes: 30,
            dueDate: source.dueDate,
            urgency: TaskUrgency.resolve(
                dueDate: source.dueDate,
                priority: reminderPriority(source.priority),
                referenceDate: referenceDate
            ),
            state: .completed,
            elapsedMinutes: current.elapsedMinutes,
            completionReason: .appleReminderCompleted,
            sprint: current.sprint,
            isMainObjective: false
        )
    }

    @discardableResult
    public func apply(
        _ command: TaskActivityCommand,
        taskID: String,
        blockedReason: String? = nil,
        operationID: UUID = UUID(),
        now: Date = Date()
    ) throws -> TodaySnapshot {
        try waitForMutationWriteAvailability()
        let operation = try mutationOperations.begin(
            id: operationID,
            taskID: taskID,
            command: command,
            blockedReason: blockedReason,
            requestedAt: now
        )
        if operation.state == .completed, let result = operation.result {
            return result
        }
        if operation.state == .failed {
            throw TodayDashboardAgentError.validationFailed(
                operation.lastDiagnostic ?? "This task change is not valid."
            )
        }
        var retryIndex = 0
        while true {
            do {
                let result = try applyPending(
                    command,
                    taskID: taskID,
                    blockedReason: blockedReason,
                    operationID: operationID,
                    now: operation.requestedAt
                )
                try mutationOperations.complete(operationID: operationID, result: result)
                return result
            } catch {
                if Self.isTerminalValidationError(error) {
                    try? mutationOperations.failValidation(operationID: operationID, diagnostic: error.localizedDescription)
                    throw error
                } else {
                    try? mutationOperations.recordPendingFailure(operationID: operationID, diagnostic: error.localizedDescription)
                }
                guard retryIndex < mutationLockRetryDelays.count, databaseHasCompetingWriteLock() else { throw error }
                Thread.sleep(forTimeInterval: mutationLockRetryDelays[retryIndex])
                retryIndex += 1
            }
        }
    }

    private func applyPending(
        _ command: TaskActivityCommand,
        taskID: String,
        blockedReason: String?,
        operationID: UUID,
        now: Date
    ) throws -> TodaySnapshot {
        let previousSnapshot = try snapshots.load(for: now)
        let activeBefore = try execution.activeTask(now: now)
        let reminderBefore = try reminders.snapshot(forID: taskID)
        let sourceKind = try reminders.sourceKind(forID: taskID)
        if try !mutationOperations.hasCompletedStep(operationID: operationID, step: "execution") {
            try execution.apply(command, taskID: taskID, blockedReason: blockedReason, operationID: operationID, at: now)
            try completeMutationStep(operationID: operationID, step: "execution", at: now)
        }
        if command == .block,
           try !mutationOperations.hasCompletedStep(operationID: operationID, step: "plan-promotion") {
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
            try completeMutationStep(operationID: operationID, step: "plan-promotion", at: now)
        }
        switch command {
        case .complete:
            if try !mutationOperations.hasCompletedStep(operationID: operationID, step: "reminder-completion") && sourceKind == .local {
                let timeZoneIdentifier = (try? userPolicyStore.current()?.policy.schedule.timeZoneIdentifier)
                    ?? TimeZone.current.identifier
                try mutationOperations.completeLocalReminder(
                    operationID: operationID,
                    taskID: taskID,
                    completedAt: now,
                    timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
                )
                try mutationStepObserver("reminder-completion")
            } else if sourceKind != .local,
                      try !mutationOperations.hasCompletedStep(operationID: operationID, step: "outbox") {
                _ = try outbox.enqueue(
                    type: .completeReminder,
                    entityID: taskID,
                    desiredState: .completeReminder,
                    planVersion: 1
                )
                try completeMutationStep(operationID: operationID, step: "outbox", at: now)
            }
            if try !mutationOperations.hasCompletedStep(operationID: operationID, step: "history") {
                try taskHistory.record(
                    taskID: taskID,
                    state: .completed,
                    title: reminderBefore?.title,
                    sourceKind: reminderBefore?.sourceKind,
                    operationID: operationID,
                    at: now
                )
                try completeMutationStep(operationID: operationID, step: "history", at: now)
            }
        case .reschedule:
            if try !mutationOperations.hasCompletedStep(operationID: operationID, step: "history") {
                try taskHistory.record(taskID: taskID, state: .postponed, operationID: operationID, at: now)
                try completeMutationStep(operationID: operationID, step: "history", at: now)
            }
        case .start, .startSprint10, .startSprint20, .startSprint25:
            if try !mutationOperations.hasCompletedStep(operationID: operationID, step: "history") {
                try taskHistory.record(taskID: taskID, state: .selected, operationID: operationID, at: now)
                try completeMutationStep(operationID: operationID, step: "history", at: now)
            }
        case .pause, .pauseForBreak, .pauseForExternalInterruption, .pauseDoneForNow, .pauseForEndOfDay, .resume, .block, .continueOpenEnded:
            break
        }
        if command == .complete,
           try !mutationOperations.hasCompletedStep(operationID: operationID, step: "reward"),
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
            try completeMutationStep(operationID: operationID, step: "reward", at: now)
        }
        if command == .complete,
           try !mutationOperations.hasCompletedStep(operationID: operationID, step: "learning"),
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
            let persistedStartedAt = try execution.latestIntervalStartedAt(taskID: taskID, endingAt: now)
            if let startedAt = activeBefore?.taskID == taskID ? activeBefore?.startedAt : persistedStartedAt, startedAt < now {
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
            try completeMutationStep(operationID: operationID, step: "learning", at: now)
        }
        let result: TodaySnapshot
        if try mutationOperations.hasCompletedStep(operationID: operationID, step: "today-snapshot"),
           let stored = try snapshots.load(for: now) {
            result = stored
        } else {
            result = try snapshot(now: now)
            try completeMutationStep(operationID: operationID, step: "today-snapshot", at: now)
        }
        return result
    }

    private func completeMutationStep(operationID: UUID, step: String, at date: Date) throws {
        try mutationOperations.completeStep(operationID: operationID, step: step, at: date)
        try mutationStepObserver(step)
    }

    private static func isTerminalValidationError(_ error: Error) -> Bool {
        guard let executionError = error as? TaskExecutionStoreError else { return false }
        switch executionError {
        case .invalidSprintDuration, .invalidBlockedReason, .sprintUnavailable, .sprintStillActive:
            return true
        case .openDatabase, .schema, .read, .write:
            return false
        }
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

    private func databaseHasCompetingWriteLock() -> Bool {
        var probe: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &probe, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let probe else { return false }
        defer { sqlite3_close(probe) }
        sqlite3_busy_timeout(probe, 5)
        let result = sqlite3_exec(probe, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        if result == SQLITE_OK {
            _ = sqlite3_exec(probe, "ROLLBACK;", nil, nil, nil)
            return false
        }
        let primary = result & 0xFF
        return primary == SQLITE_BUSY || primary == SQLITE_LOCKED
    }

    private func waitForMutationWriteAvailability() throws {
        var retryIndex = 0
        while databaseHasCompetingWriteLock() {
            guard retryIndex < mutationLockRetryDelays.count else {
                throw TodayDashboardAgentError.databaseTemporarilyLocked
            }
            Thread.sleep(forTimeInterval: mutationLockRetryDelays[retryIndex])
            retryIndex += 1
        }
    }
}

public enum TodayDashboardAgentError: LocalizedError, Equatable {
    case unavailableTask
    case completionNotRetryable
    case databaseTemporarilyLocked
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailableTask:
            "That Reminder is no longer available. Refresh tasks and choose another one."
        case .completionNotRetryable:
            "This completion is not waiting for a manual retry. Refresh its sync status before trying again."
        case .databaseTemporarilyLocked:
            "The local database is still busy. The last confirmed task state is unchanged. Try again in a moment."
        case let .validationFailed(message):
            message
        }
    }
}
