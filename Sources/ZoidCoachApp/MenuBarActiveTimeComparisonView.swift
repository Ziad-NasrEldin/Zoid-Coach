import AppKit
import SwiftUI

struct MenuBarActiveTimeComparisonView: View {
    let comparison: MenuBarActiveTimeComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .accessibilityHidden(true)
            .overlay {
                MenuBarActiveTimeAccessibilityBridge(comparison: comparison)
            }
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

private struct MenuBarActiveTimeAccessibilityBridge: NSViewRepresentable {
    let comparison: MenuBarActiveTimeComparison

    func makeNSView(context: Context) -> MenuBarActiveTimeAccessibilityView {
        MenuBarActiveTimeAccessibilityView(comparison: comparison)
    }

    func updateNSView(_ nsView: MenuBarActiveTimeAccessibilityView, context: Context) {
        nsView.update(comparison: comparison)
    }
}

private final class MenuBarActiveTimeAccessibilityView: NSView {
    private var comparison: MenuBarActiveTimeComparison
    private var accessibilityEntries: [NSAccessibilityElement] = []

    init(comparison: MenuBarActiveTimeComparison) {
        self.comparison = comparison
        super.init(frame: .zero)
        setAccessibilityElement(false)
        rebuildAccessibilityEntries()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(comparison: MenuBarActiveTimeComparison) {
        guard self.comparison != comparison else { return }
        self.comparison = comparison
        rebuildAccessibilityEntries()
    }

    override func layout() {
        super.layout()
        updateAccessibilityFrames()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityChildren() -> [Any]? {
        accessibilityEntries
    }

    private func rebuildAccessibilityEntries() {
        accessibilityEntries = [
            makeEntry(
                label: comparison.elapsedAccessibilityText,
                help: "The active task timer, whether or not Screenwatch observed aligned work.",
                identifier: "menu-bar.task.elapsed-time"
            ),
            makeEntry(
                label: comparison.alignedAccessibilityText,
                help: comparison.evidenceExplanation,
                identifier: "menu-bar.task.aligned-time"
            ),
            makeEntry(
                label: comparison.evidenceExplanation,
                help: "Explains how observed aligned time differs from elapsed task time.",
                identifier: "menu-bar.task.alignment-evidence"
            ),
        ]
        setAccessibilityChildren(accessibilityEntries)
        updateAccessibilityFrames()
    }

    private func makeEntry(label: String, help: String, identifier: String) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(.staticText)
        element.setAccessibilityLabel(label)
        element.setAccessibilityHelp(help)
        element.setAccessibilityIdentifier(identifier)
        return element
    }

    private func updateAccessibilityFrames() {
        guard !accessibilityEntries.isEmpty else { return }
        let rowHeight = bounds.height / CGFloat(accessibilityEntries.count)
        for (index, element) in accessibilityEntries.enumerated() {
            element.setAccessibilityFrameInParentSpace(NSRect(
                x: 0,
                y: bounds.height - CGFloat(index + 1) * rowHeight,
                width: bounds.width,
                height: rowHeight
            ))
        }
    }
}
