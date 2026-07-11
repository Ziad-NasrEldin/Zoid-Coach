import Foundation

public struct EstimateLearningContext: Equatable, Hashable, Codable, Sendable {
    public let taskType: String?
    public let project: String?

    public init(taskType: String?, project: String?) {
        self.taskType = taskType
        self.project = project
    }
}

public struct EstimateLearningSample: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let context: EstimateLearningContext
    public let estimatedMinutes: Int
    public let actualAlignedMinutes: Int
    public let trackingCoverage: Double
    public let completedAt: Date
    public let isEligible: Bool

    public init(
        id: String,
        context: EstimateLearningContext,
        estimatedMinutes: Int,
        actualAlignedMinutes: Int,
        trackingCoverage: Double,
        completedAt: Date,
        isEligible: Bool = true
    ) {
        self.id = id
        self.context = context
        self.estimatedMinutes = estimatedMinutes
        self.actualAlignedMinutes = actualAlignedMinutes
        self.trackingCoverage = trackingCoverage
        self.completedAt = completedAt
        self.isEligible = isEligible
    }
}

public struct EstimateLearningPolicy: Equatable, Codable, Sendable {
    public let version: Int
    public let minimumSamples: Int
    public let rollingSampleLimit: Int
    public let minimumTrackingCoverage: Double
    public let minimumRatio: Double
    public let maximumRatio: Double
    public let minimumRecommendedMinutes: Int
    public let maximumRecommendedMinutes: Int

    public init(
        version: Int = 1,
        minimumSamples: Int = 4,
        rollingSampleLimit: Int = 12,
        minimumTrackingCoverage: Double = 0.75,
        minimumRatio: Double = 0.5,
        maximumRatio: Double = 2,
        minimumRecommendedMinutes: Int = 15,
        maximumRecommendedMinutes: Int = 240
    ) {
        self.version = version
        self.minimumSamples = max(1, minimumSamples)
        self.rollingSampleLimit = max(1, rollingSampleLimit)
        self.minimumTrackingCoverage = min(max(minimumTrackingCoverage, 0), 1)
        self.minimumRatio = max(0.01, minimumRatio)
        self.maximumRatio = max(self.minimumRatio, maximumRatio)
        self.minimumRecommendedMinutes = max(1, minimumRecommendedMinutes)
        self.maximumRecommendedMinutes = max(self.minimumRecommendedMinutes, maximumRecommendedMinutes)
    }
}

public struct EstimateLearningProposal: Equatable, Codable, Sendable {
    public let policyVersion: Int
    public let generatedAt: Date
    public let sampleCount: Int
    public let evidenceIDs: [String]
    public let rawMedianRatio: Double
    public let appliedRatio: Double
    public let recommendedEstimateMinutes: Int
    public let rollbackEstimateMinutes: Int

    public init(
        policyVersion: Int,
        generatedAt: Date,
        sampleCount: Int,
        evidenceIDs: [String],
        rawMedianRatio: Double,
        appliedRatio: Double,
        recommendedEstimateMinutes: Int,
        rollbackEstimateMinutes: Int
    ) {
        self.policyVersion = policyVersion
        self.generatedAt = generatedAt
        self.sampleCount = sampleCount
        self.evidenceIDs = evidenceIDs
        self.rawMedianRatio = rawMedianRatio
        self.appliedRatio = appliedRatio
        self.recommendedEstimateMinutes = recommendedEstimateMinutes
        self.rollbackEstimateMinutes = rollbackEstimateMinutes
    }
}

public struct EstimateLearner: Sendable {
    private let clock: any ReplayClock

    public init(clock: any ReplayClock) {
        self.clock = clock
    }

    public func proposal(
        for context: EstimateLearningContext,
        currentEstimateMinutes: Int,
        samples: [EstimateLearningSample],
        policy: EstimateLearningPolicy = EstimateLearningPolicy()
    ) -> EstimateLearningProposal? {
        guard currentEstimateMinutes > 0 else { return nil }
        let eligible = samples
            .filter {
                $0.context == context &&
                    $0.isEligible &&
                    $0.estimatedMinutes > 0 &&
                    $0.actualAlignedMinutes > 0 &&
                    $0.trackingCoverage >= policy.minimumTrackingCoverage
            }
            .sorted {
                if $0.completedAt != $1.completedAt { return $0.completedAt > $1.completedAt }
                return $0.id < $1.id
            }
            .prefix(policy.rollingSampleLimit)
        guard eligible.count >= policy.minimumSamples else { return nil }

        let ratios = eligible.map { Double($0.actualAlignedMinutes) / Double($0.estimatedMinutes) }
        guard let rawMedianRatio = robustMedian(ratios) else { return nil }
        let appliedRatio = min(max(rawMedianRatio, policy.minimumRatio), policy.maximumRatio)
        let scaled = Double(currentEstimateMinutes) * appliedRatio
        let roundedToFive = Int((scaled / 5).rounded() * 5)
        let recommended = min(max(roundedToFive, policy.minimumRecommendedMinutes), policy.maximumRecommendedMinutes)
        return EstimateLearningProposal(
            policyVersion: policy.version,
            generatedAt: clock.now,
            sampleCount: eligible.count,
            evidenceIDs: eligible.map(\.id),
            rawMedianRatio: rawMedianRatio,
            appliedRatio: appliedRatio,
            recommendedEstimateMinutes: recommended,
            rollbackEstimateMinutes: currentEstimateMinutes
        )
    }
}

