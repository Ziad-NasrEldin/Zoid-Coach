import Foundation
import ZoidCoachCore

public struct AgentPlanSchedulingResult: Equatable, Sendable {
    public let scheduledBlockCount: Int
    public let unscheduledTaskIDs: [String]
    public let reminderMutationCount: Int
    public let obsoleteBlockDeletionCount: Int

    public init(scheduledBlockCount: Int, unscheduledTaskIDs: [String], reminderMutationCount: Int, obsoleteBlockDeletionCount: Int) {
        self.scheduledBlockCount = scheduledBlockCount
        self.unscheduledTaskIDs = unscheduledTaskIDs
        self.reminderMutationCount = reminderMutationCount
        self.obsoleteBlockDeletionCount = obsoleteBlockDeletionCount
    }
}

public final class AgentPlanScheduler: @unchecked Sendable {
    private let plans: AutonomousPlanStore
    private let reminders: ReminderSnapshotStore
    private let outbox: ActionOutboxStore
    private let calendar: any CalendarAvailabilitySource

    public init(plans: AutonomousPlanStore, reminders: ReminderSnapshotStore, outbox: ActionOutboxStore, calendar: any CalendarAvailabilitySource) {
        self.plans = plans
        self.reminders = reminders
        self.outbox = outbox
        self.calendar = calendar
    }

    public func enqueueSchedule(for day: Date, policy: UserPolicy, policyVersion: Int) async throws -> AgentPlanSchedulingResult {
        guard !policy.automationPause.isPaused else {
            return AgentPlanSchedulingResult(scheduledBlockCount: 0, unscheduledTaskIDs: [], reminderMutationCount: 0, obsoleteBlockDeletionCount: 0)
        }
        let plan = try plans.loadDailyPlan(for: day)
        let reminderByID = Dictionary(uniqueKeysWithValues: try reminders.loadIncomplete().map { ($0.id, $0) })
        let workIntervals = policy.schedule.workIntervals(on: day)
        guard !plan.isEmpty, let firstStart = workIntervals.map(\.start).min(), let finalEnd = workIntervals.map(\.end).max() else {
            return AgentPlanSchedulingResult(scheduledBlockCount: 0, unscheduledTaskIDs: plan.map(\.reminderID), reminderMutationCount: 0, obsoleteBlockDeletionCount: 0)
        }
        let commitments = try await calendar.commitments(
            from: firstStart,
            through: finalEnd,
            calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
        )
        let fixed = commitments.filter { $0.ownershipToken == nil }
        let free = workIntervals.flatMap { interval in freeIntervals(in: interval, commitments: fixed) }
        let tasks = plan.compactMap { entry -> SchedulableTask? in
            guard let task = reminderByID[entry.reminderID] else { return nil }
            return SchedulableTask(id: entry.reminderID, title: task.title, durationMinutes: entry.estimateMinutes)
        }
        let schedule = CalendarBlockScheduler().schedule(tasks: tasks, availableIntervals: free, transitionMinutes: 10)
        let dayKey = localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        let desiredTokens = Set(schedule.blocks.map { ownershipToken(dayKey: dayKey, taskID: $0.taskID) })
        var deletions = 0
        for existing in commitments where existing.ownershipToken != nil {
            guard let token = existing.ownershipToken, !desiredTokens.contains(token) else { continue }
            let result = try outbox.enqueue(
                type: .deleteCalendarBlock,
                entityID: existing.id,
                desiredState: .deleteOwnedCalendarBlock(ownershipToken: token),
                planVersion: policyVersion
            )
            if result.wasInserted { deletions += 1 }
        }

        var blockCount = 0
        for block in schedule.blocks {
            guard let task = reminderByID[block.taskID] else { continue }
            let token = ownershipToken(dayKey: dayKey, taskID: block.taskID)
            let result = try outbox.enqueue(
                type: .reconcileCalendarBlock,
                entityID: block.taskID,
                desiredState: .calendarBlock(CalendarBlockDesiredState(
                    title: task.title,
                    start: block.start,
                    end: block.end,
                    ownershipToken: token,
                    planItemID: block.taskID
                )),
                planVersion: policyVersion
            )
            if result.wasInserted { blockCount += 1 }
        }

        var reminderMutations = 0
        let dueDate = finalEnd
        for entry in plan {
            guard let task = reminderByID[entry.reminderID] else { continue }
            let marker = "plan:\(dayKey):rank:\(entry.rank)"
            let priorityResult = try outbox.enqueue(
                type: .setReminderPriority,
                entityID: entry.reminderID,
                desiredState: .reminder(ReminderDesiredState(priority: entry.rank == 1 ? 1 : 5, metadataMarker: marker)),
                planVersion: policyVersion
            )
            if priorityResult.wasInserted { reminderMutations += 1 }
            if task.dueDate == nil {
                let dueResult = try outbox.enqueue(
                    type: .setReminderDueDate,
                    entityID: entry.reminderID,
                    desiredState: .reminder(ReminderDesiredState(dueDate: dueDate, metadataMarker: marker)),
                    planVersion: policyVersion
                )
                if dueResult.wasInserted { reminderMutations += 1 }
            }
        }
        return AgentPlanSchedulingResult(
            scheduledBlockCount: blockCount,
            unscheduledTaskIDs: schedule.unscheduledTaskIDs,
            reminderMutationCount: reminderMutations,
            obsoleteBlockDeletionCount: deletions
        )
    }

    private func freeIntervals(in workWindow: CalendarInterval, commitments: [CalendarCommitment]) -> [CalendarInterval] {
        var cursor = workWindow.start
        var result: [CalendarInterval] = []
        for commitment in commitments.sorted(by: { $0.start < $1.start }) where commitment.end > workWindow.start && commitment.start < workWindow.end {
            let occupiedStart = max(commitment.start, workWindow.start)
            let occupiedEnd = min(commitment.end, workWindow.end)
            if cursor < occupiedStart { result.append(CalendarInterval(start: cursor, end: occupiedStart)) }
            cursor = max(cursor, occupiedEnd)
        }
        if cursor < workWindow.end { result.append(CalendarInterval(start: cursor, end: workWindow.end)) }
        return result
    }

    private func ownershipToken(dayKey: String, taskID: String) -> String {
        "zoid-plan:\(dayKey):\(taskID)"
    }

    private func localDayKey(_ date: Date, timeZoneIdentifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
