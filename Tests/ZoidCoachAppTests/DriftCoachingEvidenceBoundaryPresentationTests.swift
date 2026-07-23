import Testing
@testable import ZoidCoachApp

struct DriftCoachingEvidenceBoundaryPresentationTests {
    @Test
    func limitedCoverageExplainsWhyStrongCoachingHoldsAndWhatToDo() {
        let presentation = DriftCoachingEvidenceBoundaryPresentation(
            hasSourceIssue: true,
            unknownMinutes: 20
        )

        #expect(presentation.title == "COACHING HOLDS WHEN EVIDENCE IS LIMITED")
        #expect(presentation.detail == "Zoid 666 does not use stale or missing activity as strong drift evidence. Restore Source Health before trusting today's behavior picture.")
        #expect(presentation.accessibilityValue == "Limited evidence")
    }

    @Test
    func unknownTimeIsExplicitlyExcludedFromStrongCoachingEvidence() {
        let presentation = DriftCoachingEvidenceBoundaryPresentation(
            hasSourceIssue: false,
            unknownMinutes: 12
        )

        #expect(presentation.title == "UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING")
        #expect(presentation.detail == "Unknown time stays out of work, gaming, and distraction. Review it if you know what happened; Zoid 666 does not guess.")
        #expect(presentation.accessibilityValue == "Unknown evidence excluded")
    }

    @Test
    func currentEvidenceStillRefusesToInferIntentFromAnAppName() {
        let presentation = DriftCoachingEvidenceBoundaryPresentation(
            hasSourceIssue: false,
            unknownMinutes: 0
        )

        #expect(presentation.title == "CLASSIFICATION IS NOT INTENT")
        #expect(presentation.detail == "Fresh classifications can support coaching, but an app name alone does not prove why you used it or whether it supported the active task.")
        #expect(presentation.policyDetail == "Strong gaming coaching also requires fresh, sustained, confident gaming and unfinished priority work.")
        #expect(presentation.accessibilityValue == "Current evidence boundary")
    }
}
