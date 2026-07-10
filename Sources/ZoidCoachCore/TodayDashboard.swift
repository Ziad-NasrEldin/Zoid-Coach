import Foundation

public enum TaskUrgency: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low

    public static func resolve(dueDate: Date?, priority: ReminderPriority, referenceDate: Date, calendar: Calendar = .current) -> TaskUrgency {
        guard let dueDate else {
            return priority >= .high ? .high : priority >= .medium ? .medium : .low
        }
        let dayDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: referenceDate), to: calendar.startOfDay(for: dueDate)).day ?? 0
        if dayDifference <= 0 || priority >= .high { return .high }
        if dayDifference <= 2 || priority >= .medium { return .medium }
        return .low
    }
}

public enum TaskExecutionState: String, Codable, CaseIterable, Sendable {
    case ready
    case active
    case paused
    case blocked
    case completed
    case rescheduled
}

public enum TaskActivityCommand: String, Codable, Sendable {
    case start
    case pause
    case resume
    case complete
    case block
    case reschedule
}

public struct TodayTaskRow: Identifiable, Equatable, Codable, Sendable {
    public let taskID: String
    public let title: String
    public let estimateMinutes: Int
    public let dueDate: Date?
    public let urgency: TaskUrgency
    public let state: TaskExecutionState
    public let elapsedMinutes: Int
    public let isMainObjective: Bool
    public let isLocked: Bool

    public init(taskID: String, title: String, estimateMinutes: Int, dueDate: Date?, urgency: TaskUrgency, state: TaskExecutionState, elapsedMinutes: Int = 0, isMainObjective: Bool = false, isLocked: Bool = false) {
        self.taskID = taskID
        self.title = title
        self.estimateMinutes = max(1, estimateMinutes)
        self.dueDate = dueDate
        self.urgency = urgency
        self.state = state
        self.elapsedMinutes = max(0, elapsedMinutes)
        self.isMainObjective = isMainObjective
        self.isLocked = isLocked
    }

    public var id: String { taskID }
}

public enum BehaviorClassification: String, Codable, CaseIterable, Sendable {
    case work
    case gaming
    case distracting
    case idle
    case unknown
}

public struct BehaviorObservation: Equatable, Codable, Sendable {
    public let observedAt: Date
    public let application: String?
    public let classification: BehaviorClassification

    public init(observedAt: Date, application: String?, classification: BehaviorClassification) {
        self.observedAt = observedAt
        self.application = application
        self.classification = classification
    }
}

public struct BehaviorSummary: Equatable, Codable, Sendable {
    public let workMinutes: Int
    public let gamingMinutes: Int
    public let distractingMinutes: Int
    public let gamingOrDistractingMinutes: Int
    public let idleMinutes: Int
    public let unknownMinutes: Int

    public init(workMinutes: Int = 0, gamingMinutes: Int = 0, distractingMinutes: Int = 0, idleMinutes: Int = 0, unknownMinutes: Int = 0) {
        self.workMinutes = max(0, workMinutes)
        self.gamingMinutes = max(0, gamingMinutes)
        self.distractingMinutes = max(0, distractingMinutes)
        gamingOrDistractingMinutes = max(0, gamingMinutes) + max(0, distractingMinutes)
        self.idleMinutes = max(0, idleMinutes)
        self.unknownMinutes = max(0, unknownMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case workMinutes, gamingMinutes, distractingMinutes, gamingOrDistractingMinutes, idleMinutes, unknownMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyCombined = try container.decodeIfPresent(Int.self, forKey: .gamingOrDistractingMinutes) ?? 0
        let gaming = try container.decodeIfPresent(Int.self, forKey: .gamingMinutes) ?? legacyCombined
        let distracting = try container.decodeIfPresent(Int.self, forKey: .distractingMinutes) ?? 0
        self.init(
            workMinutes: try container.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 0,
            gamingMinutes: gaming,
            distractingMinutes: distracting,
            idleMinutes: try container.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 0,
            unknownMinutes: try container.decodeIfPresent(Int.self, forKey: .unknownMinutes) ?? 0
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workMinutes, forKey: .workMinutes)
        try container.encode(gamingMinutes, forKey: .gamingMinutes)
        try container.encode(distractingMinutes, forKey: .distractingMinutes)
        try container.encode(gamingOrDistractingMinutes, forKey: .gamingOrDistractingMinutes)
        try container.encode(idleMinutes, forKey: .idleMinutes)
        try container.encode(unknownMinutes, forKey: .unknownMinutes)
    }
}

public struct TelemetryCoverage: Equatable, Codable, Sendable {
    public let isLimited: Bool
    public let explanation: String
    public let lastObservationAt: Date?

