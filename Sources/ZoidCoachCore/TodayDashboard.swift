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
    case pauseForBreak
    case pauseForExternalInterruption
    case pauseDoneForNow
    case pauseForEndOfDay
    case resume
    case complete
    case block
    case reschedule
    case startSprint10
    case startSprint20
    case startSprint25
    case continueOpenEnded

    public var sprintDurationMinutes: Int? {
        switch self {
        case .startSprint10: 10
        case .startSprint20: 20
        case .startSprint25: 25
        default: nil
        }
    }

    public var pauseReason: TaskPauseReason? {
        switch self {
        case .pause: .unspecified
        case .pauseForBreak: .break
        case .pauseForExternalInterruption: .externalInterruption
        case .pauseDoneForNow: .doneForNow
        case .pauseForEndOfDay: .endingWorkday
        case .start, .resume, .complete, .block, .reschedule,
             .startSprint10, .startSprint20, .startSprint25, .continueOpenEnded: nil
        }
    }
}

public enum SprintExecutionState: String, Codable, Sendable {
    case active
    case paused
    case expired
    case continuedOpenEnded
    case finished
}

public struct SprintSnapshot: Equatable, Codable, Sendable {
    public let durationMinutes: Int
    public let elapsedSeconds: Int
    public let remainingSeconds: Int
    public let state: SprintExecutionState
    public let observedAt: Date?

    public init(durationMinutes: Int, elapsedSeconds: Int, remainingSeconds: Int, state: SprintExecutionState, observedAt: Date? = nil) {
        self.durationMinutes = max(1, durationMinutes)
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.remainingSeconds = max(0, remainingSeconds)
        self.state = state
        self.observedAt = observedAt
    }

    public var isBounded: Bool {
        state != .continuedOpenEnded && state != .finished
    }

    public func remainingSeconds(at date: Date) -> Int {
        guard state == .active, let observedAt else { return remainingSeconds }
        return max(0, remainingSeconds - Int(max(0, date.timeIntervalSince(observedAt))))
    }
}

public enum TaskPauseReason: String, Codable, CaseIterable, Sendable {
    case unspecified
    case `break`
    case switchingTasks
    case externalInterruption
    case reminderDeleted
    case doneForNow
    case endingWorkday
    case blocked

    public var userFacingLabel: String {
        switch self {
        case .unspecified: "Paused"
        case .break: "Paused for a break"
        case .switchingTasks: "Paused while switching tasks"
        case .externalInterruption: "Paused for an external interruption"
        case .reminderDeleted: "Paused because the Apple Reminder was deleted"
        case .doneForNow: "Paused because you are done for now"
        case .endingWorkday: "Paused at the end of the workday"
        case .blocked: "Paused because the task is blocked"
        }
    }
}

public enum TaskCompletionReason: String, Codable, Sendable {
    case appleReminderCompleted

    public var userFacingLabel: String {
        switch self {
        case .appleReminderCompleted: "Ended because the Apple Reminder was completed"
        }
    }
}

public struct AcceptedBreakSnapshot: Equatable, Codable, Sendable {
    public static let defaultDurationMinutes = 15

    public let startedAt: Date
    public let durationMinutes: Int

    public init(startedAt: Date, durationMinutes: Int = defaultDurationMinutes) {
        self.startedAt = startedAt
        self.durationMinutes = max(1, durationMinutes)
    }

    public func remainingSeconds(at date: Date) -> Int {
        max(0, durationMinutes * 60 - Int(max(0, date.timeIntervalSince(startedAt))))
    }

    public func hasEnded(at date: Date) -> Bool {
        remainingSeconds(at: date) == 0
    }
}

public struct LearnedEstimateSuggestion: Equatable, Codable, Sendable {
    public let recommendedMinutes: Int
    public let sampleCount: Int
    public let minimumActualMinutes: Int
    public let maximumActualMinutes: Int
    public let confidence: Double

    public init(
        recommendedMinutes: Int,
        sampleCount: Int,
        minimumActualMinutes: Int,
        maximumActualMinutes: Int,
        confidence: Double
    ) {
        self.recommendedMinutes = max(1, recommendedMinutes)
        self.sampleCount = max(1, sampleCount)
        self.minimumActualMinutes = max(1, minimumActualMinutes)
        self.maximumActualMinutes = max(self.minimumActualMinutes, maximumActualMinutes)
        self.confidence = min(max(confidence, 0), 1)
    }

    public var hasLimitedEvidence: Bool { confidence < 0.75 }
}

