import Foundation
import ZoidCoachCore

enum CoachingState: String, Equatable, Sendable {
    case observation = "Observation week"
    case gentle = "Gentle coaching"
    case accountability = "Level 2 coaching"
    case paused = "Coaching paused"
    case unavailable = "Coaching status unavailable"
}

enum CoachingPauseEvidence: Equatable, Sendable {
    case indefinite
    case until(Date)
}

struct CoachingRuntimeState: Equatable, Sendable {
    let state: CoachingState
    let pauseEvidence: CoachingPauseEvidence?

    init(state: CoachingState, pauseEvidence: CoachingPauseEvidence? = nil) {
        self.state = state
        self.pauseEvidence = pauseEvidence
    }

    static let unavailable = Self(state: .unavailable)

    static func resolve(
        automationPause: AutomationPause,
        baselineStatus: BaselineObservationStatus,
        coachingLevel: CoachingLevel,
        now: Date
    ) -> Self {
        if automationPause.isActive(at: now) {
            return Self(
                state: .paused,
                pauseEvidence: automationPause.resumesAtUTC.map(CoachingPauseEvidence.until) ?? .indefinite
            )
        }
        if baselineStatus.suppressesBehaviorPrompts {
            return Self(state: .observation)
        }
        switch coachingLevel {
        case .gentle:
            return Self(state: .gentle)
        case .accountability:
            return Self(state: .accountability)
        }
    }
}

struct CoachingStateRefreshGate: Sendable {
    private var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    func shouldInstall(_ candidate: UInt64) -> Bool {
        candidate == generation
    }
}

struct CoachingStatePresentation: Equatable, Sendable {
    let statusLabel: String
    let explanation: String
    let pauseReason: String?
    let recoveryHint: String?

    init(runtimeState: CoachingRuntimeState) {
        switch runtimeState.state {
        case .accountability:
            statusLabel = "COACHING ACTIVE - ACCOUNTABILITY"
            explanation = "Coaching can offer more frequent prompts within your saved limits. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = nil
        case .gentle:
            statusLabel = "COACHING ACTIVE - GENTLE"
            explanation = "Coaching can offer gentle prompts within your saved limits. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = nil
        case .observation:
            statusLabel = "OBSERVATION ONLY"
            explanation = "Zoid 666 is building its baseline without behavior coaching prompts. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = nil
        case .paused:
            statusLabel = "COACHING PAUSED"
            explanation = "Behavior coaching prompts and automated coaching actions are paused. Task tracking and activity observation continue according to their own settings."
            switch runtimeState.pauseEvidence {
            case .indefinite:
                pauseReason = "Paused until you resume coaching."
            case let .until(date):
                pauseReason = "Paused until \(date.formatted(date: .abbreviated, time: .shortened))."
            case nil:
                pauseReason = "The saved pause end is unavailable."
            }
            recoveryHint = "Resume coaching in Settings when you want coaching prompts again."
        case .unavailable:
            statusLabel = "COACHING STATUS UNAVAILABLE"
            explanation = "Coaching availability could not be verified. Task tracking and activity observation have separate status and are not reported as stopped here."
            pauseReason = nil
            recoveryHint = nil
        }
    }

    var accessibilityLabel: String {
        let details = [pauseReason, explanation, recoveryHint].compactMap { $0 }
        return ([statusLabel + "."] + details).joined(separator: " ")
    }
}
