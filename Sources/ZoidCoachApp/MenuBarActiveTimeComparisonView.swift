import SwiftUI

struct MenuBarActiveTimeComparisonView: View {
    let comparison: MenuBarActiveTimeComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                timingValue(
                    comparison.elapsedText,
                    label: comparison.elapsedAccessibilityText,
                    identifier: "menu-bar.task.elapsed-time"
                )
                timingValue(
                    comparison.alignedText,
                    label: comparison.alignedAccessibilityText,
                    identifier: "menu-bar.task.aligned-time"
                )
            }
            Text(comparison.evidenceExplanation)
                .font(Sumi.body(9))
                .foregroundStyle(Sumi.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(comparison.evidenceExplanation)
                .accessibilityIdentifier("menu-bar.task.alignment-evidence")
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-bar.task.active-time-comparison")
    }

    private func timingValue(_ text: String, label: String, identifier: String) -> some View {
        Text(text)
            .font(Sumi.label(8))
            .sumiLabelTracking()
            .foregroundStyle(Sumi.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }
}
