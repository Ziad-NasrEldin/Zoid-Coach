struct MenuBarVoiceControlsPresentation: Equatable {
    let isExpanded: Bool

    let title = "VOICE CONTROLS"
    let accessibilityLabel = "Voice controls"

    var symbolName: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    var accessibilityValue: String {
        isExpanded ? "Expanded" : "Collapsed"
    }

    var accessibilityHint: String {
        isExpanded ? "Collapse voice controls" : "Expand voice controls"
    }
}
