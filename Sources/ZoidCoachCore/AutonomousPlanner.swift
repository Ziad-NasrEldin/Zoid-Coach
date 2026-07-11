import Foundation

public enum ReminderPriority: Int, Comparable, Sendable {
    case none = 0
    case low = 1
    case medium = 5
    case high = 9

    public static func < (lhs: ReminderPriority, rhs: ReminderPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func fromEventKit(_ priority: Int) -> ReminderPriority {
        switch priority {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }
}

public struct PlanningTaskCandidate: Equatable, Sendable {
    public let id: String
    public let title: String
    public let estimateMinutes: Int
    public let dueDate: Date?
    public let reminderPriority: ReminderPriority
    public let carryoverDays: Int
    public let deferralCount: Int
    public let recentAlignedMinutes: Int
    public let isBlocked: Bool
    public let aiPriorityAdjustment: Int
    public let aiReason: String?

    public init(
        id: String,
        title: String,
        estimateMinutes: Int,
        dueDate: Date?,
        reminderPriority: ReminderPriority,
        carryoverDays: Int,
        deferralCount: Int,
        recentAlignedMinutes: Int,
        isBlocked: Bool,
        aiPriorityAdjustment: Int = 0,
        aiReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.estimateMinutes = max(1, estimateMinutes)
        self.dueDate = dueDate
        self.reminderPriority = reminderPriority
        self.carryoverDays = max(0, carryoverDays)
        self.deferralCount = max(0, deferralCount)
        self.recentAlignedMinutes = max(0, recentAlignedMinutes)
        self.isBlocked = isBlocked
        self.aiPriorityAdjustment = min(max(aiPriorityAdjustment, -200), 200)
        self.aiReason = aiReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct PlanningInput: Equatable, Sendable {
    public let referenceDate: Date
    public let availableFocusMinutes: Int
    public let maximumCommitments: Int
    public let candidates: [PlanningTaskCandidate]

    public init(
        referenceDate: Date,
        availableFocusMinutes: Int,
        maximumCommitments: Int,
        candidates: [PlanningTaskCandidate]
    ) {
        self.referenceDate = referenceDate
        self.availableFocusMinutes = max(0, availableFocusMinutes)
        self.maximumCommitments = max(0, maximumCommitments)
        self.candidates = candidates
    }
}

public struct PlannedTask: Equatable, Sendable, Identifiable {
    public let taskID: String
    public let title: String
    public let rank: Int
    public let estimateMinutes: Int
    public let reason: String
    public let score: Int

    public var id: String { taskID }
}

public struct DailyPlanProposal: Equatable, Sendable {
    public let items: [PlannedTask]
    public let mainObjectiveTaskID: String?
    public let plannedFocusMinutes: Int
    public let availableFocusMinutes: Int

    public init(
        items: [PlannedTask],
        mainObjectiveTaskID: String?,
        plannedFocusMinutes: Int,
        availableFocusMinutes: Int
    ) {
        self.items = items
        self.mainObjectiveTaskID = mainObjectiveTaskID
        self.plannedFocusMinutes = plannedFocusMinutes
        self.availableFocusMinutes = availableFocusMinutes
    }
}

public struct AutonomousPlanner: Sendable {
    public init() {}

    public func plan(_ input: PlanningInput) -> DailyPlanProposal {
        let ranked = input.candidates
            .filter { !$0.isBlocked }
            .map { candidate in RankedCandidate(candidate: candidate, score: score(candidate, referenceDate: input.referenceDate)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.candidate.estimateMinutes != rhs.candidate.estimateMinutes {
                    return lhs.candidate.estimateMinutes < rhs.candidate.estimateMinutes
                }
                return lhs.candidate.title.localizedCaseInsensitiveCompare(rhs.candidate.title) == .orderedAscending
            }

        var remainingMinutes = input.availableFocusMinutes
        var items: [PlannedTask] = []

        for rankedCandidate in ranked where items.count < input.maximumCommitments {
            let candidate = rankedCandidate.candidate
            guard candidate.estimateMinutes <= remainingMinutes else { continue }
            let rank = items.count + 1
            items.append(
                PlannedTask(
                    taskID: candidate.id,
                    title: candidate.title,
                    rank: rank,
                    estimateMinutes: candidate.estimateMinutes,
                    reason: reason(for: candidate, referenceDate: input.referenceDate),
                    score: rankedCandidate.score
                )
            )
            remainingMinutes -= candidate.estimateMinutes
        }

        return DailyPlanProposal(
            items: items,
            mainObjectiveTaskID: items.first?.taskID,
            plannedFocusMinutes: input.availableFocusMinutes - remainingMinutes,
            availableFocusMinutes: input.availableFocusMinutes
        )
    }

    private func score(_ candidate: PlanningTaskCandidate, referenceDate: Date) -> Int {
        var result = candidate.reminderPriority.rawValue * 20
        result += min(candidate.carryoverDays, 5) * 35
        result += min(candidate.deferralCount, 5) * 25
        result += min(candidate.recentAlignedMinutes / 15, 12) * 10
        result += candidate.aiPriorityAdjustment

        if let dueDate = candidate.dueDate {
            let interval = dueDate.timeIntervalSince(referenceDate)
            if interval <= 0 {
                result += 1_000
            } else if interval <= 24 * 60 * 60 {
                result += 700
            } else if interval <= 3 * 24 * 60 * 60 {
                result += 350
            }
        }

        return result
    }

    private func reason(for candidate: PlanningTaskCandidate, referenceDate: Date) -> String {
        if candidate.aiPriorityAdjustment > 0, let aiReason = candidate.aiReason { return aiReason }
        if let dueDate = candidate.dueDate {
            let interval = dueDate.timeIntervalSince(referenceDate)
            if interval <= 0 { return "Overdue reminder" }
            if interval <= 24 * 60 * 60 { return "Due within 24 hours" }
            if interval <= 3 * 24 * 60 * 60 { return "Due within three days" }
        }
        if candidate.carryoverDays > 0 { return "Carried over for \(candidate.carryoverDays) day\(candidate.carryoverDays == 1 ? "" : "s")" }
        if candidate.deferralCount > 0 { return "Deferred \(candidate.deferralCount) time\(candidate.deferralCount == 1 ? "" : "s")" }
        if candidate.recentAlignedMinutes > 0 { return "Recent work evidence" }
        if candidate.reminderPriority >= .high { return "High-priority reminder" }
        return "Fits today's available focus time"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct RankedCandidate: Sendable {
    let candidate: PlanningTaskCandidate
    let score: Int
}