    public init(isLimited: Bool, explanation: String, lastObservationAt: Date?) {
        self.isLimited = isLimited
        self.explanation = explanation
        self.lastObservationAt = lastObservationAt
    }
}

public enum RecommendationReasonCode: String, Codable, Sendable {
    case overdue
    case dueToday
    case highUrgency
    case shortFit
    case mainObjective
    case userLocked
    case limitedCoverage
}

public struct NextTaskRecommendation: Equatable, Codable, Sendable {
    public let taskID: String?
    public let sentence: String
    public let reasons: [RecommendationReasonCode]
    public let coverageUncertainty: String?

    public init(taskID: String?, sentence: String, reasons: [RecommendationReasonCode], coverageUncertainty: String? = nil) {
        self.taskID = taskID
        self.sentence = sentence
        self.reasons = reasons
        self.coverageUncertainty = coverageUncertainty
    }
}

public struct GamingPolicy: Equatable, Codable, Sendable {
    public let version: Int
    public let dailyBudgetMinutes: Int
    public let priorityTaskRewardMinutes: Int

    public init(version: Int = 1, dailyBudgetMinutes: Int = 60, priorityTaskRewardMinutes: Int = 15) {
        self.version = version
        self.dailyBudgetMinutes = max(0, dailyBudgetMinutes)
        self.priorityTaskRewardMinutes = max(0, priorityTaskRewardMinutes)
    }
}

public struct GamingStatus: Equatable, Codable, Sendable {
    public let budgetMinutes: Int
    public let usedMinutes: Int
    public let unlockedRemainingMinutes: Int
    public let nextUnlockReason: String
    public let confidenceIsLimited: Bool

    public init(budgetMinutes: Int, usedMinutes: Int, unlockedRemainingMinutes: Int, nextUnlockReason: String, confidenceIsLimited: Bool) {
        self.budgetMinutes = max(0, budgetMinutes)
        self.usedMinutes = max(0, usedMinutes)
        self.unlockedRemainingMinutes = max(0, unlockedRemainingMinutes)
        self.nextUnlockReason = nextUnlockReason
        self.confidenceIsLimited = confidenceIsLimited
    }
}

public struct ActiveTaskSnapshot: Equatable, Codable, Sendable {
    public let taskID: String
    public let startedAt: Date?
    public let elapsedMinutes: Int

    public init(taskID: String, startedAt: Date?, elapsedMinutes: Int) {
        self.taskID = taskID
        self.startedAt = startedAt
        self.elapsedMinutes = max(0, elapsedMinutes)
    }
}

public struct TodayReminderQueueRow: Identifiable, Equatable, Codable, Sendable {
    public let reminderID: String
    public let title: String
    public let listID: String?
    public let listName: String?
    public let dueDate: Date?
    public let priority: Int

    public init(reminderID: String, title: String, listID: String?, listName: String?, dueDate: Date?, priority: Int) {
        self.reminderID = reminderID
        self.title = title
        self.listID = listID
        self.listName = listName
        self.dueDate = dueDate
        self.priority = priority
    }

    public var id: String { reminderID }
}

public struct SourceFreshnessSnapshot: Identifiable, Equatable, Codable, Sendable {
    public let sourceID: String
    public let state: String
    public let detail: String
    public let lastUpdatedAt: Date?

