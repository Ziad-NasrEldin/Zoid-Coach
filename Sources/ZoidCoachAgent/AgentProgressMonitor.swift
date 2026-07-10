import Foundation
import ZoidCoachCore

actor AgentProgressMonitor {
    private let clock = ContinuousClock()
    private var lastProgress: ContinuousClock.Instant

    init() {
        lastProgress = clock.now
    }

    func markProgress() {
        lastProgress = clock.now
    }

    func requiresRestart(policy: AgentLivenessPolicy) -> Bool {
        policy.requiresRestart(elapsedSinceProgress: lastProgress.duration(to: clock.now))
    }
}
