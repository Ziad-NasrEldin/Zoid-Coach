import Foundation

public enum TaskEstimateProgressPhase: String, Equatable, Sendable {
    case notStarted
    case underway
    case nearingEstimate
    case overEstimate
}

public struct TaskEstimateProgress: Equatable, Sendable {
    public let elapsedMinutes: Int
    public let estimateMinutes: Int

    public init(elapsedMinutes: Int, estimateMinutes: Int) {
        self.elapsedMinutes = max(0, elapsedMinutes)
        self.estimateMinutes = max(1, estimateMinutes)
    }

    public var percent: Int {
        let rawPercent = Double(elapsedMinutes) / Double(estimateMinutes) * 100
        return rawPercent >= Double(Int.max) ? Int.max : Int(rawPercent.rounded())
    }

    public var boundedFraction: Double {
        min(1, Double(elapsedMinutes) / Double(estimateMinutes))
    }

    public var phase: TaskEstimateProgressPhase {
        if elapsedMinutes == 0 { return .notStarted }
        if elapsedMinutes > estimateMinutes { return .overEstimate }
        if percent >= 80 { return .nearingEstimate }
        return .underway
    }

    public var remainingMinutes: Int {
        max(0, estimateMinutes - elapsedMinutes)
    }

    public var overrunMinutes: Int {
        max(0, elapsedMinutes - estimateMinutes)
    }

    public var statusLabel: String {
        switch phase {
        case .notStarted:
            return "Not started"
        case .underway:
            return "\(remainingMinutes) min remaining in estimate"
        case .nearingEstimate:
            return remainingMinutes == 0 ? "Estimate reached" : "\(remainingMinutes) min remaining in estimate"
        case .overEstimate:
            return "\(overrunMinutes) min over estimate"
        }
    }

    public var accessibilitySummary: String {
        "\(elapsedMinutes) minutes tracked of \(estimateMinutes) estimated, \(statusLabel.lowercased())."
    }

    public func addingElapsedMinutes(_ additionalMinutes: Int) -> TaskEstimateProgress {
        let (updatedElapsed, overflowed) = elapsedMinutes.addingReportingOverflow(max(0, additionalMinutes))
        return TaskEstimateProgress(
            elapsedMinutes: overflowed ? Int.max : updatedElapsed,
            estimateMinutes: estimateMinutes
        )
    }
}
