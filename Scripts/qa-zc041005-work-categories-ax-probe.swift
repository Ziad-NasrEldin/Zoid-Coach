#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private struct ExpectedCategory {
    let id: String
    let label: String
    let minutes: Int
}

private struct WindowTraits {
    let identifier: String?
    let isMinimized: Bool
    let isExplicitlyHidden: Bool
    let hasTodayNavigation: Bool
    let hasReviewsNavigation: Bool
}

private enum MainWindowSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private enum ReviewsDestinationSelection: Equatable {
    case unique
    case missing
    case ambiguous
}

private struct ReviewsNavigationState {
    let destination: ReviewsDestinationSelection
    let deepEvidenceChildVisible: Bool
}

private func reviewsNavigationSucceeded(
    beforePress: ReviewsNavigationState,
    pressSucceeded _: Bool,
    afterPress: ReviewsNavigationState
) -> Bool {
    guard beforePress.destination != .ambiguous,
          afterPress.destination != .ambiguous
    else { return false }
    return beforePress.destination == .unique || afterPress.destination == .unique
}

private enum ReviewScrollStep: Equatable {
    case verticalScrollBar(Double)
    case pageAction
}

private func reviewScrollStep(
    page: Int,
    maximumPages: Int,
    verticalScrollBarIsWritable: Bool,
    minimumValue: Double,
    maximumValue: Double
) -> ReviewScrollStep {
    guard verticalScrollBarIsWritable,
          maximumPages > 0,
          maximumValue > minimumValue
    else { return .pageAction }
    let boundedPage = min(max(page + 1, 1), maximumPages)
    let fraction = Double(boundedPage) / Double(maximumPages)
    return .verticalScrollBar(minimumValue + ((maximumValue - minimumValue) * fraction))
}

private let mainWindowIdentifier = "zoid-666.main-window"

private func selectMainWindow(from windows: [WindowTraits]) -> MainWindowSelection {
    let matches = windows.indices.filter { index in
        let window = windows[index]
        guard !window.isMinimized, !window.isExplicitlyHidden else { return false }
        return window.identifier == mainWindowIdentifier
            || (window.hasTodayNavigation && window.hasReviewsNavigation)
    }
    switch matches.count {
    case 1: return .selected(matches[0])
    case 0: return .missing
    default: return .ambiguous
    }
}