public struct ActiveTaskTimeComparison: Equatable, Codable, Sendable {
    public let elapsedMinutes: Int
    public let observedAlignedMinutes: Int
    public let observedSessionMinutes: Int
    public let coverageIsLimited: Bool
    public let evidenceExplanation: String

    public init(
        elapsedMinutes: Int,
        activeSince: Date,
        observations: [BehaviorObservation],
        now: Date
    ) {
        let sessionObservations = observations.filter {
            $0.observedAt >= activeSince && $0.observedAt <= now
        }
        let evidence = BehaviorSessionizer().summarize(observations: sessionObservations, now: now)
        let summary = evidence.summary
        let observedSessionMinutes = summary.workMinutes
            + summary.gamingMinutes
            + summary.distractingMinutes
            + summary.idleMinutes
            + summary.unknownMinutes

        self.elapsedMinutes = max(0, elapsedMinutes)
        self.observedAlignedMinutes = summary.workMinutes
        self.observedSessionMinutes = observedSessionMinutes
        self.coverageIsLimited = evidence.coverage.isLimited
        if sessionObservations.isEmpty {
            self.evidenceExplanation = "No Screenwatch time is available for this active session. Elapsed time remains the reliable task timer."
        } else if evidence.coverage.isLimited {
            self.evidenceExplanation = "\(evidence.coverage.explanation) Aligned time is only work-classified Screenwatch time from this active session, not proof that it matched this task."
        } else {
            self.evidenceExplanation = "Aligned time is work-classified Screenwatch time from this active session. It is a signal, not proof that the activity matched this task."
        }
    }

    public var accessibilitySummary: String {
        "Task elapsed \(elapsedMinutes) minutes. Observed aligned \(observedAlignedMinutes) minutes. \(evidenceExplanation)"
    }
}

public struct TodayTaskRow: Identifiable, Equatable, Codable, Sendable {
    public let taskID: String
    public let title: String
    public let estimateMinutes: Int
    public let dueDate: Date?
    public let urgency: TaskUrgency
    public let state: TaskExecutionState
    public let elapsedMinutes: Int
    public let activeTimeComparison: ActiveTaskTimeComparison?
    public let completionReason: TaskCompletionReason?
    public let latestPauseReason: TaskPauseReason?
    public let acceptedBreak: AcceptedBreakSnapshot?
    public let sprint: SprintSnapshot?
    public let isMainObjective: Bool
    public let isLocked: Bool
    public let isOptional: Bool?
    public let blockedReason: String?
    public let deferredUntil: Date?
    public let learnedEstimateSuggestion: LearnedEstimateSuggestion?

    public init(
        taskID: String,
        title: String,
        estimateMinutes: Int,
        dueDate: Date?,
        urgency: TaskUrgency,
        state: TaskExecutionState,
        elapsedMinutes: Int = 0,
        activeTimeComparison: ActiveTaskTimeComparison? = nil,
        completionReason: TaskCompletionReason? = nil,
        latestPauseReason: TaskPauseReason? = nil,
        acceptedBreak: AcceptedBreakSnapshot? = nil,
        sprint: SprintSnapshot? = nil,
        isMainObjective: Bool = false,
        isLocked: Bool = false,
        isOptional: Bool = false,
        blockedReason: String? = nil,
        deferredUntil: Date? = nil,
        learnedEstimateSuggestion: LearnedEstimateSuggestion? = nil
    ) {
        self.taskID = taskID
        self.title = title
        self.estimateMinutes = max(1, estimateMinutes)
        self.dueDate = dueDate
        self.urgency = urgency
        self.state = state
        self.elapsedMinutes = max(0, elapsedMinutes)
        self.activeTimeComparison = activeTimeComparison
        self.completionReason = completionReason
        self.latestPauseReason = latestPauseReason
        self.acceptedBreak = acceptedBreak
        self.sprint = sprint
        self.isMainObjective = isMainObjective
        self.isLocked = isLocked
        self.isOptional = isOptional
        self.blockedReason = blockedReason
        self.deferredUntil = deferredUntil
        self.learnedEstimateSuggestion = learnedEstimateSuggestion
    }

    public var id: String { taskID }

    public func userFacingStateLabel(defaultLabel: String) -> String {
        guard state == .completed, let completionReason else { return defaultLabel }
        return completionReason.userFacingLabel
    }
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

public enum ActiveTaskContextState: String, Equatable, Codable, Sendable {
    case aligned
    case uncertain
    case mismatched

