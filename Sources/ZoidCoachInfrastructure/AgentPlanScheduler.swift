import Foundation
import ZoidCoachCore

public struct AgentPlanSchedulingResult: Equatable, Sendable {
    public let scheduledBlockCount: Int
    public let unscheduledTaskIDs: [String]
    public let reminderMutationCount: Int
    public let obsoleteBlockDeletionCount: Int
    public let commandIDs: [String]

    public init(scheduledBlockCount: Int, unscheduledTaskIDs: [String], reminderMutationCount: Int, obsoleteBlockDeletionCount: Int, commandIDs: [String] = []) {
        self.scheduledBlockCount = scheduledBlockCount
        self.unscheduledTaskIDs = unscheduledTaskIDs
        self.reminderMutationCount = reminderMutationCount
        self.obsoleteBlockDeletionCount = obsoleteBlockDeletionCount
        self.commandIDs = commandIDs
    }
}

public final class AgentPlanScheduler: @unchecked Sendable {
    private let plans: AutonomousPlanStore
    private let reminders: ReminderSnapshotStore
    private let outbox: ActionOutboxStore
    private let calendar: any CalendarAvailabilitySource
    private let learning: LearningAggregateStore?
    private let now: @Sendable () -> Date

    public init(
        plans: AutonomousPlanStore,
        reminders: ReminderSnapshotStore,
        outbox: ActionOutboxStore,
        calendar: any CalendarAvailabilitySource,
        learning: LearningAggregateStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.plans = plans
        self.reminders = reminders
        self.outbox = outbox
        self.calendar = calendar
        self.learning = learning
        self.now = now
    }

