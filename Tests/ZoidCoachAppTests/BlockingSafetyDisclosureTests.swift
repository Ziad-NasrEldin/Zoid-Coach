import Testing
@testable import ZoidCoachApp

@Test
func blockingSafetyDisclosureNamesEveryRequiredGateInStableOrder() {
    let disclosure = BlockingSafetyDisclosure()

    #expect(disclosure.statusTitle == "HARD BLOCKING OFF")
    #expect(disclosure.requirements.map(\.id) == [
        .explicitEnablement,
        .reversible,
        .timeBounded,
        .escapeHatch,
    ])
    #expect(disclosure.accessibilitySummary.contains("does not block applications or websites"))
    #expect(disclosure.accessibilitySummary.contains("Explicit enablement"))
    #expect(disclosure.accessibilitySummary.contains("Reversible"))
    #expect(disclosure.accessibilitySummary.contains("Time-bounded"))
    #expect(disclosure.accessibilitySummary.contains("Escape hatch"))
}

@Test
func blockingSafetyContractRejectsEachMissingGate() {
    let disclosure = BlockingSafetyDisclosure()
    let unsafe = BlockingSafetyDisclosure.Candidate(
        isExplicitlyEnabled: false,
        isReversible: false,
        maximumDurationMinutes: nil,
        hasEscapeHatch: false
    )

    #expect(disclosure.unmetRequirements(for: unsafe) == [
        .explicitEnablement,
        .reversible,
        .timeBounded,
        .escapeHatch,
    ])
    #expect(disclosure.unmetRequirements(for: .init(
        isExplicitlyEnabled: true,
        isReversible: true,
        maximumDurationMinutes: 0,
        hasEscapeHatch: true
    )) == [.timeBounded])
}

@Test
func blockingSafetyContractAcceptsOnlyABoundedReversibleEscapableChoice() {
    let disclosure = BlockingSafetyDisclosure()
    let safe = BlockingSafetyDisclosure.Candidate(
        isExplicitlyEnabled: true,
        isReversible: true,
        maximumDurationMinutes: 45,
        hasEscapeHatch: true
    )

    #expect(disclosure.unmetRequirements(for: safe).isEmpty)
}
