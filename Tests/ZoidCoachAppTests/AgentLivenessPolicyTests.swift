import Testing
@testable import ZoidCoachCore

struct AgentLivenessPolicyTests {
    @Test
    func restartsOnlyAfterProgressExceedsTheStallBudget() {
        let policy = AgentLivenessPolicy(maximumStallDuration: .seconds(180))

        #expect(!policy.requiresRestart(elapsedSinceProgress: .seconds(180)))
        #expect(policy.requiresRestart(elapsedSinceProgress: .seconds(181)))
    }

    @Test
    func enforcesAMinimumStallBudget() {
        let policy = AgentLivenessPolicy(maximumStallDuration: .seconds(1))

        #expect(!policy.requiresRestart(elapsedSinceProgress: .seconds(30)))
        #expect(policy.requiresRestart(elapsedSinceProgress: .seconds(31)))
    }
}