    public var title: String {
        switch self {
        case .aligned: "Context looks work-aligned"
        case .uncertain: "Context is uncertain"
        case .mismatched: "Context may not match this task"
        }
    }
}

public struct ActiveTaskContextAssessment: Equatable, Codable, Sendable {
    public let state: ActiveTaskContextState
    public let explanation: String
    public let lastObservedAt: Date?

    public init(state: ActiveTaskContextState, explanation: String, lastObservedAt: Date?) {
        self.state = state
        self.explanation = explanation
        self.lastObservedAt = lastObservedAt
    }
}

public struct ActiveTaskContextAssessor: Sendable {
    public init() {}

    public func assess(
        observations: [BehaviorObservation],
        now: Date,
        staleAfter: TimeInterval = 900
    ) -> ActiveTaskContextAssessment {
        guard let latest = observations.max(by: { $0.observedAt < $1.observedAt }) else {
            return ActiveTaskContextAssessment(
                state: .uncertain,
                explanation: "No current activity evidence is available, so Zoid 666 will not guess.",
                lastObservedAt: nil
            )
        }
        guard now.timeIntervalSince(latest.observedAt) <= staleAfter else {
            return ActiveTaskContextAssessment(
                state: .uncertain,
                explanation: "The latest activity evidence is stale, so Zoid 666 will not guess.",
                lastObservedAt: latest.observedAt
            )
        }
        switch latest.classification {
        case .work:
            return ActiveTaskContextAssessment(
                state: .aligned,
                explanation: "The latest observed app is classified as work. This is a signal, not proof that it matches this task.",
                lastObservedAt: latest.observedAt
            )
        case .gaming, .distracting:
            return ActiveTaskContextAssessment(
                state: .mismatched,
                explanation: "The latest observed app is not classified as work. Check the context before changing your plan.",
                lastObservedAt: latest.observedAt
            )
        case .idle:
            return ActiveTaskContextAssessment(
                state: .uncertain,
                explanation: "The latest observation is idle. Zoid 666 cannot infer whether that matches this task.",
                lastObservedAt: latest.observedAt
            )
        case .unknown:
            return ActiveTaskContextAssessment(
                state: .uncertain,
                explanation: "The latest activity is unclassified, so Zoid 666 will not guess.",
                lastObservedAt: latest.observedAt
            )
        }
    }
}

public struct AppUsageBreakdown: Identifiable, Equatable, Codable, Sendable {
    public let application: String
    public let observedSeconds: Int
    public let percentage: Double
    public let classification: BehaviorClassification

    public init(application: String, observedSeconds: Int, percentage: Double, classification: BehaviorClassification = .unknown) {
        self.application = application
        self.observedSeconds = max(0, observedSeconds)
        self.percentage = min(100, max(0, percentage))
        self.classification = classification
    }

    public var id: String { "\(application)|\(classification.rawValue)" }
    public var observedMinutes: Int { Int((Double(observedSeconds) / 60).rounded()) }

    private enum CodingKeys: String, CodingKey {
        case application, observedSeconds, percentage, classification
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            application: try container.decode(String.self, forKey: .application),
            observedSeconds: try container.decode(Int.self, forKey: .observedSeconds),
            percentage: try container.decode(Double.self, forKey: .percentage),
            classification: try container.decodeIfPresent(BehaviorClassification.self, forKey: .classification) ?? .unknown
        )
    }
}

public struct CategoryUsageBreakdown: Identifiable, Equatable, Codable, Sendable {
    public let classification: BehaviorClassification
    public let observedSeconds: Int
    public let percentage: Double

    public init(classification: BehaviorClassification, observedSeconds: Int, percentage: Double) {
        self.classification = classification
        self.observedSeconds = max(0, observedSeconds)
        self.percentage = min(100, max(0, percentage))
    }

    public var id: BehaviorClassification { classification }
}

public struct BehaviorSummary: Equatable, Codable, Sendable {
    public let workMinutes: Int
    public let gamingMinutes: Int
    public let meaningfulGamingMinutes: Int
    public let distractingMinutes: Int
    public let gamingOrDistractingMinutes: Int
    public let idleMinutes: Int
    public let unknownMinutes: Int
    public let appUsage: [AppUsageBreakdown]

