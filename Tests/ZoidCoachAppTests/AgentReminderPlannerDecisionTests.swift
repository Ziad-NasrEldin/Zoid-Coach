import Testing
@testable import ZoidCoachAgent

@Suite("Agent reminder planner source decisions")
struct AgentReminderPlannerDecisionTests {
    @Test("authorized source with no reminders drafts an empty optional invitation")
    func authorizedEmptySourceDraftsZeroSuggestions() {
        #expect(AgentReminderPlanner.planningAvailabilityDecision(
            sourceAccessAvailable: true,
            availableReminderCount: 0,
            eligibleReminderCount: 0
        ) == .draftWithoutSuggestions)
    }

    @Test("authorized source filtered to no eligible reminders drafts no fabricated items")
    func authorizedFilteredEmptySourceDraftsZeroSuggestions() {
        #expect(AgentReminderPlanner.planningAvailabilityDecision(
            sourceAccessAvailable: true,
            availableReminderCount: 3,
            eligibleReminderCount: 0
        ) == .draftWithoutSuggestions)
    }

    @Test("unavailable or denied source remains unavailable when empty")
    func unavailableSourceDoesNotPretendToBeEmpty() {
        #expect(AgentReminderPlanner.planningAvailabilityDecision(
            sourceAccessAvailable: false,
            availableReminderCount: 0,
            eligibleReminderCount: 0
        ) == .unavailable)
    }

    @Test(arguments: [1, 3])
    func nonemptyEligibleCountsContinuePlanning(itemCount: Int) {
        #expect(AgentReminderPlanner.planningAvailabilityDecision(
            sourceAccessAvailable: true,
            availableReminderCount: itemCount,
            eligibleReminderCount: itemCount
        ) == .continueWithEligible(itemCount))
    }
}