    public init(sourceID: String, state: String, detail: String, lastUpdatedAt: Date?) {
        self.sourceID = sourceID
        self.state = state
        self.detail = detail
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var id: String { sourceID }
}

public struct TodaySnapshot: Equatable, Codable, Sendable {
    public let localDate: Date
    public let timeZoneIdentifier: String
    public let mainObjective: String?
    public let taskRows: [TodayTaskRow]
    public let activeTask: ActiveTaskSnapshot?
    public let recommendation: NextTaskRecommendation
    public let behavior: BehaviorSummary
    public let coverage: TelemetryCoverage
    public let gaming: GamingStatus
    public let sourceFreshnessExplanation: String
    public let unplannedReminders: [TodayReminderQueueRow]?
    public let sources: [SourceFreshnessSnapshot]?

    public init(localDate: Date, timeZoneIdentifier: String, mainObjective: String?, taskRows: [TodayTaskRow], activeTask: ActiveTaskSnapshot?, recommendation: NextTaskRecommendation, behavior: BehaviorSummary, coverage: TelemetryCoverage, gaming: GamingStatus, sourceFreshnessExplanation: String, unplannedReminders: [TodayReminderQueueRow] = [], sources: [SourceFreshnessSnapshot] = []) {
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mainObjective = mainObjective
        self.taskRows = taskRows
        self.activeTask = activeTask
        self.recommendation = recommendation
        self.behavior = behavior
        self.coverage = coverage
        self.gaming = gaming
        self.sourceFreshnessExplanation = sourceFreshnessExplanation
        self.unplannedReminders = unplannedReminders
        self.sources = sources
    }
}

public struct BehaviorSessionizer: Sendable {
    public let inactivityGap: TimeInterval
    public let maximumObservationDuration: TimeInterval

    public init(inactivityGap: TimeInterval = 300, maximumObservationDuration: TimeInterval = 300) {
        self.inactivityGap = inactivityGap
        self.maximumObservationDuration = maximumObservationDuration
    }

    public func summarize(observations: [BehaviorObservation], now: Date, staleAfter: TimeInterval = 900) -> (summary: BehaviorSummary, coverage: TelemetryCoverage) {
        let sorted = observations.sorted { $0.observedAt < $1.observedAt }
        guard let last = sorted.last else {
            return (BehaviorSummary(), TelemetryCoverage(isLimited: true, explanation: "Limited coverage: Screenwatch has no observations today.", lastObservationAt: nil))
        }
        var totals = Dictionary(uniqueKeysWithValues: BehaviorClassification.allCases.map { ($0, TimeInterval(0)) })
        for (index, observation) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].observedAt : now
            let rawElapsed = max(0, next.timeIntervalSince(observation.observedAt))
            guard rawElapsed <= inactivityGap else { continue }
            let elapsed = min(maximumObservationDuration, rawElapsed)
            totals[observation.classification, default: 0] += elapsed
        }
        let limited = now.timeIntervalSince(last.observedAt) > staleAfter
        let summary = BehaviorSummary(
            workMinutes: Int(totals[.work, default: 0] / 60),
            gamingMinutes: Int(totals[.gaming, default: 0] / 60),
            distractingMinutes: Int(totals[.distracting, default: 0] / 60),
            idleMinutes: Int(totals[.idle, default: 0] / 60),
            unknownMinutes: Int(totals[.unknown, default: 0] / 60)
        )
        let coverage = TelemetryCoverage(isLimited: limited, explanation: limited ? "Limited coverage: Screenwatch is stale." : "Screenwatch coverage is current.", lastObservationAt: last.observedAt)
        return (summary, coverage)
    }
}

public struct BehaviorClassifier: Sendable {
    public init() {}

