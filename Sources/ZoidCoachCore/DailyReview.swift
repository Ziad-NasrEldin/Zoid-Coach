import Foundation

public struct DailyReviewSession: Identifiable, Equatable, Sendable {
    public let sourceDay: String
    public let start: Date
    public let end: Date
    public let application: String
    public let classification: BehaviorClassification
    public let taskID: String?
    public let observationCount: Int

    public init(
        sourceDay: String,
        start: Date,
        end: Date,
        application: String,
        classification: BehaviorClassification,
        taskID: String? = nil,
        observationCount: Int
    ) {
        self.sourceDay = sourceDay
        self.start = start
        self.end = max(start, end)
        self.application = application
        self.classification = classification
        self.taskID = taskID
        self.observationCount = max(1, observationCount)
    }

    public var id: String { "\(sourceDay):\(Int(start.timeIntervalSince1970))" }
    public var durationMinutes: Int {
        max(1, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
    }
}

public struct DailyReviewTotal: Identifiable, Equatable, Sendable {
    public let classification: BehaviorClassification
    public let minutes: Int

    public init(classification: BehaviorClassification, minutes: Int) {
        self.classification = classification
        self.minutes = max(0, minutes)
    }

    public var id: BehaviorClassification { classification }
}

public struct AppClassificationCorrectionRule: Identifiable, Equatable, Sendable {
    public let application: String
    public let normalizedApplication: String
    public let classification: BehaviorClassification
    public let sourceDay: String
    public let sourceSessionStart: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        application: String,
        normalizedApplication: String,
        classification: BehaviorClassification,
        sourceDay: String,
        sourceSessionStart: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.application = application
        self.normalizedApplication = normalizedApplication
        self.classification = classification
        self.sourceDay = sourceDay
        self.sourceSessionStart = sourceSessionStart
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var id: String { normalizedApplication }
}

public struct OfflineWorkEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceDay: String
    public let taskID: String?
    public let startedAt: Date
    public let durationMinutes: Int
    public let note: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        sourceDay: String,
        taskID: String? = nil,
        startedAt: Date,
        durationMinutes: Int,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sourceDay = sourceDay
        self.taskID = taskID
        self.startedAt = startedAt
        self.durationMinutes = max(1, durationMinutes)
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DailyReviewHypothesisState: String, Codable, Sendable {
    case pending
    case accepted
    case rejected
}

public struct DailyReviewPlannedTaskOutcome: Identifiable, Equatable, Sendable {
    public let taskID: String
    public let title: String
    public let isMainObjective: Bool
    public let estimatedMinutes: Int?
    public let isCompleted: Bool

    public var id: String { taskID }

    public init(
        taskID: String,
        title: String,
        isMainObjective: Bool,
        estimatedMinutes: Int?,
        isCompleted: Bool
    ) {
        self.taskID = taskID
        self.title = title
        self.isMainObjective = isMainObjective
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = isCompleted
    }
}

public enum DailyReviewCoachingOutcome: Equatable, Sendable {
    case unanswered
    case effectPending
    case recoveryStarted
    case returnedToWork(observedMinutes: Int, selectedTaskMatched: Bool)
    case acceptedBreak
    case intentionalChoice
    case extensionRecorded
    case responseRecorded
}

public struct DailyReviewCoachingInteraction: Identifiable, Equatable, Sendable {
    public let promptID: String
    public let promptType: String
    public let title: String
    public let summary: String
    public let createdAt: Date
    public let responseAction: String?
    public let responseSurface: String?
    public let respondedAt: Date?
    public let effectWasApplied: Bool?
    public let observedApplication: String?
    public let observedGamingMinutes: Int?
    public let unfinishedTaskTitle: String?
    public let outcome: DailyReviewCoachingOutcome

    public var id: String { promptID }

    public init(
        promptID: String,
        promptType: String,
        title: String,
        summary: String,
        createdAt: Date,
        responseAction: String?,
        responseSurface: String?,
        respondedAt: Date?,
        effectWasApplied: Bool?,
        observedApplication: String?,
        observedGamingMinutes: Int?,
        unfinishedTaskTitle: String?,
        outcome: DailyReviewCoachingOutcome
    ) {
        self.promptID = promptID
        self.promptType = promptType
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.responseAction = responseAction
        self.responseSurface = responseSurface
        self.respondedAt = respondedAt
        self.effectWasApplied = effectWasApplied
        self.observedApplication = observedApplication
        self.observedGamingMinutes = observedGamingMinutes
        self.unfinishedTaskTitle = unfinishedTaskTitle
        self.outcome = outcome
    }
}

public struct DailyReviewSnapshot: Equatable, Sendable {
    public let sourceDay: String
    public let sessions: [DailyReviewSession]
    public let totals: [DailyReviewTotal]
    public let hypothesis: String?
    public let hypothesisState: DailyReviewHypothesisState
    public let confirmedAt: Date?
    public let offlineWork: [OfflineWorkEntry]
    public let completedTasks: [CompletedTaskHistoryEntry]
    public let plannedTasks: [DailyReviewPlannedTaskOutcome]
    public let coachingInteractions: [DailyReviewCoachingInteraction]

