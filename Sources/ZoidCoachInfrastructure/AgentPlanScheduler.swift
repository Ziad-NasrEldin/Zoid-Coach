import CryptoKit
import Foundation
import ZoidCoachCore

public struct AgentPlanCommandRequirement: Equatable, Hashable, Codable, Sendable {
    public let type: ActionCommandType
    public let entityID: String

    public init(type: ActionCommandType, entityID: String) {
        self.type = type
        self.entityID = entityID
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && lhs.entityID == rhs.entityID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type.rawValue)
        hasher.combine(entityID)
    }
}

public struct AgentPlanPreparedCommand: Equatable, Codable, Sendable {
    public let type: ActionCommandType
    public let entityID: String
    public let desiredState: ActionDesiredState
    public let planVersion: Int
    public let supersedingPending: Bool
    public let origin: ActionOrigin

    public init(
        type: ActionCommandType,
        entityID: String,
        desiredState: ActionDesiredState,
        planVersion: Int,
        supersedingPending: Bool = true,
        origin: ActionOrigin
    ) {
        self.type = type
        self.entityID = entityID
        self.desiredState = desiredState
        self.planVersion = planVersion
        self.supersedingPending = supersedingPending
        self.origin = origin
    }

    public var requirement: AgentPlanCommandRequirement {
        AgentPlanCommandRequirement(type: type, entityID: entityID)
    }
}

public struct AgentPlanCommandCancellation: Equatable, Codable, Sendable {
    public let type: ActionCommandType
    public let entityID: String

    public init(type: ActionCommandType, entityID: String) {
        self.type = type
        self.entityID = entityID
    }
}

public struct PreparedAgentPlanSchedule: Equatable, Codable, Sendable {
    public let requestFingerprint: String
    public let unscheduledTaskIDs: [String]
    public let cancellations: [AgentPlanCommandCancellation]
    public let commands: [AgentPlanPreparedCommand]

    public init(
        requestFingerprint: String,
        unscheduledTaskIDs: [String],
        cancellations: [AgentPlanCommandCancellation] = [],
        commands: [AgentPlanPreparedCommand] = []
    ) {
        self.requestFingerprint = requestFingerprint
        self.unscheduledTaskIDs = unscheduledTaskIDs
        self.cancellations = cancellations
        self.commands = commands
    }

    public var requiredCommands: Set<AgentPlanCommandRequirement> {
        Set(commands.map(\.requirement))
    }
}

private struct AgentPlanRequestFingerprintPayload: Codable {
    let dayKey: String
    let policyVersion: Int
    let policy: UserPolicy
    let plan: [StoredAutonomousPlanEntry]
    let tasks: [AgentPlanTaskFingerprint]
}

private struct AgentPlanTaskFingerprint: Codable {
    let id: String
    let title: String
    let dueDate: Date?
    let priority: Int
    let notes: String?
    let listID: String?
    let listName: String?
    let modificationDate: Date?
    let isCompleted: Bool
    let sourceKind: ReminderSourceKind

    init(_ task: ReminderSourceSnapshot) {
        id = task.id
        title = task.title
        dueDate = task.dueDate
        priority = task.priority
        notes = task.notes
        listID = task.listID
        listName = task.listName
        modificationDate = task.modificationDate
        isCompleted = task.isCompleted
        sourceKind = task.sourceKind
    }
}

public struct AgentPlanSchedulingResult: Equatable, Sendable {
    public let scheduledBlockCount: Int
    public let unscheduledTaskIDs: [String]
    public let reminderMutationCount: Int
    public let taskStartReminderCount: Int
    public let obsoleteBlockDeletionCount: Int
    public let commandIDs: [String]
    public let requiredCommands: Set<AgentPlanCommandRequirement>