    public var categoryUsage: [CategoryUsageBreakdown] {
        let totalSeconds = appUsage.reduce(0) { $0 + $1.observedSeconds }
        let order = Dictionary(uniqueKeysWithValues: BehaviorClassification.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: appUsage, by: \.classification)
            .map { classification, applications in
                let observedSeconds = applications.reduce(0) { $0 + $1.observedSeconds }
                return CategoryUsageBreakdown(
                    classification: classification,
                    observedSeconds: observedSeconds,
                    percentage: totalSeconds > 0 ? Double(observedSeconds) / Double(totalSeconds) * 100 : 0
                )
            }
            .sorted {
                if $0.observedSeconds != $1.observedSeconds { return $0.observedSeconds > $1.observedSeconds }
                return order[$0.classification, default: .max] < order[$1.classification, default: .max]
            }
    }

    public var workCategoryUsage: [WorkCategoryBreakdown] {
        let classifier = WorkCategoryClassifier()
        var seconds = Dictionary(uniqueKeysWithValues: WorkCategory.allCases.map { ($0, 0) })
        for application in appUsage where application.classification == .work {
            let category = classifier.category(for: application.application) ?? .uncategorized
            seconds[category, default: 0] += application.observedSeconds
        }
        return WorkCategory.allCases.map {
            WorkCategoryBreakdown(category: $0, observedSeconds: seconds[$0, default: 0])
        }
    }

    public init(workMinutes: Int = 0, gamingMinutes: Int = 0, meaningfulGamingMinutes: Int? = nil, distractingMinutes: Int = 0, idleMinutes: Int = 0, unknownMinutes: Int = 0, appUsage: [AppUsageBreakdown] = []) {
        self.workMinutes = max(0, workMinutes)
        self.gamingMinutes = max(0, gamingMinutes)
        self.meaningfulGamingMinutes = max(0, meaningfulGamingMinutes ?? gamingMinutes)
        self.distractingMinutes = max(0, distractingMinutes)
        gamingOrDistractingMinutes = max(0, gamingMinutes) + max(0, distractingMinutes)
        self.idleMinutes = max(0, idleMinutes)
        self.unknownMinutes = max(0, unknownMinutes)
        self.appUsage = appUsage
    }

    private enum CodingKeys: String, CodingKey {
        case workMinutes, gamingMinutes, meaningfulGamingMinutes, distractingMinutes, gamingOrDistractingMinutes, idleMinutes, unknownMinutes, appUsage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyCombined = try container.decodeIfPresent(Int.self, forKey: .gamingOrDistractingMinutes) ?? 0
        let gaming = try container.decodeIfPresent(Int.self, forKey: .gamingMinutes) ?? legacyCombined
        let distracting = try container.decodeIfPresent(Int.self, forKey: .distractingMinutes) ?? 0
        self.init(
            workMinutes: try container.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 0,
            gamingMinutes: gaming,
            meaningfulGamingMinutes: try container.decodeIfPresent(Int.self, forKey: .meaningfulGamingMinutes) ?? gaming,
            distractingMinutes: distracting,
            idleMinutes: try container.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 0,
            unknownMinutes: try container.decodeIfPresent(Int.self, forKey: .unknownMinutes) ?? 0,
            appUsage: try container.decodeIfPresent([AppUsageBreakdown].self, forKey: .appUsage) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workMinutes, forKey: .workMinutes)
        try container.encode(gamingMinutes, forKey: .gamingMinutes)
        try container.encode(meaningfulGamingMinutes, forKey: .meaningfulGamingMinutes)
        try container.encode(distractingMinutes, forKey: .distractingMinutes)
        try container.encode(gamingOrDistractingMinutes, forKey: .gamingOrDistractingMinutes)
        try container.encode(idleMinutes, forKey: .idleMinutes)
        try container.encode(unknownMinutes, forKey: .unknownMinutes)
        try container.encode(appUsage, forKey: .appUsage)
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
    case boundedSprint
    case mainObjective
    case userLocked
    case limitedCoverage
}

public struct NextTaskRecommendation: Equatable, Codable, Sendable {
    public let taskID: String?
    public let sentence: String
    public let reasons: [RecommendationReasonCode]
    public let coverageUncertainty: String?
    public let suggestedSprintMinutes: Int?

    public init(
        taskID: String?,
        sentence: String,
        reasons: [RecommendationReasonCode],
        coverageUncertainty: String? = nil,
        suggestedSprintMinutes: Int? = nil
    ) {
        self.taskID = taskID
        self.sentence = sentence
        self.reasons = reasons
        self.coverageUncertainty = coverageUncertainty
        self.suggestedSprintMinutes = suggestedSprintMinutes
    }
}

public enum CoachingLevel: String, Codable, CaseIterable, Sendable {
    case gentle
    case accountability