private let expectedCategories = [
    ExpectedCategory(id: "deep_work", label: "Deep work", minutes: 2),
    ExpectedCategory(id: "creative_work", label: "Creative work", minutes: 3),
    ExpectedCategory(id: "research", label: "Research", minutes: 4),
    ExpectedCategory(id: "communication", label: "Communication", minutes: 5),
    ExpectedCategory(id: "administration", label: "Administration", minutes: 6),
    ExpectedCategory(id: "uncategorized", label: "Uncategorized work", minutes: 8),
]
private let privateSentinels = [
    "qa-zc041005", "private-url", "Xcode", "Figma", "Zotero", "Slack", "Calendar", "Safari", "Steam",
]

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
    let main = WindowTraits(
        identifier: mainWindowIdentifier,
        isMinimized: false,
        isExplicitlyHidden: false,
        hasTodayNavigation: true,
        hasReviewsNavigation: true
    )
    let auxiliary = WindowTraits(
        identifier: "agent-lifecycle",
        isMinimized: false,
        isExplicitlyHidden: false,
        hasTodayNavigation: false,
        hasReviewsNavigation: false
    )
    let contentIdentifiedMain = WindowTraits(
        identifier: nil,
        isMinimized: false,
        isExplicitlyHidden: false,
        hasTodayNavigation: true,
        hasReviewsNavigation: true
    )
    let minimizedMain = WindowTraits(
        identifier: mainWindowIdentifier,
        isMinimized: true,
        isExplicitlyHidden: false,
        hasTodayNavigation: true,
        hasReviewsNavigation: true
    )
    let hiddenMain = WindowTraits(
        identifier: mainWindowIdentifier,
        isMinimized: false,
        isExplicitlyHidden: true,
        hasTodayNavigation: true,
        hasReviewsNavigation: true
    )
    let selectedReviews = ReviewsNavigationState(
        destination: .unique,
        deepEvidenceChildVisible: false
    )
    let missingReviews = ReviewsNavigationState(
        destination: .missing,
        deepEvidenceChildVisible: false
    )
    let deepChildOnly = ReviewsNavigationState(
        destination: .missing,
        deepEvidenceChildVisible: true
    )
    let ambiguousReviews = ReviewsNavigationState(
        destination: .ambiguous,
        deepEvidenceChildVisible: false
    )
    guard expectedCategories.count == 6,
          expectedCategories.reduce(0, { $0 + $1.minutes }) == 28,
          privateSentinels.contains(where: { "qa-zc041005-private-deep".localizedCaseInsensitiveContains($0) }),
          !privateSentinels.contains(where: { "Deep work, 2 minutes".localizedCaseInsensitiveContains($0) }),
          selectMainWindow(from: [main, auxiliary]) == .selected(0),
          selectMainWindow(from: [auxiliary, contentIdentifiedMain]) == .selected(1),
          selectMainWindow(from: [main, minimizedMain]) == .selected(0),
          selectMainWindow(from: [main, main]) == .ambiguous,
          selectMainWindow(from: [main, contentIdentifiedMain]) == .ambiguous,
          selectMainWindow(from: [auxiliary]) == .missing,
          selectMainWindow(from: [minimizedMain]) == .missing,
          selectMainWindow(from: [hiddenMain]) == .missing,
          reviewsNavigationSucceeded(
              beforePress: selectedReviews,
              pressSucceeded: false,
              afterPress: selectedReviews
          ),
          reviewsNavigationSucceeded(
              beforePress: missingReviews,
              pressSucceeded: true,
              afterPress: selectedReviews
          ),
          !reviewsNavigationSucceeded(
              beforePress: missingReviews,
              pressSucceeded: true,
              afterPress: missingReviews
          ),
          !reviewsNavigationSucceeded(
              beforePress: deepChildOnly,
              pressSucceeded: false,
              afterPress: deepChildOnly
          ),
          !reviewsNavigationSucceeded(
              beforePress: ambiguousReviews,
              pressSucceeded: true,
              afterPress: selectedReviews
          ),
          !reviewsNavigationSucceeded(
              beforePress: missingReviews,
              pressSucceeded: true,
              afterPress: ambiguousReviews
          ),
          reviewScrollStep(
              page: 0,
              maximumPages: 16,
              verticalScrollBarIsWritable: true,
              minimumValue: 0,
              maximumValue: 1
          ) == .verticalScrollBar(0.0625),
          reviewScrollStep(
              page: 15,
              maximumPages: 16,
              verticalScrollBarIsWritable: true,
              minimumValue: 0,
              maximumValue: 1
          ) == .verticalScrollBar(1),
          reviewScrollStep(
              page: 0,
              maximumPages: 16,
              verticalScrollBarIsWritable: false,
              minimumValue: 0,
              maximumValue: 1
          ) == .pageAction
    else {
        fputs("FAIL: ZC-041-005 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-041-005 AX probe self-test")
    exit(0)
}

private let arguments = CommandLine.arguments
guard arguments.count == 5,
      arguments[1] == "--pid",
      let pid = Int32(arguments[2]),
      arguments[3] == "--phase",
      ["categories", "empty", "window"].contains(arguments[4])
else {
    fputs("usage: qa-zc041005-work-categories-ax-probe.swift --self-test | --pid <pid> --phase <categories|empty|window>\n", stderr)
    exit(2)
}

private let phase = arguments[4]
private let application = AXUIElementCreateApplication(pid)
private let maximumNodes = 4_000
private let maximumScrollPages = 16

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute as CFString)
}

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func number(_ element: AXUIElement, _ name: CFString) -> Double? {
    (attribute(element, name) as? NSNumber)?.doubleValue
}