    public func classify(application: String) -> BehaviorClassification {
        let normalized = application.lowercased()
        if ["steam", "league of legends", "minecraft", "roblox", "discord"].contains(where: normalized.contains) { return .gaming }
        if ["youtube", "tiktok", "instagram", "twitter", "x.com", "reddit"].contains(where: normalized.contains) { return .distracting }
        if ["screensaver", "loginwindow"].contains(where: normalized.contains) { return .idle }
        if ["xcode", "cursor", "visual studio code", "terminal", "iterm", "codex", "chatgpt", "figma", "pages", "numbers", "keynote", "mail", "calendar", "reminders", "slack"].contains(where: normalized.contains) { return .work }
        return .unknown
    }
}

public struct NextTaskRecommender: Sendable {
    public init() {}

    public func recommend(tasks: [TodayTaskRow], referenceDate: Date, availableMinutes: Int, coverage: TelemetryCoverage, calendar: Calendar = .current) -> NextTaskRecommendation {
        let candidates = tasks.filter { ![.active, .blocked, .completed, .rescheduled].contains($0.state) }
        guard let task = candidates.sorted(by: { score($0, referenceDate: referenceDate, availableMinutes: availableMinutes, calendar: calendar) > score($1, referenceDate: referenceDate, availableMinutes: availableMinutes, calendar: calendar) || (score($0, referenceDate: referenceDate, availableMinutes: availableMinutes, calendar: calendar) == score($1, referenceDate: referenceDate, availableMinutes: availableMinutes, calendar: calendar) && $0.taskID < $1.taskID) }).first else {
            return NextTaskRecommendation(taskID: nil, sentence: "No ready planned task remains.", reasons: coverage.isLimited ? [.limitedCoverage] : [], coverageUncertainty: coverage.isLimited ? coverage.explanation : nil)
        }
        var reasons: [RecommendationReasonCode] = []
        if let dueDate = task.dueDate {
            let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: referenceDate), to: calendar.startOfDay(for: dueDate)).day ?? 1
            if difference < 0 { reasons.append(.overdue) } else if difference == 0 { reasons.append(.dueToday) }
        }
        if task.urgency == .high { reasons.append(.highUrgency) }
        if task.estimateMinutes <= availableMinutes { reasons.append(.shortFit) }
        if task.isMainObjective { reasons.append(.mainObjective) }
        if task.isLocked { reasons.append(.userLocked) }
        if coverage.isLimited { reasons.append(.limitedCoverage) }
        let detail = reasons.contains(.overdue) ? "It is overdue." : reasons.contains(.dueToday) ? "It is due today." : task.estimateMinutes <= availableMinutes ? "It fits the time you have." : "It is your highest ready priority."
        return NextTaskRecommendation(taskID: task.taskID, sentence: "Start \"\(task.title)\" now. \(detail)", reasons: reasons, coverageUncertainty: coverage.isLimited ? coverage.explanation : nil)
    }

    private func score(_ task: TodayTaskRow, referenceDate: Date, availableMinutes: Int, calendar: Calendar) -> Int {
        var value = task.urgency == .high ? 700 : task.urgency == .medium ? 350 : 100
        if let dueDate = task.dueDate {
            let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: referenceDate), to: calendar.startOfDay(for: dueDate)).day ?? 10
            value += difference < 0 ? 1_000 : difference == 0 ? 800 : difference == 1 ? 300 : 0
        }
        if task.estimateMinutes <= availableMinutes { value += 100 }
        if task.isMainObjective { value += 200 }
        if task.isLocked { value += 500 }
        return value
    }
}

public struct GamingStatusCalculator: Sendable {
    public init() {}

    public func status(policy: GamingPolicy, gamingMinutes: Int, rewardApplied: Bool, coverage: TelemetryCoverage) -> GamingStatus {
        let allowance = policy.dailyBudgetMinutes + (rewardApplied ? policy.priorityTaskRewardMinutes : 0)
        return GamingStatus(budgetMinutes: policy.dailyBudgetMinutes, usedMinutes: gamingMinutes, unlockedRemainingMinutes: max(0, allowance - gamingMinutes), nextUnlockReason: rewardApplied ? "Priority-task reward already applied today." : "Finish one priority task to unlock a one-time reward.", confidenceIsLimited: coverage.isLimited)
    }
}