    public var maximumDailyPrompts: Int { self == .gentle ? 1 : 3 }
    public var cooldownMinutes: Int { self == .gentle ? 180 : 60 }
}

public struct GamingPolicy: Equatable, Codable, Sendable {
    public static let flexible = GamingPolicy(
        dailyBudgetMinutes: 90,
        priorityTaskRewardMinutes: 0
    )
    public static let balanced = GamingPolicy(
        dailyBudgetMinutes: 60,
        priorityTaskRewardMinutes: 15
    )
    public static let firm = GamingPolicy(
        dailyBudgetMinutes: 30,
        priorityTaskRewardMinutes: 30
    )

    public let version: Int
    public let dailyBudgetMinutes: Int
    public let priorityTaskRewardMinutes: Int
    public let coachingLevel: CoachingLevel
    public let intentionalOverrideMinutes: Int
    public let dailyPromptCap: Int
    public let promptCooldownMinutes: Int
    public let taskStartGraceMinutes: Int
    public let returnFromIdleGraceMinutes: Int
    public let budgetEnabled: Bool

    public init(
        version: Int = 1,
        dailyBudgetMinutes: Int = 60,
        priorityTaskRewardMinutes: Int = 15,
        coachingLevel: CoachingLevel = .gentle,
        intentionalOverrideMinutes: Int = 45,
        dailyPromptCap: Int? = nil,
        promptCooldownMinutes: Int? = nil,
        taskStartGraceMinutes: Int = 3,
        returnFromIdleGraceMinutes: Int = 1,
        budgetEnabled: Bool = true
    ) {
        self.version = version
        self.dailyBudgetMinutes = max(0, dailyBudgetMinutes)
        self.priorityTaskRewardMinutes = max(0, priorityTaskRewardMinutes)
        self.coachingLevel = coachingLevel
        self.intentionalOverrideMinutes = max(5, intentionalOverrideMinutes)
        self.dailyPromptCap = max(1, dailyPromptCap ?? coachingLevel.maximumDailyPrompts)
        self.promptCooldownMinutes = max(5, promptCooldownMinutes ?? coachingLevel.cooldownMinutes)
        self.taskStartGraceMinutes = max(0, taskStartGraceMinutes)
        self.returnFromIdleGraceMinutes = max(0, returnFromIdleGraceMinutes)
        self.budgetEnabled = budgetEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case version, dailyBudgetMinutes, priorityTaskRewardMinutes, coachingLevel, intentionalOverrideMinutes, dailyPromptCap, promptCooldownMinutes, taskStartGraceMinutes, returnFromIdleGraceMinutes, budgetEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            dailyBudgetMinutes: try container.decodeIfPresent(Int.self, forKey: .dailyBudgetMinutes) ?? 60,
            priorityTaskRewardMinutes: try container.decodeIfPresent(Int.self, forKey: .priorityTaskRewardMinutes) ?? 15,
            coachingLevel: try container.decodeIfPresent(CoachingLevel.self, forKey: .coachingLevel) ?? .gentle,
            intentionalOverrideMinutes: try container.decodeIfPresent(Int.self, forKey: .intentionalOverrideMinutes) ?? 45,
            dailyPromptCap: try container.decodeIfPresent(Int.self, forKey: .dailyPromptCap),
            promptCooldownMinutes: try container.decodeIfPresent(Int.self, forKey: .promptCooldownMinutes),
            taskStartGraceMinutes: try container.decodeIfPresent(Int.self, forKey: .taskStartGraceMinutes) ?? 3,
            returnFromIdleGraceMinutes: try container.decodeIfPresent(Int.self, forKey: .returnFromIdleGraceMinutes) ?? 1,
            budgetEnabled: try container.decodeIfPresent(Bool.self, forKey: .budgetEnabled) ?? true
        )
    }
}

public struct GamingStatus: Equatable, Codable, Sendable {
    public static let meaningfulSessionExplanation = "Gaming sessions under 2 continuous minutes are observed but do not use the allowance."
    public let budgetMinutes: Int
    public let earnedMinutes: Int
    public let manualAdjustmentMinutes: Int
    public let usedMinutes: Int
    public let unlockedRemainingMinutes: Int
    public let lockedMinutes: Int
    public let overageMinutes: Int
    public let nextUnlockReason: String
    public let confidenceIsLimited: Bool
    public let budgetEnabled: Bool

