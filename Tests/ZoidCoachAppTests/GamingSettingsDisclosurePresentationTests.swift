import Testing
@testable import ZoidCoachApp

struct GamingSettingsDisclosurePresentationTests {
    @Test
    func collapsedStateNamesTheHiddenLimitsWithoutCompetingWithTheAllowance() {
        let presentation = GamingSettingsDisclosurePresentation(isExpanded: false)

        #expect(presentation.title == "ADVANCED COACHING LIMITS")
        #expect(presentation.detail == "Work-hours maximum, prompt timing, and grace periods")
        #expect(presentation.symbolName == "chevron.right")
        #expect(presentation.accessibilityValue == "Collapsed")
        #expect(presentation.accessibilityHint == "Show advanced gaming coaching limits")
    }

    @Test
    func expandedStateMakesTheReturnActionExplicit() {
        let presentation = GamingSettingsDisclosurePresentation(isExpanded: true)

        #expect(presentation.symbolName == "chevron.down")
        #expect(presentation.accessibilityValue == "Expanded")
        #expect(presentation.accessibilityHint == "Hide advanced gaming coaching limits")
    }
}
