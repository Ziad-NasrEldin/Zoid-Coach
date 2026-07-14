import AppKit
import ApplicationServices
import SwiftUI
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Behavior evidence accessibility")
struct BehaviorEvidenceAccessibilityTests {
    @Test("hosted work-category cards remain six separate navigation elements")
    @MainActor
    func hostedWorkCategoriesExposeStableOrderedElements() async throws {
        let minutes = [12, 11, 10, 9, 8, 7]
        let categories = zip(WorkCategory.allCases, minutes).map {
            BehaviorEvidenceWorkCategory(category: $0.0, minutes: $0.1)
        }
        let host = NSHostingView(rootView: BehaviorEvidenceWorkCategoryLedger(
            categories: categories,
            detail: "Only privacy-safe category totals are shown."
        ))
        host.frame = NSRect(x: 0, y: 0, width: 616, height: 280)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let prefix = "today.behavior-evidence.work-category."
        let records = accessibilityDescendants(of: application).compactMap { element -> AccessibilityRecord? in
            guard let identifier = accessibilityText(element, kAXIdentifierAttribute as CFString),
                  identifier.hasPrefix(prefix) else { return nil }
            return AccessibilityRecord(
                identifier: identifier,
                label: accessibilityText(element, kAXDescriptionAttribute as CFString)
                    ?? accessibilityText(element, kAXTitleAttribute as CFString)
                    ?? accessibilityText(element, kAXValueAttribute as CFString)
                    ?? "",
                hint: accessibilityText(element, kAXHelpAttribute as CFString) ?? ""
            )
        }

        #expect(records.map(\.identifier) == WorkCategory.allCases.map { prefix + $0.rawValue })
        #expect(records.map(\.label) == [
            "Deep work, 12 minutes",
            "Creative work, 11 minutes",
            "Research, 10 minutes",
            "Communication, 9 minutes",
            "Administration, 8 minutes",
            "Uncategorized work, 7 minutes",
        ])
        #expect(records.map(\.hint) == WorkCategory.allCases.map(\.explanation))
        #expect(records.allSatisfy { !$0.label.contains("Xcode") && !$0.hint.contains("example.com") })

        withExtendedLifetime(host) {}
    }
}

private struct AccessibilityRecord: Equatable {
    let identifier: String
    let label: String
    let hint: String
}

private func accessibilityValue(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
}

private func accessibilityText(_ element: AXUIElement, _ attribute: CFString) -> String? {
    accessibilityValue(element, attribute) as? String
}

private func accessibilityDescendants(of root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    while !queue.isEmpty {
        let element = queue.removeFirst()
        result.append(element)
        if let children = accessibilityValue(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return result
}
