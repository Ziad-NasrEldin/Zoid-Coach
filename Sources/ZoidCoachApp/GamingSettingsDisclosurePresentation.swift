struct GamingSettingsDisclosurePresentation: Equatable {
    let isExpanded: Bool

    let title = "ADVANCED COACHING LIMITS"
    let detail = "Work-hours maximum, prompt timing, and grace periods"

    var symbolName: String {
        isExpanded ? "chevron.down" : "chevron.right"
    }

    var accessibilityValue: String {
        isExpanded ? "Expanded" : "Collapsed"
    }

    var accessibilityHint: String {
        isExpanded
            ? "Hide advanced gaming coaching limits"
            : "Show advanced gaming coaching limits"
    }
}
