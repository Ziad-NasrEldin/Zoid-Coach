import Foundation

public enum WeeklyReviewEvidenceQuality: String, Codable, Sendable {
    case sufficient
    case limited
}

public struct WeeklyReviewDateRange: Equatable, Codable, Sendable {
    public let startDay: String
    public let endDay: String

    public init(startDay: String, endDay: String) {
        self.startDay = startDay
        self.endDay = endDay
    }
}

public struct WeeklyReviewOutcomeSummary: Equatable, Codable, Sendable {
    public let plannedTasks: Int
    public let completedTasks: Int
    public let plannedMinutes: Int
    public let completedPercent: Int

    public init(plannedTasks: Int, completedTasks: Int, plannedMinutes: Int) {
        self.plannedTasks = max(0, plannedTasks)
        self.completedTasks = max(0, min(completedTasks, plannedTasks))
        self.plannedMinutes = max(0, plannedMinutes)
        completedPercent = plannedTasks == 0
            ? 0
            : Int((Double(self.completedTasks) / Double(self.plannedTasks) * 100).rounded())
    }
}

public enum WeeklyReviewPatternKind: String, Codable, CaseIterable, Sendable {
    case estimateAccuracy
    case bestWorkWindow
    case driftTrigger
    case gamingBudget
    case promptRecovery
    case promptUsefulness
    case blockedTasks
}

public struct WeeklyReviewPattern: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let kind: WeeklyReviewPatternKind
    public let title: String
    public let conclusion: String
    public let sampleCount: Int
    public let dateRange: WeeklyReviewDateRange
    public let examples: [String]
    public let confidencePercent: Int
    public let alternativeExplanation: String

    public init(
        id: String,
        kind: WeeklyReviewPatternKind,
        title: String,
        conclusion: String,
        sampleCount: Int,
        dateRange: WeeklyReviewDateRange,
        examples: [String],
        confidencePercent: Int,
        alternativeExplanation: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.conclusion = conclusion
        self.sampleCount = max(0, sampleCount)
        self.dateRange = dateRange
        self.examples = Array(examples.prefix(3))
        self.confidencePercent = min(100, max(0, confidencePercent))
        self.alternativeExplanation = alternativeExplanation
    }
}

public enum WeeklyExperimentState: String, Codable, Sendable {
    case proposed
    case accepted
    case rejected
}

public struct WeeklyExperiment: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let reviewWeekStart: String
    public let title: String
    public let instruction: String
    public let measurement: String
    public let state: WeeklyExperimentState
    public let trackingWeekStart: String?
    public let trackingDaysCompleted: Int
    public let updatedAt: Date

    public init(
        id: String,
        reviewWeekStart: String,
        title: String,
        instruction: String,
        measurement: String,
        state: WeeklyExperimentState,
        trackingWeekStart: String? = nil,
        trackingDaysCompleted: Int = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.reviewWeekStart = reviewWeekStart
        self.title = title
        self.instruction = instruction
        self.measurement = measurement
        self.state = state
        self.trackingWeekStart = trackingWeekStart
        self.trackingDaysCompleted = max(0, min(7, trackingDaysCompleted))
        self.updatedAt = updatedAt
    }
}

public struct WeeklyReviewSnapshot: Equatable, Sendable {
    public static let minimumCoveredDays = 3

    public let dateRange: WeeklyReviewDateRange
    public let coveredDays: Int
    public let totalDays: Int
    public let quality: WeeklyReviewEvidenceQuality
    public let qualityExplanation: String
    public let outcomes: WeeklyReviewOutcomeSummary
    public let patterns: [WeeklyReviewPattern]
    public let experiment: WeeklyExperiment?

    public init(
        dateRange: WeeklyReviewDateRange,
        coveredDays: Int,
        totalDays: Int = 7,
        quality: WeeklyReviewEvidenceQuality,
        qualityExplanation: String,
        outcomes: WeeklyReviewOutcomeSummary,
        patterns: [WeeklyReviewPattern],
        experiment: WeeklyExperiment?
    ) {
        self.dateRange = dateRange
        self.coveredDays = max(0, min(totalDays, coveredDays))
        self.totalDays = max(1, totalDays)
        self.quality = quality
        self.qualityExplanation = qualityExplanation
        self.outcomes = outcomes
        self.patterns = patterns
        self.experiment = experiment
    }
}