    public init(scheduledBlockCount: Int, unscheduledTaskIDs: [String], reminderMutationCount: Int, taskStartReminderCount: Int = 0, obsoleteBlockDeletionCount: Int, commandIDs: [String] = [], requiredCommands: Set<AgentPlanCommandRequirement> = []) {
        self.scheduledBlockCount = scheduledBlockCount
        self.unscheduledTaskIDs = unscheduledTaskIDs
        self.reminderMutationCount = reminderMutationCount
        self.taskStartReminderCount = taskStartReminderCount
        self.obsoleteBlockDeletionCount = obsoleteBlockDeletionCount
        self.commandIDs = commandIDs
        self.requiredCommands = requiredCommands
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

    public func prepareSchedule(
        for day: Date,
        policy: UserPolicy,
        policyVersion: Int,
        origin: ActionOrigin = .explicitUser
    ) async throws -> PreparedAgentPlanSchedule {
        let requestFingerprint = try makeRequestFingerprint(
            for: day,
            policy: policy,
            policyVersion: policyVersion
        )
        guard !policy.automationPause.isPaused else {
            return PreparedAgentPlanSchedule(requestFingerprint: requestFingerprint, unscheduledTaskIDs: [])
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
            return PreparedAgentPlanSchedule(
                requestFingerprint: requestFingerprint,
                unscheduledTaskIDs: plan.map(\.reminderID)
            )
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
        var cancellations: [AgentPlanCommandCancellation] = []
        for commitment in protectedOwned {
            cancellations.append(.init(type: .deleteCalendarBlock, entityID: commitment.id))
        }
        for taskID in protectedTaskIDs {
            cancellations.append(.init(type: .reconcileCalendarBlock, entityID: taskID))
        }
        let fixed = commitments.filter { $0.ownershipToken == nil || $0.start <= schedulingTime }
        let free = workIntervals.flatMap { interval in freeIntervals(in: interval, commitments: fixed) }
        let tasks = plan.compactMap { entry -> SchedulableTask? in
            guard let task = reminderByID[entry.reminderID],
                  !protectedTaskIDs.contains(entry.reminderID),
                  entry.isOptional != true,
                  !(entry.deferredUntil.map { $0 > schedulingTime } ?? false)
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
            return PreparedAgentPlanSchedule(
                requestFingerprint: requestFingerprint,
                unscheduledTaskIDs: schedule.unscheduledTaskIDs,
                cancellations: cancellations
            )
        }
        let desiredTokens = Set(schedule.blocks.map { ownershipToken(dayKey: dayKey, taskID: $0.taskID) }).union(protectedTokens)
        var commands: [AgentPlanPreparedCommand] = []
        for existing in commitments where existing.ownershipToken != nil && existing.start > schedulingTime {
            guard let token = existing.ownershipToken, !desiredTokens.contains(token) else { continue }
            commands.append(.init(
                type: .deleteCalendarBlock,
                entityID: existing.id,
                desiredState: .deleteOwnedCalendarBlock(ownershipToken: token),
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            ))
        }

        for block in schedule.blocks {
            guard let task = reminderByID[block.taskID] else { continue }
            let token = ownershipToken(dayKey: dayKey, taskID: block.taskID)
            commands.append(.init(
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
            ))

            let reminderID = "task-start:\(dayKey):\(block.taskID)"
            commands.append(.init(
                type: .scheduleNotification,
                entityID: block.taskID,
                desiredState: .notification(NotificationDesiredState(
                    category: "TASK_START",
                    title: "Planned task ready",
                    body: "\(task.title) is scheduled to start now. Open Today to begin it or revise the plan.",
                    promptID: reminderID,
                    deliveryDate: block.start
                )),
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            ))
        }

        let dueDate = finalEnd
        for entry in plan {
            guard let task = reminderByID[entry.reminderID] else { continue }
            let marker = "plan:\(dayKey):rank:\(entry.rank)"
            commands.append(.init(
                type: .setReminderPriority,
                entityID: entry.reminderID,
                desiredState: .reminder(ReminderDesiredState(priority: entry.rank == 1 ? 1 : 5, metadataMarker: marker)),
                planVersion: policyVersion,
                supersedingPending: true,
                origin: origin
            ))
            if task.dueDate == nil {
                commands.append(.init(
                    type: .setReminderDueDate,
                    entityID: entry.reminderID,
                    desiredState: .reminder(ReminderDesiredState(dueDate: dueDate, metadataMarker: marker)),
                    planVersion: policyVersion,
                    supersedingPending: true,
                    origin: origin
                ))
            }
        }
        return PreparedAgentPlanSchedule(
            requestFingerprint: requestFingerprint,
            unscheduledTaskIDs: schedule.unscheduledTaskIDs,
            cancellations: cancellations,
            commands: commands
        )
    }

    public func enqueueSchedule(
        for day: Date,
        policy: UserPolicy,
        policyVersion: Int,
        origin: ActionOrigin = .explicitUser
    ) async throws -> AgentPlanSchedulingResult {
        let prepared = try await prepareSchedule(
            for: day,
            policy: policy,
            policyVersion: policyVersion,
            origin: origin
        )
        return try enqueuePreparedSchedule(prepared)
    }

    public func enqueuePreparedSchedule(
        _ prepared: PreparedAgentPlanSchedule
    ) throws -> AgentPlanSchedulingResult {
        for cancellation in prepared.cancellations {
            _ = try outbox.cancelPendingCommands(
                type: cancellation.type,
                entityID: cancellation.entityID
            )
        }

        var scheduledBlockCount = 0
        var reminderMutationCount = 0
        var taskStartReminderCount = 0
        var obsoleteBlockDeletionCount = 0
        var commandIDs: [String] = []

        for command in prepared.commands {
            let result = try outbox.enqueue(
                type: command.type,
                entityID: command.entityID,
                desiredState: command.desiredState,
                planVersion: command.planVersion,
                supersedingPending: command.supersedingPending,
                origin: command.origin
            )
            commandIDs.append(result.command.id)
            guard result.wasInserted else { continue }
            switch command.type {
            case .reconcileCalendarBlock:
                scheduledBlockCount += 1
            case .scheduleNotification:
                taskStartReminderCount += 1
            case .setReminderPriority, .setReminderDueDate:
                reminderMutationCount += 1
            case .deleteCalendarBlock:
                obsoleteBlockDeletionCount += 1
            default:
                break
            }
        }

        return AgentPlanSchedulingResult(
            scheduledBlockCount: scheduledBlockCount,
            unscheduledTaskIDs: prepared.unscheduledTaskIDs,
            reminderMutationCount: reminderMutationCount,
            taskStartReminderCount: taskStartReminderCount,
            obsoleteBlockDeletionCount: obsoleteBlockDeletionCount,
            commandIDs: Array(Set(commandIDs)).sorted(),
            requiredCommands: prepared.requiredCommands
        )
    }

    public func makeRequestFingerprint(
        for day: Date,
        policy: UserPolicy,
        policyVersion: Int
    ) throws -> String {
        let plan = try plans.loadDailyPlan(for: day)
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank ? lhs.reminderID < rhs.reminderID : lhs.rank < rhs.rank
            }
        let taskIDs = Set(plan.map(\.reminderID))
        let tasks = try reminders.loadIncomplete()
            .filter { taskIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map(AgentPlanTaskFingerprint.init)
        let payload = AgentPlanRequestFingerprintPayload(
            dayKey: localDayKey(day, timeZoneIdentifier: policy.schedule.timeZoneIdentifier),
            policyVersion: policyVersion,
            policy: policy,
            plan: plan,
            tasks: tasks
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return digest.map { String(format: "%02x", $0) }.joined()
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