private func element(_ element: AXUIElement, _ name: CFString) -> AXUIElement? {
    guard let value = attribute(element, name),
          CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func walk(
    root: AXUIElement,
    matching: (AXUIElement) -> Bool
) throws -> AXUIElement? {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw ProbeError.failure("AX traversal exceeded \(maximumNodes) nodes")
        }
        if matching(element) { return element }
        queue.append(contentsOf: children(element))
    }
    return nil
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw ProbeError.failure("the supplied process is not running") }
    let windows = ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter { role($0) == (kAXWindowRole as String) }
    let traits = try windows.map { window in
        var navigationLabels = Set<String>()
        _ = try walk(root: window) { element in
            guard role(element) == (kAXButtonRole as String) else { return false }
            navigationLabels.formUnion(labels(element))
            return false
        }
        return WindowTraits(
            identifier: identifier(window),
            isMinimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            isExplicitlyHidden: bool(window, "AXVisible" as CFString) == false,
            hasTodayNavigation: navigationLabels.contains("Today"),
            hasReviewsNavigation: navigationLabels.contains("Reviews")
        )
    }
    switch selectMainWindow(from: traits) {
    case let .selected(index):
        return windows[index]
    case .missing:
        throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous:
        throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}

private func reviewsNavigationState(in window: AXUIElement) throws -> ReviewsNavigationState {
    var destinationCount = 0
    var deepEvidenceChildVisible = false
    _ = try walk(root: window) { element in
        switch identifier(element) {
        case "reviews.daily": destinationCount += 1
        case "reviews.work-categories": deepEvidenceChildVisible = true
        default: break
        }
        return false
    }
    let destination: ReviewsDestinationSelection
    switch destinationCount {
    case 1: destination = .unique
    case 0: destination = .missing
    default: destination = .ambiguous
    }
    return ReviewsNavigationState(
        destination: destination,
        deepEvidenceChildVisible: deepEvidenceChildVisible
    )
}

private func navigateToReviews(window: AXUIElement) throws {
    var reviewItems: [AXUIElement] = []
    _ = try walk(root: window) { element in
        if role(element) == (kAXButtonRole as String), labels(element).contains("Reviews") {
            reviewItems.append(element)
        }
        return false
    }
    guard reviewItems.count == 1, let reviews = reviewItems.first else {
        if try walk(root: window, matching: { identifier($0) == "onboarding.root" }) != nil {
            throw ProbeError.failure("onboarding is visible; establish the supported QA ready state")
        }
        throw ProbeError.failure(
            reviewItems.isEmpty
                ? "normal Reviews navigation is unavailable"
                : "normal Reviews navigation is ambiguous"
        )
    }
    let beforePress = try reviewsNavigationState(in: window)
    _ = AXUIElementPerformAction(reviews, "AXScrollToVisible" as CFString)
    let pressSucceeded = AXUIElementPerformAction(reviews, kAXPressAction as CFString) == .success
    Thread.sleep(forTimeInterval: 0.3)
    let afterPress = try reviewsNavigationState(in: window)
    guard reviewsNavigationSucceeded(
        beforePress: beforePress,
        pressSucceeded: pressSucceeded,
        afterPress: afterPress
    ) else {
        throw ProbeError.failure("could not navigate to the unique Daily Review destination")
    }
}