    public init(budgetMinutes: Int, earnedMinutes: Int = 0, manualAdjustmentMinutes: Int = 0, usedMinutes: Int, unlockedRemainingMinutes: Int, lockedMinutes: Int = 0, overageMinutes: Int = 0, nextUnlockReason: String, confidenceIsLimited: Bool, budgetEnabled: Bool = true) {
        self.budgetMinutes = max(0, budgetMinutes)
        self.earnedMinutes = max(0, earnedMinutes)
        self.manualAdjustmentMinutes = max(0, manualAdjustmentMinutes)
        self.usedMinutes = max(0, usedMinutes)
        self.unlockedRemainingMinutes = max(0, unlockedRemainingMinutes)
        self.lockedMinutes = max(0, lockedMinutes)
        self.overageMinutes = max(0, overageMinutes)
        self.nextUnlockReason = nextUnlockReason
        self.confidenceIsLimited = confidenceIsLimited
        self.budgetEnabled = budgetEnabled
    }

    public var allowanceBreakdown: String {
        let manual = manualAdjustmentMinutes > 0 ? " · Manual +\(manualAdjustmentMinutes)m" : ""
        return "Base \(budgetMinutes)m · Earned \(earnedMinutes)m\(manual) · Used \(usedMinutes)m · Locked \(lockedMinutes)m · Remaining \(unlockedRemainingMinutes)m · Same-day overage \(overageMinutes)m"
    }

    public func applyingManualAdjustment(_ minutes: Int) -> GamingStatus {
        guard budgetEnabled else { return self }
        let manualMinutes = max(0, minutes)
        let allowance = budgetMinutes + earnedMinutes + manualMinutes
        return GamingStatus(
            budgetMinutes: budgetMinutes,
            earnedMinutes: earnedMinutes,
            manualAdjustmentMinutes: manualMinutes,
            usedMinutes: usedMinutes,
            unlockedRemainingMinutes: max(0, allowance - usedMinutes),
            lockedMinutes: lockedMinutes,
            overageMinutes: max(0, usedMinutes - allowance),
            nextUnlockReason: nextUnlockReason,
            confidenceIsLimited: confidenceIsLimited,
            budgetEnabled: budgetEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case budgetMinutes, earnedMinutes, manualAdjustmentMinutes, usedMinutes, unlockedRemainingMinutes, lockedMinutes, overageMinutes, nextUnlockReason, confidenceIsLimited, budgetEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            budgetMinutes: try container.decode(Int.self, forKey: .budgetMinutes),
            earnedMinutes: try container.decodeIfPresent(Int.self, forKey: .earnedMinutes) ?? 0,
            manualAdjustmentMinutes: try container.decodeIfPresent(Int.self, forKey: .manualAdjustmentMinutes) ?? 0,
            usedMinutes: try container.decode(Int.self, forKey: .usedMinutes),
            unlockedRemainingMinutes: try container.decode(Int.self, forKey: .unlockedRemainingMinutes),
            lockedMinutes: try container.decodeIfPresent(Int.self, forKey: .lockedMinutes) ?? 0,
            overageMinutes: try container.decodeIfPresent(Int.self, forKey: .overageMinutes) ?? 0,
            nextUnlockReason: try container.decode(String.self, forKey: .nextUnlockReason),
            confidenceIsLimited: try container.decode(Bool.self, forKey: .confidenceIsLimited),
            budgetEnabled: try container.decodeIfPresent(Bool.self, forKey: .budgetEnabled) ?? true
        )
    }
}

public struct ActiveTaskSnapshot: Equatable, Codable, Sendable {
    public let taskID: String
    public let startedAt: Date?
    public let elapsedMinutes: Int
    public let sprint: SprintSnapshot?