    public init(
        sourceDay: String,
        sessions: [DailyReviewSession],
        totals: [DailyReviewTotal],
        hypothesis: String?,
        hypothesisState: DailyReviewHypothesisState,
        confirmedAt: Date?,
        offlineWork: [OfflineWorkEntry] = [],
        completedTasks: [CompletedTaskHistoryEntry] = [],
        plannedTasks: [DailyReviewPlannedTaskOutcome] = [],
        coachingInteractions: [DailyReviewCoachingInteraction] = []
    ) {
        self.sourceDay = sourceDay
        self.sessions = sessions
        self.totals = totals
        self.hypothesis = hypothesis
        self.hypothesisState = hypothesisState
        self.confirmedAt = confirmedAt
        self.offlineWork = offlineWork
        self.completedTasks = completedTasks
        self.plannedTasks = plannedTasks
        self.coachingInteractions = coachingInteractions
    }

    public var observedMinutes: Int { totals.reduce(0) { $0 + $1.minutes } }
    public var offlineMinutes: Int { offlineWork.reduce(0) { $0 + $1.durationMinutes } }
    public var actualMinutes: Int { observedMinutes + offlineMinutes }
    public var mainObjective: DailyReviewPlannedTaskOutcome? {
        plannedTasks.first(where: \.isMainObjective)
    }
    public var completedPriorityTaskCount: Int {
        plannedTasks.filter(\.isCompleted).count
    }
    public var bestObservedWorkBlock: DailyReviewSession? {
        longestSession(where: { $0.classification == .work })
    }
    public var largestObservedDriftEpisode: DailyReviewSession? {
        longestSession(where: { $0.classification == .gaming || $0.classification == .distracting })
    }

    private func longestSession(where predicate: (DailyReviewSession) -> Bool) -> DailyReviewSession? {
        sessions.filter(predicate).sorted {
            let leftDuration = $0.end.timeIntervalSince($0.start)
            let rightDuration = $1.end.timeIntervalSince($1.start)
            if leftDuration != rightDuration {
                return leftDuration > rightDuration
            }
            return $0.start < $1.start
        }.first
    }
}

public struct CompletedTaskHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let taskID: String
    public let title: String
    public let sourceKind: CompletedTaskSourceKind
    public let completedAt: Date
    public let lastPauseReason: TaskPauseReason?

    public init(
        id: Int64,
        taskID: String,
        title: String,
        sourceKind: CompletedTaskSourceKind,
        completedAt: Date,
        lastPauseReason: TaskPauseReason?
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.sourceKind = sourceKind
        self.completedAt = completedAt
        self.lastPauseReason = lastPauseReason
    }
}

public enum CompletedTaskSourceKind: String, Equatable, Sendable {
    case reminders
    case local
    case unknown
}

public enum DailyReviewSessionizer {
    public struct Observation: Equatable, Sendable {
        public let sourceDay: String
        public let observedAt: Date
        public let application: String
        public let classification: BehaviorClassification
        public let taskID: String?

        public init(
            sourceDay: String,
            observedAt: Date,
            application: String,
            classification: BehaviorClassification,
            taskID: String? = nil
        ) {
            self.sourceDay = sourceDay
            self.observedAt = observedAt
            self.application = application
            self.classification = classification
            self.taskID = taskID
        }
    }

    public static func sessions(
        from observations: [Observation],
        maximumGap: TimeInterval = 5 * 60
    ) -> [DailyReviewSession] {
        let ordered = observations.sorted { $0.observedAt < $1.observedAt }
        guard let first = ordered.first else { return [] }
        var result: [DailyReviewSession] = []
        var start = first.observedAt
        var previous = first
        var count = 1

        func appendSession(endingAt end: Date) {
            result.append(DailyReviewSession(
                sourceDay: previous.sourceDay,
                start: start,
                end: end.addingTimeInterval(60),
                application: previous.application,
                classification: previous.classification,
                taskID: previous.taskID,
                observationCount: count
            ))
        }

        for observation in ordered.dropFirst() {
            let continues = observation.sourceDay == previous.sourceDay
                && observation.application == previous.application
                && observation.classification == previous.classification
                && observation.taskID == previous.taskID
                && observation.observedAt.timeIntervalSince(previous.observedAt) <= maximumGap
            if continues {
                previous = observation
                count += 1
            } else {
                appendSession(endingAt: previous.observedAt)
                start = observation.observedAt
                previous = observation
                count = 1
            }
        }
        appendSession(endingAt: previous.observedAt)
        return result
    }

    public static func totals(for sessions: [DailyReviewSession]) -> [DailyReviewTotal] {
        let grouped = Dictionary(grouping: sessions, by: \.classification)
        return BehaviorClassification.allCases.compactMap { classification in
            guard let values = grouped[classification], !values.isEmpty else { return nil }
            return DailyReviewTotal(
                classification: classification,
                minutes: values.reduce(0) { $0 + $1.durationMinutes }
            )
        }
    }
}
