import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Plan gaming unlock condition")
struct GamingUnlockConditionPresentationTests {
    @Test("locked reward names the main objective and requires a deliberate move")
    func configurableReward() {
        let presentation = GamingUnlockConditionPresentation(gaming: gaming(locked: 25))

        #expect(presentation.isConfigurable)
        #expect(presentation.conditionLabel(isMainObjective: true) == "GAMING UNLOCK - COMPLETE THIS TASK FOR 25 MIN")
        #expect(presentation.conditionLabel(isMainObjective: false) == nil)
        #expect(presentation.makeMainTitle(isMainObjective: false) == "MAKE MAIN + GAMING UNLOCK")
        #expect(presentation.makeMainTitle(isMainObjective: true) == "MAIN + GAMING UNLOCK")
        #expect(presentation.confirmationMessage(taskTitle: "Ship proposal").contains("instead of the current main objective"))
    }

    @Test("disabled budget and applied reward do not imply a movable unlock")
    func unavailableReward() {
        let disabled = GamingUnlockConditionPresentation(gaming: gaming(locked: 25, enabled: false))
        let applied = GamingUnlockConditionPresentation(gaming: gaming(locked: 0, earned: 25))

        #expect(!disabled.isConfigurable)
        #expect(!applied.isConfigurable)
        #expect(disabled.conditionLabel(isMainObjective: true) == nil)
        #expect(applied.makeMainTitle(isMainObjective: false) == "ADJUST: MAKE MAIN")
    }

    private func gaming(locked: Int, earned: Int = 0, enabled: Bool = true) -> GamingStatus {
        GamingStatus(
            budgetMinutes: 60,
            earnedMinutes: earned,
            usedMinutes: 0,
            unlockedRemainingMinutes: 60 + earned,
            lockedMinutes: locked,
            nextUnlockReason: locked > 0 ? "Complete the main objective" : "Reward applied",
            confidenceIsLimited: false,
            budgetEnabled: enabled
        )
    }
}