    public func enqueueSchedule(
        for day: Date,
        policy: UserPolicy,
        policyVersion: Int,
        origin: ActionOrigin = .explicitUser
    ) async throws -> AgentPlanSchedulingResult {
        guard !policy.automationPause.isPaused else {
            return AgentPlanSchedulingResult(scheduledBlockCount: 0, unscheduledTaskIDs: [], reminderMutationCount: 0, obsoleteBlockDeletionCount: 0)
        }
        let plan = try plans.loadDailyPlan(for: day)
        let reminderByID = Dictionary(uniqueKeysWithValues: try reminders.loadIncomplete().map { ($0.id, $0) })
        let schedulingTime = now()
        let workIntervals = policy.schedule.workIntervals(on: day).compactMap { interval -> CalendarInterval? in
            let start = max(interval.start, schedulingTime)
            guard start < interval.end else { return nil }
            return CalendarInterval(start: start, end: interval.end)
        }
        guard !plan.isEmpty, let firstStart = workIntervals.map(\.start).min(), let finalEnd = workIntervals.map(\.end).max() else {
            return AgentPlanSchedulingResult(scheduledBlockCount: 0, unscheduledTaskIDs: plan.map(\.reminderID), reminderMutationCount: 0, obsoleteBlockDeletionCount: 0)
        }
        let commitments = try await calendar.commitments(
            from: firstStart,
            through: finalEnd,
            calendarIdentifiers: policy.calendar.visibleCalendarIdentifiers
        )
        let protectedOwned = commitments.filter { $0.ownershipToken != nil && $0.start <= schedulingTime }
        let protectedTokens = Set(protectedOwned.compactMap(\.ownershipToken))
        let dayKey = localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier)
        let ownershipPrefix = "zoid-plan:\(dayKey):"
        let protectedTaskIDs = Set(protectedTokens.compactMap { token -> String? in
            guard token.hasPrefix(ownershipPrefix) else { return nil }
            return String(token.dropFirst(ownershipPrefix.count))
        })
        for commitment in protectedOwned {
            _ = try outbox.cancelPendingCommands(type: .deleteCalendarBlock, entityID: commitment.id)
        }
        for taskID in protectedTaskIDs {
            _ = try outbox.cancelPendingCommands(type: .reconcileCalendarBlock, entityID: taskID)
        }
        let fixed = commitments.filter { $0.ownershipToken == nil || $0.start <= schedulingTime }
        let free = workIntervals.flatMap { interval in freeIntervals(in: interval, commitments: fixed) }
        let tasks = plan.compactMap { entry -> SchedulableTask? in
            guard let task = reminderByID[entry.reminderID],
                  !protectedTaskIDs.contains(entry.reminderID)
            else { return nil }
            return SchedulableTask(id: entry.reminderID, title: task.title, durationMinutes: entry.estimateMinutes)
        }
        let preferredInterval = try learnedPreferredInterval(for: day, policy: policy)
        let schedulingIntervals = splitForPreference(free, preferred: preferredInterval)
        let schedule = CalendarBlockScheduler().schedule(
            tasks: tasks,
            availableIntervals: schedulingIntervals,
            transitionMinutes: 10,
            preferredInterval: preferredInterval
        )
        guard schedule.unscheduledTaskIDs.isEmpty else {
            return AgentPlanSchedulingResult(
                scheduledBlockCount: 0,
                unscheduledTaskIDs: schedule.unscheduledTaskIDs,
                reminderMutationCount: 0,
                obsoleteBlockDeletionCount: 0
            )
        }
        let desiredTokens = Set(schedule.blocks.map { ownershipToken(dayKey: dayKey, taskID: $0.taskID) }).union(protectedTokens)
        var deletions = 0
        var commandIDs: [String] = []
        for existing in commitments where existing.ownershipToken != nil && existing.start > schedulingTime {
            guard let token = existing.ownershipToken, !desiredTokens.contains(token) else { continue }
            let result = try outbox.enqueue(
                type: .deleteCalendarBlock,
                entityID: existing.id,
                desiredState: .deleteOwnedCalendarBlock(ownershipToken: token),
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            )
            if result.wasInserted { deletions += 1 }
            commandIDs.append(result.command.id)
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
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            )
            if result.wasInserted { blockCount += 1 }
            commandIDs.append(result.command.id)
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
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            )
            if priorityResult.wasInserted { reminderMutations += 1 }
            commandIDs.append(priorityResult.command.id)
            if task.dueDate == nil {
                let dueResult = try outbox.enqueue(
                    type: .setReminderDueDate,
                    entityID: entry.reminderID,
                    desiredState: .reminder(ReminderDesiredState(dueDate: dueDate, metadataMarker: marker)),
                    planVersion: policyVersion,
                    supersedingPending: true,
                    origin: origin
                )
                if dueResult.wasInserted { reminderMutations += 1 }
                commandIDs.append(dueResult.command.id)
            }
        }
        return AgentPlanSchedulingResult(
            scheduledBlockCount: blockCount,
            unscheduledTaskIDs: schedule.unscheduledTaskIDs,
            reminderMutationCount: reminderMutations,
            obsoleteBlockDeletionCount: deletions,
            commandIDs: Array(Set(commandIDs)).sorted()
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

    private func learnedPreferredInterval(for day: Date, policy: UserPolicy) throws -> CalendarInterval? {
        guard let aggregate = try learning?.preferredWorkWindowAggregate(
            timeZoneIdentifier: policy.schedule.timeZoneIdentifier
        ), aggregate.confidence >= 0.5,
              let timeZone = TimeZone(identifier: policy.schedule.timeZoneIdentifier)
        else { return nil }
        let window = aggregate.proposal.preferredWindow
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
              window.weekdays.contains(weekday),
              let start = calendar.date(
                bySettingHour: window.start.hour,
                minute: window.start.minute,
                second: 0,
                of: day
              ),
              let end = calendar.date(
                bySettingHour: window.end.hour,
                minute: window.end.minute,
                second: 0,
                of: day
              ), start < end
        else { return nil }
        return CalendarInterval(start: start, end: end)
    }

    private func splitForPreference(
        _ intervals: [CalendarInterval],
        preferred: CalendarInterval?
    ) -> [CalendarInterval] {
        guard let preferred else { return intervals }
        return intervals.flatMap { interval in
            var boundaries = [interval.start, interval.end]
            if preferred.start > interval.start, preferred.start < interval.end { boundaries.append(preferred.start) }
            if preferred.end > interval.start, preferred.end < interval.end { boundaries.append(preferred.end) }
            let sorted = boundaries.sorted()
            return zip(sorted, sorted.dropFirst()).map { CalendarInterval(start: $0.0, end: $0.1) }
        }
    }
}
