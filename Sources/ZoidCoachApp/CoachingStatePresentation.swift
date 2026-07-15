import Foundation

struct CoachingStatePresentation: Equatable, Sendable {
    let statusLabel: String
    let explanation: String
    let pauseReason: String?
    let recoveryHint: String?

    init(state: CoachingState) {
        switch state {
        case .accountability:
            statusLabel = "COACHING ACTIVE"
            explanation = "Coaching can offer prompts and suggestions. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = nil
        case .observation:
            statusLabel = "OBSERVATION ONLY"
            explanation = "Zoid 666 is learning patterns without behavior coaching prompts. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = nil
        case .paused:
            statusLabel = "COACHING PAUSED"
            explanation = "Behavior coaching prompts and automated coaching actions are paused. Task tracking and activity observation continue according to their own settings."
            pauseReason = nil
            recoveryHint = "Resume coaching in Settings when you want coaching prompts again."
        }
    }

    var accessibilityLabel: String {
        let details = [pauseReason, explanation, recoveryHint].compactMap { $0 }
        return ([statusLabel + "."] + details).joined(separator: " ")
    }
}
