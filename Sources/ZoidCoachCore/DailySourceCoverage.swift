import Foundation

public enum DailyCoveragePrecision: String, Equatable, Sendable {
    case exactWithinTrackedWindow
    case approximate
    case insufficient
}

public struct DailyCoverageSourceState: Equatable, Sendable {
    public let state: String
    public let detail: String
    public let evidence: String
    public let checkedAt: Date?

    public init(state: String, detail: String, evidence: String, checkedAt: Date?) {
        self.state = state
        self.detail = detail
        self.evidence = evidence
        self.checkedAt = checkedAt
    }

    public var isHealthy: Bool {
        ["healthy", "current", "connected", "ok"].contains(state.lowercased())
    }
}

public struct DailySourceCoverage: Equatable, Sendable {
    public let localDay: String
    public let activeTaskMinutes: Int
    public let observedTaskMinutes: Int
    public let alignedTaskMinutes: Int
    public let missingTaskMinutes: Int
    public let workMinutes: Int
    public let gamingMinutes: Int
    public let distractingMinutes: Int
    public let idleMinutes: Int
    public let unknownMinutes: Int
    public let source: DailyCoverageSourceState?

    public init(
        localDay: String,
        activeTaskMinutes: Int,
        observedTaskMinutes: Int,
        alignedTaskMinutes: Int,
        missingTaskMinutes: Int,
        workMinutes: Int,
        gamingMinutes: Int,
        distractingMinutes: Int,
        idleMinutes: Int,
        unknownMinutes: Int,
        source: DailyCoverageSourceState?
    ) {
        self.localDay = localDay
        self.activeTaskMinutes = max(0, activeTaskMinutes)
        self.observedTaskMinutes = max(0, observedTaskMinutes)
        self.alignedTaskMinutes = max(0, alignedTaskMinutes)
        self.missingTaskMinutes = max(0, missingTaskMinutes)
        self.workMinutes = max(0, workMinutes)
        self.gamingMinutes = max(0, gamingMinutes)
        self.distractingMinutes = max(0, distractingMinutes)
        self.idleMinutes = max(0, idleMinutes)
        self.unknownMinutes = max(0, unknownMinutes)
        self.source = source
    }

    public var coveragePercent: Int? {
        guard activeTaskMinutes > 0 else { return nil }
        return min(100, Int((Double(observedTaskMinutes) / Double(activeTaskMinutes) * 100).rounded()))
    }

    public var observedMinutes: Int {
        workMinutes + gamingMinutes + distractingMinutes + idleMinutes + unknownMinutes
    }

    public var unknownSharePercent: Int {
        guard observedMinutes > 0 else { return 0 }
        return min(100, Int((Double(unknownMinutes) / Double(observedMinutes) * 100).rounded()))
    }

    public var precision: DailyCoveragePrecision {
        guard observedMinutes > 0 else { return .insufficient }
        guard let coveragePercent else { return .approximate }
        if coveragePercent >= 90 && unknownSharePercent < 15 && source?.isHealthy == true {
            return .exactWithinTrackedWindow
        }
        return .approximate
    }

    public var isLowCoverage: Bool {
        guard observedMinutes > 0 else { return true }
        if let coveragePercent, coveragePercent < 70 { return true }
        return unknownSharePercent >= 30 || source?.isHealthy != true
    }

    public var idleIsReliable: Bool {
        idleMinutes > 0 && source?.isHealthy == true && !isLowCoverage
    }

    public func displayMinutes(_ minutes: Int) -> String {
        switch precision {
        case .exactWithinTrackedWindow:
            return "\(minutes) min"
        case .approximate:
            let rounded = Int((Double(minutes) / 5).rounded()) * 5
            return "about \(max(0, rounded)) min observed"
        case .insufficient:
            return "not enough coverage"
        }
    }

    public var missingExplanation: String {
        if activeTaskMinutes == 0 {
            return "No active-task window was recorded, so Zoid 666 cannot estimate whole-day missing time. Observed categories remain partial evidence only."
        }
        if missingTaskMinutes == 0 {
            return "No gap was detected inside recorded active-task windows. This does not claim coverage outside those windows."
        }
        return "About \(missingTaskMinutes) active-task minute\(missingTaskMinutes == 1 ? " was" : "s were") not covered by Screenwatch. Missing time is not counted as work, gaming, or distraction."
    }
}
