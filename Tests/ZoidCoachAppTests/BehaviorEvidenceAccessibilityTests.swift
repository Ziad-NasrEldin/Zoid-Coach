import AppKit
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

        let prefix = "today.behavior-evidence.work-category."
        let records = accessibilityDescendants(of: host).compactMap { element -> AccessibilityRecord? in
            guard let identifier = accessibilityIdentifier(element),
                  identifier.hasPrefix(prefix) else { return nil }
            return AccessibilityRecord(
                identifier: identifier,
                label: accessibilityLabel(element) ?? "",
                hint: accessibilityHelp(element) ?? ""
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

    @Test("hosted uncertain work rows expose privacy-safe stable elements")
    @MainActor
    func hostedWorkUncertaintiesExposeStablePrivacySafeElements() async throws {
        let uncertainties = [
            BehaviorEvidenceWorkUncertainty(application: "YouTube", observedSeconds: 600),
            BehaviorEvidenceWorkUncertainty(application: "Safari", observedSeconds: 59),
        ]
        let host = NSHostingView(rootView: BehaviorEvidenceWorkUncertaintyLedger(
            uncertainties: uncertainties
        ))
        host.frame = NSRect(x: 0, y: 0, width: 616, height: 260)

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

        let prefix = "today.behavior-evidence.work-uncertainty."
        let records = accessibilityDescendants(of: host).compactMap { element -> AccessibilityRecord? in
            guard let identifier = accessibilityIdentifier(element),
                  identifier.hasPrefix(prefix) else { return nil }
            return AccessibilityRecord(
                identifier: identifier,
                label: accessibilityLabel(element) ?? "",
                hint: accessibilityHelp(element) ?? ""
            )
        }

        #expect(records.map(\.identifier) == uncertainties.map(\.accessibilityIdentifier))
        #expect(records.map(\.label) == uncertainties.map(\.accessibilityLabel))
        #expect(records.map(\.hint) == uncertainties.map(\.explanation))
        #expect(records.allSatisfy {
            !$0.label.contains("Swift concurrency")
                && !$0.hint.contains("youtube.com/watch")
        })

        withExtendedLifetime(host) {}
    }
}

private struct AccessibilityRecord: Equatable {
    let identifier: String
    let label: String
    let hint: String
}

@MainActor
private func accessibilityIdentifier(_ element: Any) -> String? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityIdentifier() }
    if let element = element as? NSView { return element.accessibilityIdentifier() }
    return nil
}

@MainActor
private func accessibilityLabel(_ element: Any) -> String? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityLabel() }
    if let element = element as? NSView { return element.accessibilityLabel() }
    return nil
}

@MainActor
private func accessibilityHelp(_ element: Any) -> String? {
    if let element = element as? NSAccessibilityElement { return element.accessibilityHelp() }
    if let element = element as? NSView { return element.accessibilityHelp() }
    return nil
}

@MainActor
private func accessibilityDescendants(of root: Any) -> [Any] {
    var result: [Any] = []
    var queue: [Any] = [root]
    var visited: Set<ObjectIdentifier> = []
    while !queue.isEmpty {
        let element = queue.removeFirst()
        if let object = element as? NSObject {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
        }
        result.append(element)
        if let element = element as? NSAccessibilityElement {
            queue.append(contentsOf: element.accessibilityChildren() ?? [])
        } else if let element = element as? NSView {
            queue.append(contentsOf: element.accessibilityChildren() ?? [])
            queue.append(contentsOf: element.subviews)
        }
    }
    return result
}
