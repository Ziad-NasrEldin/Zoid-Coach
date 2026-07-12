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
    }

    public func snapshot(now: Date = Date()) throws -> TodaySnapshot {
        let plan = try plans.loadDailyPlan(for: now)
        let reminderSnapshots = try reminders.loadIncomplete()
        let reminderByID = Dictionary(uniqueKeysWithValues: reminderSnapshots.map { ($0.id, $0) })
        let executionByID = try execution.snapshot(for: plan.map(\.reminderID), now: now)
        let rows = plan.compactMap { entry -> TodayTaskRow? in
            guard let reminder = reminderByID[entry.reminderID] else { return nil }
            let current = executionByID[entry.reminderID]
            return TodayTaskRow(
                taskID: reminder.id,
                title: reminder.title,
                estimateMinutes: entry.estimateMinutes,
                dueDate: reminder.dueDate,
                urgency: TaskUrgency.resolve(dueDate: reminder.dueDate, priority: reminderPriority(reminder.priority), referenceDate: now),
                state: current?.state ?? .ready,
                elapsedMinutes: current?.elapsedMinutes ?? 0,
                isMainObjective: entry.isMainObjective
            )
        }
        let behavior = BehaviorSessionizer().summarize(observations: try archive.behaviorObservations(for: now), now: now)
        let gamingPolicy = try userPolicyStore.currentGamingPolicy()
        let rewardMinutes = try snapshots.priorityRewardMinutes(policy: gamingPolicy, day: now)
        let gaming = GamingStatusCalculator().status(
            policy: gamingPolicy,
            gamingMinutes: behavior.summary.gamingMinutes,
            appliedRewardMinutes: rewardMinutes,
            coverage: behavior.coverage
        )
        let active = try execution.activeTask(now: now)
        let recommendation = active == nil ? NextTaskRecommender().recommend(tasks: rows, referenceDate: now, availableMinutes: 60, coverage: behavior.coverage) : NextTaskRecommendation(taskID: active?.taskID, sentence: "Continue the active task before starting another one.", reasons: [], coverageUncertainty: behavior.coverage.isLimited ? behavior.coverage.explanation : nil)
        let plannedIDs = Set(rows.map(\.taskID))
        let unplanned = reminderSnapshots
            .filter { !plannedIDs.contains($0.id) }
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
        let timeZoneIdentifier = (try? userPolicyStore.current()?.policy.schedule.timeZoneIdentifier) ?? TimeZone.current.identifier
        let snapshot = TodaySnapshot(
            localDate: now,
            timeZoneIdentifier: timeZoneIdentifier,
            mainObjective: rows.first(where: \.isMainObjective)?.title,
            taskRows: rows,
            activeTask: active,
            recommendation: recommendation,
            behavior: behavior.summary,
            coverage: behavior.coverage,
            gaming: gaming,
            sourceFreshnessExplanation: sourceSnapshots.map { "\($0.sourceID): \($0.state)" }.joined(separator: " · "),
            unplannedReminders: unplanned,
            sources: sourceSnapshots
        )
        try snapshots.save(snapshot, for: now)
        return snapshot
    }

    @discardableResult
    public func apply(_ command: TaskActivityCommand, taskID: String, now: Date = Date()) throws -> TodaySnapshot {
        let previousSnapshot = try snapshots.load(for: now)
        let previousExecution = try execution.snapshot(for: [taskID], now: now)[taskID]
        let activeBefore = try execution.activeTask(now: now)
        let reminderBefore = try reminders.loadIncomplete().first(where: { $0.id == taskID })
        try execution.apply(command, taskID: taskID, at: now)
        switch command {
        case .complete:
            _ = try outbox.enqueue(
                type: .completeReminder,
                entityID: taskID,
                desiredState: .completeReminder,
                planVersion: 1
            )
            try taskHistory.record(taskID: taskID, state: .completed, at: now)
        case .reschedule:
            try taskHistory.record(taskID: taskID, state: .postponed, at: now)
        case .start:
            try taskHistory.record(taskID: taskID, state: .selected, at: now)
        case .pause, .resume, .block:
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

    public func cachedSnapshot(for day: Date = Date()) throws -> TodaySnapshot? {
        try snapshots.load(for: day)
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
}
