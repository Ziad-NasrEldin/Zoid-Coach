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

@Suite("Reachable Today gaming unlock control")
struct TodayPlanGamingUnlockControlStateTests {
    @Test("live plan ownership overrides a stale snapshot and missing live state falls back")
    func livePlanOwnershipWins() {
        let newlyMain = DailyPlanEntry(
            reminderID: "new-main",
            rank: 2,
            isMainObjective: true,
            estimateMinutes: 30
        )
        let formerlyMain = DailyPlanEntry(
            reminderID: "old-main",
            rank: 1,
            isMainObjective: false,
            estimateMinutes: 30
        )

        #expect(TodayPlanMainObjectiveState.resolve(
            snapshotIsMainObjective: false,
            livePlanEntry: newlyMain
        ))
        #expect(!TodayPlanMainObjectiveState.resolve(
            snapshotIsMainObjective: true,
            livePlanEntry: formerlyMain
        ))
        #expect(TodayPlanMainObjectiveState.resolve(
            snapshotIsMainObjective: true,
            livePlanEntry: nil
        ))
    }

    @Test("locked reward labels the main task and requires confirmation before moving")
    func lockedReward() {
        let gaming = gaming(locked: 25)
        let main = TodayPlanGamingUnlockControlState(gaming: gaming, isMainObjective: true)
        let alternative = TodayPlanGamingUnlockControlState(gaming: gaming, isMainObjective: false)

        #expect(main.conditionLabel == "GAMING UNLOCK - COMPLETE THIS TASK FOR 25 MIN")
        #expect(alternative.conditionLabel == nil)
        #expect(alternative.makeMainTitle == "MAKE MAIN + GAMING UNLOCK")
        #expect(alternative.requiresConfirmation)
        #expect(alternative.accessibilityHint.contains("main objective and the one-time gaming reward condition"))
        #expect(alternative.confirmationMessage(taskTitle: "Ship proposal").contains("instead of the current main objective"))
    }

    @Test("unavailable reward preserves ordinary make-main behavior")
    func unavailableReward() {
        let disabled = TodayPlanGamingUnlockControlState(
            gaming: gaming(locked: 25, enabled: false),
            isMainObjective: false
        )
        let earned = TodayPlanGamingUnlockControlState(
            gaming: gaming(locked: 0, earned: 25),
            isMainObjective: false
        )

        #expect(disabled.makeMainTitle == "MAKE MAIN")
        #expect(earned.makeMainTitle == "MAKE MAIN")
        #expect(!disabled.requiresConfirmation)
        #expect(!earned.requiresConfirmation)
        #expect(disabled.conditionLabel == nil)
        #expect(earned.conditionLabel == nil)
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