public struct WorkWindowLearningSample: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let trackingCoverage: Double
    public let isAlignedWork: Bool

    public init(id: String, startedAt: Date, endedAt: Date, trackingCoverage: Double, isAlignedWork: Bool = true) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trackingCoverage = trackingCoverage
        self.isAlignedWork = isAlignedWork
    }
}

public struct PreferredWorkWindowLearningPolicy: Equatable, Codable, Sendable {
    public let version: Int
    public let minimumSamples: Int
    public let rollingSampleLimit: Int
    public let minimumTrackingCoverage: Double
    public let minimumSessionMinutes: Int
    public let maximumLearnedDurationMinutes: Int

    public init(
        version: Int = 1,
        minimumSamples: Int = 5,
        rollingSampleLimit: Int = 21,
        minimumTrackingCoverage: Double = 0.75,
        minimumSessionMinutes: Int = 15,
        maximumLearnedDurationMinutes: Int = 240
    ) {
        self.version = version
        self.minimumSamples = max(1, minimumSamples)
        self.rollingSampleLimit = max(1, rollingSampleLimit)
        self.minimumTrackingCoverage = min(max(minimumTrackingCoverage, 0), 1)
        self.minimumSessionMinutes = max(1, minimumSessionMinutes)
        self.maximumLearnedDurationMinutes = max(self.minimumSessionMinutes, maximumLearnedDurationMinutes)
    }
}

public struct PreferredWorkWindowProposal: Equatable, Codable, Sendable {
    public let policyVersion: Int
    public let generatedAt: Date
    public let sampleCount: Int
    public let evidenceIDs: [String]
    public let preferredWindow: WeeklyWorkWindow
    public let rollbackWindow: WeeklyWorkWindow?

    public init(
        policyVersion: Int,
        generatedAt: Date,
        sampleCount: Int,
        evidenceIDs: [String],
        preferredWindow: WeeklyWorkWindow,
        rollbackWindow: WeeklyWorkWindow?
    ) {
        self.policyVersion = policyVersion
        self.generatedAt = generatedAt
        self.sampleCount = sampleCount
        self.evidenceIDs = evidenceIDs
        self.preferredWindow = preferredWindow
        self.rollbackWindow = rollbackWindow
    }
}

public struct PreferredWorkWindowLearner: Sendable {
    private let clock: any ReplayClock

    public init(clock: any ReplayClock) {
        self.clock = clock
    }

    public func proposal(
        samples: [WorkWindowLearningSample],
        timeZoneIdentifier: String,
        rollbackWindow: WeeklyWorkWindow? = nil,
        policy: PreferredWorkWindowLearningPolicy = PreferredWorkWindowLearningPolicy()
    ) -> PreferredWorkWindowProposal? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let eligible = samples
            .filter {
                let durationMinutes = Int($0.endedAt.timeIntervalSince($0.startedAt) / 60)
                return $0.isAlignedWork &&
                    $0.trackingCoverage >= policy.minimumTrackingCoverage &&
                    durationMinutes >= policy.minimumSessionMinutes
            }
            .sorted {
                if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
                return $0.id < $1.id
            }
            .prefix(policy.rollingSampleLimit)
        guard eligible.count >= policy.minimumSamples else { return nil }

        let startMinutes = eligible.map { sample -> Double in
            let components = calendar.dateComponents([.hour, .minute], from: sample.startedAt)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        let durations = eligible.map { min(Double($0.endedAt.timeIntervalSince($0.startedAt) / 60), Double(policy.maximumLearnedDurationMinutes)) }
        guard let medianStart = robustMedian(startMinutes), let medianDuration = robustMedian(durations) else { return nil }
        let startMinute = min(max(Int(medianStart.rounded()), 0), 1_438)
        let duration = min(max(Int(medianDuration.rounded()), policy.minimumSessionMinutes), policy.maximumLearnedDurationMinutes)
        let endMinute = min(startMinute + duration, 1_439)
        let weekdays = Set(eligible.compactMap { Weekday(rawValue: calendar.component(.weekday, from: $0.startedAt)) }).sorted()
        guard weekdays.isEmpty == false else { return nil }

        return PreferredWorkWindowProposal(
            policyVersion: policy.version,
            generatedAt: clock.now,
            sampleCount: eligible.count,
            evidenceIDs: eligible.map(\.id),
            preferredWindow: WeeklyWorkWindow(
                weekdays: weekdays,
                start: LocalTime(hour: startMinute / 60, minute: startMinute % 60),
                end: LocalTime(hour: endMinute / 60, minute: endMinute % 60)
            ),
            rollbackWindow: rollbackWindow
        )
    }
}

private func robustMedian(_ values: [Double]) -> Double? {
    let sorted = values.filter(\.isFinite).sorted()
    guard sorted.isEmpty == false else { return nil }
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
