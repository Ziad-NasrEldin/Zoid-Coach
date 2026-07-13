import ZoidCoachCore

struct GamingUnlockConditionPresentation: Equatable, Sendable {
    let lockedRewardMinutes: Int

    init(gaming: GamingStatus?) {
        lockedRewardMinutes = gaming?.budgetEnabled == true ? gaming?.lockedMinutes ?? 0 : 0
    }

    var isConfigurable: Bool { lockedRewardMinutes > 0 }

    func conditionLabel(isMainObjective: Bool) -> String? {
        guard isConfigurable, isMainObjective else { return nil }
        return "GAMING UNLOCK - COMPLETE THIS TASK FOR \(lockedRewardMinutes) MIN"
    }

    func makeMainTitle(isMainObjective: Bool) -> String {
        guard !isMainObjective else { return "MAIN + GAMING UNLOCK" }
        return isConfigurable ? "MAKE MAIN + GAMING UNLOCK" : "ADJUST: MAKE MAIN"
    }

    func confirmationMessage(taskTitle: String) -> String {
        "\(taskTitle) will become today's main objective. Completing it will unlock the one-time \(lockedRewardMinutes)-minute gaming reward instead of the current main objective."
    }
}