private func findIdentifierByScrolling(
    _ expected: String,
    in window: AXUIElement
) throws -> AXUIElement {
    for page in 0...maximumScrollPages {
        if let element = try walk(root: window, matching: { identifier($0) == expected }) {
            _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
            return element
        }
        guard page < maximumScrollPages else { break }
        let scrollArea = try reviewsScrollArea(in: window)
        guard scrollReviews(scrollArea, page: page) else {
            throw ProbeError.failure("could not scroll Daily Review toward \(expected)")
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    throw ProbeError.failure("required Daily Review target is unavailable after bounded scrolling: \(expected)")
}

private func reviewsScrollArea(in window: AXUIElement) throws -> AXUIElement {
    var scrollAreas: [AXUIElement] = []
    _ = try walk(root: window) { candidate in
        if role(candidate) == (kAXScrollAreaRole as String) { scrollAreas.append(candidate) }
        return false
    }
    let matches = try scrollAreas.filter { scrollArea in
        try walk(root: scrollArea, matching: { identifier($0) == "reviews.daily" }) != nil
    }
    guard matches.count == 1, let match = matches.first else {
        throw ProbeError.failure(
            matches.isEmpty
                ? "Daily Review content scroll area is unavailable"
                : "Daily Review content scroll area is ambiguous"
        )
    }
    return match
}

private func scrollReviews(_ scrollArea: AXUIElement, page: Int) -> Bool {
    let verticalScrollBar = element(scrollArea, kAXVerticalScrollBarAttribute as CFString)
    var scrollBarIsWritable = DarwinBoolean(false)
    if let verticalScrollBar {
        _ = AXUIElementIsAttributeSettable(
            verticalScrollBar,
            kAXValueAttribute as CFString,
            &scrollBarIsWritable
        )
    }
    let minimumValue = verticalScrollBar.flatMap {
        number($0, kAXMinValueAttribute as CFString)
    } ?? 0
    let maximumValue = verticalScrollBar.flatMap {
        number($0, kAXMaxValueAttribute as CFString)
    } ?? 1

    switch reviewScrollStep(
        page: page,
        maximumPages: maximumScrollPages,
        verticalScrollBarIsWritable: scrollBarIsWritable.boolValue,
        minimumValue: minimumValue,
        maximumValue: maximumValue
    ) {
    case let .verticalScrollBar(value):
        guard let verticalScrollBar else { return false }
        return AXUIElementSetAttributeValue(
            verticalScrollBar,
            kAXValueAttribute as CFString,
            NSNumber(value: value)
        ) == .success
    case .pageAction:
        return AXUIElementPerformAction(
            scrollArea,
            "AXScrollDownByPage" as CFString
        ) == .success
    }
}

private func subtreeSnapshot(_ root: AXUIElement) throws -> (identifiers: [String], strings: [String]) {
    var identifiers: [String] = []
    var strings: [String] = []
    _ = try walk(root: root) { element in
        if let id = identifier(element) { identifiers.append(id) }
        strings.append(contentsOf: labels(element))
        return false
    }
    return (identifiers, strings)
}

private func assertPrivacy(_ strings: [String]) throws {
    guard strings.allSatisfy({ value in
        privateSentinels.allSatisfy { !value.localizedCaseInsensitiveContains($0) }
    }) else {
        throw ProbeError.failure("private application or fixture evidence escaped into the category ledger")
    }
}

do {
    let window = try mainWindow()
    if phase == "window" {
        print("PASS: ZC-041-005 exactly one visible main window")
        exit(0)
    }
    try navigateToReviews(window: window)
    let ledger = try findIdentifierByScrolling("reviews.work-categories", in: window)
    let snapshot = try subtreeSnapshot(ledger)
    try assertPrivacy(snapshot.strings)

    if phase == "empty" {
        _ = try findIdentifierByScrolling("reviews.work-categories.empty", in: window)
        guard expectedCategories.allSatisfy({ category in
            !snapshot.identifiers.contains("reviews.work-category.\(category.id)")
        }) else {
            throw ProbeError.failure("category rows were exposed for a non-work-only review day")
        }
    } else {
        let detail = try findIdentifierByScrolling("reviews.work-categories.detail", in: window)
        guard labels(detail).contains(where: {
            $0.contains("chosen left session supplies that classification")
                && $0.contains("8 work minutes remain Uncategorized")
        }) else {
            throw ProbeError.failure("category authority or Uncategorized explanation is unavailable")
        }
        var rowHashes = Set<CFHashCode>()
        for category in expectedCategories {
            let rowID = "reviews.work-category.\(category.id)"
            let row = try findIdentifierByScrolling(rowID, in: window)
            let expectedLabel = "\(category.label), \(category.minutes) minute\(category.minutes == 1 ? "" : "s")"
            guard labels(row).contains(expectedLabel) else {
                throw ProbeError.failure("category total mismatch for \(category.id)")
            }
            rowHashes.insert(CFHash(row))
        }
        guard rowHashes.count == 6,
              !snapshot.identifiers.contains("reviews.work-categories.empty") else {
            throw ProbeError.failure("six distinct category rows were not exposed")
        }
    }

    print("PASS: ZC-041-005 AX phase \(phase)")
} catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: unexpected AX verifier failure\n", stderr)
    exit(1)
}
