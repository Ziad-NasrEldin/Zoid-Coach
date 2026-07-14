import Testing
@testable import ZoidCoachApp

@Test
func planSelectionEvidenceNeverExposesUnclassifiedStoredReason() {
    let privateReason = "Client acquisition details for an unannounced project"
    let presentation = PlanSelectionEvidencePresentation.make(
        storedSelectionReason: privateReason
    )

    #expect(presentation.heading == "EVIDENCE")
    #expect(presentation.detail == "Included in today's plan. Private ranking details are not displayed.")
    #expect(!presentation.detail.contains(privateReason))
}

@Test
func planSelectionEvidenceUsesTheSameApprovedCopyWithoutAStoredReason() {
    let presentation = PlanSelectionEvidencePresentation.make(storedSelectionReason: nil)

    #expect(presentation.heading == "EVIDENCE")
    #expect(presentation.detail == "Included in today's plan. Private ranking details are not displayed.")
}