    public init(taskID: String, startedAt: Date?, elapsedMinutes: Int, sprint: SprintSnapshot? = nil) {
        self.taskID = taskID
        self.startedAt = startedAt
        self.elapsedMinutes = max(0, elapsedMinutes)
        self.sprint = sprint
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
    public let activeTaskContext: ActiveTaskContextAssessment?
    public let recommendation: NextTaskRecommendation
    public let behavior: BehaviorSummary
    public let coverage: TelemetryCoverage
    public let gaming: GamingStatus
    public let sourceFreshnessExplanation: String
    public let unplannedReminders: [TodayReminderQueueRow]?
    public let sources: [SourceFreshnessSnapshot]?
    public let planningStatus: PlanningDayStatus?

    public init(localDate: Date, timeZoneIdentifier: String, mainObjective: String?, taskRows: [TodayTaskRow], activeTask: ActiveTaskSnapshot?, activeTaskContext: ActiveTaskContextAssessment? = nil, recommendation: NextTaskRecommendation, behavior: BehaviorSummary, coverage: TelemetryCoverage, gaming: GamingStatus, sourceFreshnessExplanation: String, unplannedReminders: [TodayReminderQueueRow] = [], sources: [SourceFreshnessSnapshot] = [], planningStatus: PlanningDayStatus? = nil) {
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.mainObjective = mainObjective
        self.taskRows = taskRows
        self.activeTask = activeTask
        self.activeTaskContext = activeTaskContext
        self.recommendation = recommendation
        self.behavior = behavior
        self.coverage = coverage
        self.gaming = gaming
        self.sourceFreshnessExplanation = sourceFreshnessExplanation
        self.unplannedReminders = unplannedReminders
        self.sources = sources
        self.planningStatus = planningStatus
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
        var gamingRuns: [TimeInterval] = []
        var currentGamingRun: TimeInterval = 0
        var applicationTotals: [AppUsageKey: TimeInterval] = [:]
        for (index, observation) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].observedAt : now
            let rawElapsed = max(0, next.timeIntervalSince(observation.observedAt))
            guard rawElapsed <= inactivityGap else {
                if currentGamingRun > 0 {
                    gamingRuns.append(currentGamingRun)
                    currentGamingRun = 0
                }
                continue
            }
            let elapsed = min(maximumObservationDuration, rawElapsed)
            totals[observation.classification, default: 0] += elapsed
            if observation.classification == .gaming {
                currentGamingRun += elapsed
            } else if currentGamingRun > 0 {
                gamingRuns.append(currentGamingRun)
                currentGamingRun = 0
            }
            let application = observation.application?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Unknown application"
            let applicationKey = AppUsageKey(application: application, classification: observation.classification)
            applicationTotals[applicationKey, default: 0] += elapsed
        }
        if currentGamingRun > 0 { gamingRuns.append(currentGamingRun) }
        let meaningfulGamingSeconds = gamingRuns.filter { $0 >= 120 }.reduce(0, +)
        let limited = now.timeIntervalSince(last.observedAt) > staleAfter
        let totalApplicationSeconds = applicationTotals.values.reduce(0, +)
        let appUsage = applicationTotals
            .map { key, seconds in
                AppUsageBreakdown(
                    application: key.application,
                    observedSeconds: Int(seconds.rounded()),
                    percentage: totalApplicationSeconds > 0 ? seconds / totalApplicationSeconds * 100 : 0,
                    classification: key.classification
                )
            }
            .sorted {
                if $0.observedSeconds != $1.observedSeconds { return $0.observedSeconds > $1.observedSeconds }
                if ($0.classification == .work) != ($1.classification == .work) {
                    return $0.classification == .work
                }
                return $0.application.localizedCaseInsensitiveCompare($1.application) == .orderedAscending
            }
        let summary = BehaviorSummary(
            workMinutes: Int(totals[.work, default: 0] / 60),
            gamingMinutes: Int(totals[.gaming, default: 0] / 60),
            meaningfulGamingMinutes: Int(meaningfulGamingSeconds / 60),
            distractingMinutes: Int(totals[.distracting, default: 0] / 60),
            idleMinutes: Int(totals[.idle, default: 0] / 60),
            unknownMinutes: Int(totals[.unknown, default: 0] / 60),
            appUsage: appUsage
        )
        let coverage = TelemetryCoverage(isLimited: limited, explanation: limited ? "Limited coverage: Screenwatch is stale." : "Screenwatch coverage is current.", lastObservationAt: last.observedAt)
        return (summary, coverage)
    }
}

private struct AppUsageKey: Hashable {
    let application: String
    let classification: BehaviorClassification
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public struct BehaviorClassifier: Sendable {
    private let policy: BehaviorPolicy

    public init(policy: BehaviorPolicy = BehaviorPolicy()) {
        self.policy = policy
    }

    public func classify(application: String) -> BehaviorClassification {
        if let override = policy.classificationOverride(for: application) { return override }
        let normalized = application.lowercased()
        if ["steam", "league of legends", "minecraft", "roblox", "discord"].contains(where: normalized.contains) { return .gaming }
        if ["youtube", "tiktok", "instagram", "twitter", "x.com", "reddit"].contains(where: normalized.contains) { return .distracting }
        if ["screensaver", "loginwindow"].contains(where: normalized.contains) { return .idle }
        if WorkCategoryClassifier().category(for: application) != nil { return .work }
        if ["xcode", "cursor", "visual studio code", "terminal", "iterm", "codex", "chatgpt", "figma", "pages", "numbers", "keynote", "mail", "calendar", "reminders", "slack"].contains(where: normalized.contains) { return .work }
        return .unknown
    }
}

public enum RecommendationSprintPresentation {
    public static func durationMinutes(estimateMinutes: Int, availableMinutes: Int) -> Int? {
        guard estimateMinutes > availableMinutes, availableMinutes > 0 else { return nil }
        return min(25, availableMinutes)
    }

