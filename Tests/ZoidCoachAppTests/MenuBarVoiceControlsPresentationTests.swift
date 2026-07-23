import Testing
@testable import ZoidCoachApp

struct MenuBarVoiceControlsPresentationTests {
    @Test
    func collapsedStateUsesForwardDisclosureAndExplainsTheAction() {
        let presentation = MenuBarVoiceControlsPresentation(isExpanded: false)

        #expect(presentation.title == "VOICE CONTROLS")
        #expect(presentation.symbolName == "chevron.right")
        #expect(presentation.accessibilityLabel == "Voice controls")
        #expect(presentation.accessibilityValue == "Collapsed")
        #expect(presentation.accessibilityHint == "Expand voice controls")
    }

    @Test
    func expandedStateUsesDownDisclosureAndExplainsTheAction() {
        let presentation = MenuBarVoiceControlsPresentation(isExpanded: true)

        #expect(presentation.symbolName == "chevron.down")
        #expect(presentation.accessibilityValue == "Expanded")
        #expect(presentation.accessibilityHint == "Collapse voice controls")
    }
}
