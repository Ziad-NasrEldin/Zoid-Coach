import Foundation

public enum BaselineDayCoverage: String, Codable, Equatable, Sendable {
    case complete
    case limited
    case missing
}

public struct BaselineObservationDay: Identifiable, Equatable, Sendable {
    public let localDay: String
    public let observedMinutes: Int
    public let workMinutes: Int
    public let gamingMinutes: Int
    public let distractingMinutes: Int
    public let unknownMinutes: Int
    public let eligibleDriftCount: Int
    public let coverage: BaselineDayCoverage
    public let recordedAt: Date

    public init(
        localDay: String,
        observedMinutes: Int,
        workMinutes: Int,
        gamingMinutes: Int,
        distractingMinutes: Int,
        unknownMinutes: Int,
        eligibleDriftCount: Int,
        coverage: BaselineDayCoverage,
        recordedAt: Date
    ) {
        self.localDay = localDay
        self.observedMinutes = max(0, observedMinutes)
        self.workMinutes = max(0, workMinutes)
        self.gamingMinutes = max(0, gamingMinutes)
        self.distractingMinutes = max(0, distractingMinutes)
        self.unknownMinutes = max(0, unknownMinutes)
        self.eligibleDriftCount = max(0, eligibleDriftCount)
        self.coverage = coverage
        self.recordedAt = recordedAt
    }

    public var id: String { localDay }
    public var countsTowardBaseline: Bool { coverage == .complete }
}

public struct BaselineObservationReport: Equatable, Sendable {
    public let averageObservedWorkMinutes: Int
    public let gamingDayCount: Int
    public let totalGamingMinutes: Int
    public let eligibleDriftCount: Int
    public let unknownSharePercent: Int

    public init(
        averageObservedWorkMinutes: Int,
        gamingDayCount: Int,
        totalGamingMinutes: Int,
        eligibleDriftCount: Int,
        unknownSharePercent: Int
    ) {
        self.averageObservedWorkMinutes = max(0, averageObservedWorkMinutes)
        self.gamingDayCount = max(0, gamingDayCount)
        self.totalGamingMinutes = max(0, totalGamingMinutes)
        self.eligibleDriftCount = max(0, eligibleDriftCount)
        self.unknownSharePercent = min(100, max(0, unknownSharePercent))
    }

    public var alertSensitivityGuidance: String {
        if unknownSharePercent >= 30 {
            return "Coverage is still too uncertain for stronger alerts. Keep coaching in observation until unknown time is reduced."
        }
        if eligibleDriftCount == 0 {
            return "No eligible drift was observed. Start with gentle alerts and review again after more varied days."
        }
        if eligibleDriftCount >= 7 {
            return "Drift appeared often enough to begin with the configured coaching level, while keeping every prompt dismissible."
        }
        return "A small number of drift candidates appeared. Begin with gentle alerts and adjust after reviewing real prompt usefulness."
    }
}

public struct BaselineObservationStatus: Equatable, Sendable {
    public let requiredCompleteDays: Int
    public let days: [BaselineObservationDay]
    public let report: BaselineObservationReport

    public init(
        requiredCompleteDays: Int = 7,
        days: [BaselineObservationDay],
        report: BaselineObservationReport
    ) {
        self.requiredCompleteDays = max(1, requiredCompleteDays)
        self.days = days.sorted { $0.localDay < $1.localDay }
        self.report = report
    }

    public var completeDayCount: Int { days.filter(\.countsTowardBaseline).count }
    public var remainingCompleteDays: Int { max(0, requiredCompleteDays - completeDayCount) }
    public var isComplete: Bool { completeDayCount >= requiredCompleteDays }
    public var suppressesBehaviorPrompts: Bool { !isComplete }
    public var progress: Double {
        min(1, Double(completeDayCount) / Double(requiredCompleteDays))
    }
    public var observedEligibleDriftCount: Int {
        days.reduce(0) { $0 + $1.eligibleDriftCount }
    }
}
