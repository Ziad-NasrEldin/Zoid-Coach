import Foundation

public struct WakePlanEvidence: Equatable, Sendable {
    public let mainObjectiveScore: Int
    public let plannedFocusMinutes: Int
    public let completedInterventionsToday: Int

    public init(mainObjectiveScore: Int, plannedFocusMinutes: Int, completedInterventionsToday: Int) {
        self.mainObjectiveScore = mainObjectiveScore
        self.plannedFocusMinutes = max(0, plannedFocusMinutes)
        self.completedInterventionsToday = max(0, completedInterventionsToday)
    }
}

public enum WakeUpDecision: Equatable, Sendable {
    case eligible(reason: String)
    case ineligible(reason: String)
}

public struct WakeUpPolicy: Equatable, Sendable {
    public let windowStartHour: Int
    public let windowEndHour: Int
    public let maximumDailyInterventions: Int
    public let minimumMainObjectiveScore: Int

    public init(
        windowStartHour: Int = 7,
        windowEndHour: Int = 9,
        maximumDailyInterventions: Int = 1,
        minimumMainObjectiveScore: Int = 700
    ) {
        self.windowStartHour = min(max(windowStartHour, 0), 23)
        self.windowEndHour = min(max(windowEndHour, 0), 23)
        self.maximumDailyInterventions = max(0, maximumDailyInterventions)
        self.minimumMainObjectiveScore = max(0, minimumMainObjectiveScore)
    }

    public func decision(for evidence: WakePlanEvidence) -> WakeUpDecision {
        guard maximumDailyInterventions > evidence.completedInterventionsToday else {
            return .ineligible(reason: "Daily intervention budget reached")
        }
        guard evidence.mainObjectiveScore >= minimumMainObjectiveScore, evidence.plannedFocusMinutes > 0 else {
            return .ineligible(reason: "No high-consequence commitment")
        }
        return .eligible(reason: "High-consequence daily commitment")
    }
}
