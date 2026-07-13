import Testing
@testable import ZoidCoachApp

@Test
func everyUnhealthySourceExplainsImpactAndKeepsARepairAction() {
    for sourceID in SourceID.allCases {
        let source = health(sourceID, state: .attention)
        let guidance = SourceRepairGuidance(source: source)

        #expect(guidance.impact?.hasPrefix("Impact:") == true)
        #expect(guidance.actionHint.contains(source.actionTitle))
        #expect(guidance.canAct)
    }
}

@Test
func guidanceNamesTheSafeFallbackForEachSource() throws {
    let reminders = SourceRepairGuidance(source: health(.reminders, state: .notConnected))
    let notifications = SourceRepairGuidance(source: health(.notifications, state: .attention))
    let calendar = SourceRepairGuidance(source: health(.calendar, state: .unavailable))
    let screenwatch = SourceRepairGuidance(source: health(.screenwatch, state: .attention))
    let agent = SourceRepairGuidance(source: health(.agent, state: .notConnected))

    #expect(try #require(reminders.impact).contains("Local plans, estimates, sessions, and history remain usable"))
    #expect(try #require(notifications.impact).contains("remains available in Today"))
    #expect(try #require(calendar.impact).contains("configured work windows"))
    #expect(try #require(screenwatch.impact).contains("Manual task tracking and planning continue"))
    #expect(try #require(agent.impact).contains("Existing local data remains available"))
}

@Test
func healthySourceHidesImpactAndCheckingSourcePreventsDuplicateAction() {
    let healthy = SourceRepairGuidance(source: health(.reminders, state: .healthy))
    let checking = SourceRepairGuidance(source: health(.reminders, state: .checking))

    #expect(healthy.impact == nil)
    #expect(healthy.canAct)
    #expect(checking.impact != nil)
    #expect(!checking.canAct)
}

private func health(_ id: SourceID, state: HealthState) -> SourceHealth {
    SourceHealth(
        id: id,
        title: id.rawValue,
        eyebrow: "Source",
        state: state,
        detail: "Current state",
        evidence: "Current evidence",
        actionTitle: "Repair"
    )
}
