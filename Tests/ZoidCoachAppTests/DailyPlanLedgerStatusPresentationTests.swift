import Testing
@testable import ZoidCoachApp

@Suite("Daily plan ledger status")
struct DailyPlanLedgerStatusPresentationTests {
    @Test("loading is presented as unavailable data rather than a zero task plan")
    func loadingIsNotPresentedAsZero() {
        let presentation = DailyPlanLedgerStatusPresentation(
            isLoading: true,
            proposedCount: 0
        )

        #expect(presentation.value == "PLAN STATUS UNKNOWN")
        #expect(presentation.explanation == "Zoid has not finished reading today's local plan. This is not a confirmed zero-task plan. Refresh Today if this message does not clear.")
        #expect(presentation.accessibilityLabel == "Plan status unknown. Today's local plan has not finished loading. This is not a confirmed zero-task plan.")
    }

    @Test("a completed empty load explicitly confirms zero proposed tasks")
    func loadedEmptyPlanConfirmsZero() {
        let presentation = DailyPlanLedgerStatusPresentation(
            isLoading: false,
            proposedCount: 0
        )

        #expect(presentation.value == "0 / 3 PROPOSED")
        #expect(presentation.explanation == "Plan data finished loading. There are currently zero proposed tasks.")
        #expect(presentation.accessibilityLabel == "Plan loaded. Zero of three tasks are proposed.")
    }

    @Test("a loaded plan reports its real proposed count without an absence warning")
    func loadedPlanReportsCount() {
        let presentation = DailyPlanLedgerStatusPresentation(
            isLoading: false,
            proposedCount: 2
        )

        #expect(presentation.value == "2 / 3 PROPOSED")
        #expect(presentation.explanation == nil)
        #expect(presentation.accessibilityLabel == "Plan loaded. Two of three tasks are proposed.")
    }
}