    public static func sentence(taskTitle: String, sprintMinutes: Int, availableMinutes: Int) -> String {
        let availableLabel = "\(availableMinutes) minute\(availableMinutes == 1 ? "" : "s")"
        return "Start \"\(taskTitle)\" with a \(sprintMinutes)-minute sprint. It is larger than the \(availableLabel) available, and the task will stay incomplete when the sprint ends."
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
        let suggestedSprintMinutes = task.estimateMinutes > availableMinutes && availableMinutes > 0
            ? min(25, availableMinutes)
            : nil
        if suggestedSprintMinutes != nil { reasons.append(.boundedSprint) }
        if task.isMainObjective { reasons.append(.mainObjective) }
        if task.isLocked { reasons.append(.userLocked) }
        if coverage.isLimited { reasons.append(.limitedCoverage) }
        let sentence: String
        if let suggestedSprintMinutes {
            let availableLabel = "\(availableMinutes) minute\(availableMinutes == 1 ? "" : "s")"
            sentence = "Start \"\(task.title)\" with a \(suggestedSprintMinutes)-minute sprint. It is larger than the \(availableLabel) available, and the task will stay incomplete when the sprint ends."
        } else {
            let detail = reasons.contains(.overdue) ? "It is overdue." : reasons.contains(.dueToday) ? "It is due today." : task.estimateMinutes <= availableMinutes ? "It fits the time you have." : "It is your highest ready priority."
            sentence = "Start \"\(task.title)\" now. \(detail)"
        }
        return NextTaskRecommendation(
            taskID: task.taskID,
            sentence: sentence,
            reasons: reasons,
            coverageUncertainty: coverage.isLimited ? coverage.explanation : nil,
            suggestedSprintMinutes: suggestedSprintMinutes
        )
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
        status(
            policy: policy,
            gamingMinutes: gamingMinutes,
            appliedRewardMinutes: rewardApplied ? policy.priorityTaskRewardMinutes : nil,
            coverage: coverage
        )
    }

    public func status(
        policy: GamingPolicy,
        gamingMinutes: Int,
        appliedRewardMinutes: Int?,
        coverage: TelemetryCoverage
    ) -> GamingStatus {
        guard policy.budgetEnabled else {
            return GamingStatus(
                budgetMinutes: 0,
                usedMinutes: gamingMinutes,
                unlockedRemainingMinutes: 0,
                nextUnlockReason: "Observation only. No gaming budget, unlock, debt, or coaching prompt is applied.",
                confidenceIsLimited: coverage.isLimited,
                budgetEnabled: false
            )
        }
        let rewardMinutes = max(0, appliedRewardMinutes ?? 0)
        let allowance = policy.dailyBudgetMinutes + rewardMinutes
        let nextUnlockReason: String
        if rewardMinutes > 0 {
            nextUnlockReason = "Priority-task reward already applied today."
        } else if policy.priorityTaskRewardMinutes == 0 {
            nextUnlockReason = "This policy uses a fixed daily gaming budget."
        } else {
            nextUnlockReason = "Finish one priority task to unlock a one-time reward."
        }
        return GamingStatus(
            budgetMinutes: policy.dailyBudgetMinutes,
            earnedMinutes: rewardMinutes,
            usedMinutes: gamingMinutes,
            unlockedRemainingMinutes: max(0, allowance - gamingMinutes),
            lockedMinutes: rewardMinutes == 0 ? policy.priorityTaskRewardMinutes : 0,
            overageMinutes: max(0, gamingMinutes - allowance),
            nextUnlockReason: nextUnlockReason,
            confidenceIsLimited: coverage.isLimited
        )
    }
}

public enum TodayReminderEligibility {
    public static func isVisible(
        dueDate: Date?,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let dueDate else { return true }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))
        guard let tomorrow else { return false }
        return dueDate < tomorrow
    }
}
