#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error { case failure(String) }
private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let hidden: Bool
    let hasToday: Bool
    let hasReviews: Bool
}
private enum WindowSelection: Equatable { case selected(Int), missing, ambiguous }
private struct ReviewsNavigationState {
    let destinationRootVisible: Bool
    let deepEvidenceChildVisible: Bool
}
private struct ScrollAreaTraits {
    let containsDailyReview: Bool
}
private enum ScrollAreaSelection: Equatable { case selected(Int), missing, ambiguous }
private enum ReviewScrollStep: Equatable { case verticalScrollBar(Double), pageAction }
private func selectDailyReviewScrollArea(_ candidates: [ScrollAreaTraits]) -> ScrollAreaSelection {
    let matches = candidates.indices.filter { candidates[$0].containsDailyReview }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
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
private func performReviewScrollStep(
    _ step: ReviewScrollStep,
    setScrollbar: (Double) -> Bool,
    scrollPage: () -> Bool
) -> Bool {
    switch step {
    case let .verticalScrollBar(value): return setScrollbar(value)
    case .pageAction: return scrollPage()
    }
}
private func reviewsNavigationSucceeded(
    beforePress: ReviewsNavigationState,
    pressSucceeded: Bool,
    afterPress: ReviewsNavigationState
) -> Bool {
    beforePress.destinationRootVisible || afterPress.destinationRootVisible
}
private let mainWindowID = "zoid-666.main-window"
private let reviewDestinationID = "reviews.daily"
private let evidenceContainerID = "reviews.evidence-layers"
private let layerIDs = [
    "reviews.evidence-layers.facts",
    "reviews.evidence-layers.context",
    "reviews.evidence-layers.hypothesis",
]
private let privateSentinels = ["qa-zc042001", "private-url", "private-note"]

private func selectMainWindow(_ windows: [WindowTraits]) -> WindowSelection {
    let matches = windows.indices.filter {
        let window = windows[$0]
        return !window.minimized && !window.hidden
            && (window.identifier == mainWindowID || (window.hasToday && window.hasReviews))
    }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let main = WindowTraits(identifier: mainWindowID, minimized: false, hidden: false, hasToday: true, hasReviews: true)
    let content = WindowTraits(identifier: nil, minimized: false, hidden: false, hasToday: true, hasReviews: true)
    let auxiliary = WindowTraits(identifier: "agent", minimized: false, hidden: false, hasToday: false, hasReviews: false)
    let minimized = WindowTraits(identifier: mainWindowID, minimized: true, hidden: false, hasToday: true, hasReviews: true)
    let hidden = WindowTraits(identifier: mainWindowID, minimized: false, hidden: true, hasToday: true, hasReviews: true)
    var scrollbarWrites: [Double] = []
    var unsupportedPageAttempts = 0
    let scrollbarWithoutPageAction = performReviewScrollStep(
        .verticalScrollBar(0.5),
        setScrollbar: { scrollbarWrites.append($0); return true },
        scrollPage: { unsupportedPageAttempts += 1; return false }
    )
    guard selectMainWindow([main, auxiliary]) == .selected(0),
          selectMainWindow([auxiliary, content]) == .selected(1),
          selectMainWindow([main, content]) == .ambiguous,
          selectMainWindow([auxiliary]) == .missing,
          selectMainWindow([minimized]) == .missing,
          selectMainWindow([hidden]) == .missing,
          reviewsNavigationSucceeded(
              beforePress: ReviewsNavigationState(
                  destinationRootVisible: true,
                  deepEvidenceChildVisible: false
              ),
              pressSucceeded: false,
              afterPress: ReviewsNavigationState(
                  destinationRootVisible: true,
                  deepEvidenceChildVisible: false
              )
          ),
          reviewsNavigationSucceeded(
              beforePress: ReviewsNavigationState(
                  destinationRootVisible: false,
                  deepEvidenceChildVisible: false
              ),
              pressSucceeded: true,
              afterPress: ReviewsNavigationState(
                  destinationRootVisible: true,
                  deepEvidenceChildVisible: false
              )
          ),
          !reviewsNavigationSucceeded(
              beforePress: ReviewsNavigationState(
                  destinationRootVisible: false,
                  deepEvidenceChildVisible: false
              ),
              pressSucceeded: true,
              afterPress: ReviewsNavigationState(
                  destinationRootVisible: false,
                  deepEvidenceChildVisible: false
              )
          ),
          !reviewsNavigationSucceeded(
              beforePress: ReviewsNavigationState(
                  destinationRootVisible: false,
                  deepEvidenceChildVisible: true
              ),
              pressSucceeded: false,
              afterPress: ReviewsNavigationState(
                  destinationRootVisible: false,
                  deepEvidenceChildVisible: true
              )
          ),
          selectDailyReviewScrollArea([
              ScrollAreaTraits(containsDailyReview: false),
              ScrollAreaTraits(containsDailyReview: true),
          ]) == .selected(1),
          selectDailyReviewScrollArea([
              ScrollAreaTraits(containsDailyReview: false),
          ]) == .missing,
          selectDailyReviewScrollArea([
              ScrollAreaTraits(containsDailyReview: true),
              ScrollAreaTraits(containsDailyReview: true),
          ]) == .ambiguous,
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
              page: 99,
              maximumPages: 16,
              verticalScrollBarIsWritable: true,
              minimumValue: -1,
              maximumValue: 1
          ) == .verticalScrollBar(1),
          reviewScrollStep(
              page: 0,
              maximumPages: 16,
              verticalScrollBarIsWritable: false,
              minimumValue: 0,
              maximumValue: 1
          ) == .pageAction,
          scrollbarWithoutPageAction,
          scrollbarWrites == [0.5],
          unsupportedPageAttempts == 0,
          Set(layerIDs).count == 3
    else {
        fputs("FAIL: ZC-042-001 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-042-001 AX probe self-test")
    exit(0)
}

guard CommandLine.arguments.count == 5,
      CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase",
      ["positive", "empty", "limited", "window"].contains(CommandLine.arguments[4])
else {
    fputs("usage: qa-zc042001-evidence-layers-ax-probe.swift --self-test | --pid <pid> --phase <positive|empty|limited|window>\n", stderr)
    exit(2)
}

private let phase = CommandLine.arguments[4]
private let application = AXUIElementCreateApplication(pid)
private let maximumNodes = 4_000
private let maximumPages = 16

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}
private func string(_ element: AXUIElement, _ name: CFString) -> String? { attribute(element, name) as? String }
private func identifier(_ element: AXUIElement) -> String? { string(element, kAXIdentifierAttribute as CFString) }
private func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute as CFString) }
private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}
private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
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
private func walk(_ root: AXUIElement, matching: (AXUIElement) -> Bool) throws -> AXUIElement? {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { throw ProbeError.failure("AX traversal exceeded its bounded node limit") }
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
        var navigation = Set<String>()
        _ = try walk(window) { element in
            if role(element) == (kAXButtonRole as String) { navigation.formUnion(labels(element)) }
            return false
        }
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            hidden: bool(window, "AXVisible" as CFString) == false,
            hasToday: navigation.contains("Today"),
            hasReviews: navigation.contains("Reviews")
        )
    }
    switch selectMainWindow(traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}
private func reviewsNavigationState(_ window: AXUIElement) throws -> ReviewsNavigationState {
    ReviewsNavigationState(
        destinationRootVisible: try walk(window, matching: {
            identifier($0) == reviewDestinationID
        }) != nil,
        deepEvidenceChildVisible: try walk(window, matching: {
            identifier($0) == evidenceContainerID
        }) != nil
    )
}
private func pressReviews(_ window: AXUIElement) throws {
    let beforePress = try reviewsNavigationState(window)
    guard let reviews = try walk(window, matching: {
        role($0) == (kAXButtonRole as String) && labels($0).contains("Reviews")
    }) else { throw ProbeError.failure("normal Reviews navigation is unavailable") }

    _ = AXUIElementPerformAction(reviews, "AXScrollToVisible" as CFString)
    let pressSucceeded = AXUIElementPerformAction(reviews, kAXPressAction as CFString) == .success
    Thread.sleep(forTimeInterval: 0.3)
    let afterPress = try reviewsNavigationState(window)
    guard reviewsNavigationSucceeded(
        beforePress: beforePress,
        pressSucceeded: pressSucceeded,
        afterPress: afterPress
    ) else {
        throw ProbeError.failure("could not press Reviews")
    }
}
private func reviewsScrollArea(in window: AXUIElement) throws -> AXUIElement {
    var scrollAreas: [AXUIElement] = []
    _ = try walk(window) {
        if role($0) == (kAXScrollAreaRole as String) { scrollAreas.append($0) }
        return false
    }
    let traits = try scrollAreas.map { scrollArea in
        ScrollAreaTraits(
            containsDailyReview: try walk(
                scrollArea,
                matching: { identifier($0) == reviewDestinationID }
            ) != nil
        )
    }
    switch selectDailyReviewScrollArea(traits) {
    case let .selected(index):
        return scrollAreas[index]
    case .missing:
        throw ProbeError.failure("Daily Review content scroll area is unavailable")
    case .ambiguous:
        throw ProbeError.failure("Daily Review content scroll area is ambiguous")
    }
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
    let step = reviewScrollStep(
        page: page,
        maximumPages: maximumPages,
        verticalScrollBarIsWritable: scrollBarIsWritable.boolValue,
        minimumValue: minimumValue,
        maximumValue: maximumValue
    )
    return performReviewScrollStep(
        step,
        setScrollbar: { value in
            guard let verticalScrollBar else { return false }
            return AXUIElementSetAttributeValue(
                verticalScrollBar,
                kAXValueAttribute as CFString,
                NSNumber(value: value)
            ) == .success
        },
        scrollPage: {
            AXUIElementPerformAction(
                scrollArea,
                "AXScrollDownByPage" as CFString
            ) == .success
        }
    )
}
private func find(_ expected: String, in window: AXUIElement) throws -> AXUIElement {
    let scrollArea = try reviewsScrollArea(in: window)
    for page in 0..<maximumPages {
        if let match = try walk(window, matching: { identifier($0) == expected }) { return match }
        guard scrollReviews(scrollArea, page: page) else { break }
        Thread.sleep(forTimeInterval: 0.15)
    }
    if let match = try walk(window, matching: { identifier($0) == expected }) { return match }
    throw ProbeError.failure("required evidence layer is unavailable after bounded scrolling: \(expected)")
}
private func subtree(_ root: AXUIElement) throws -> (ids: [String], strings: [String]) {
    var ids: [String] = []
    var strings: [String] = []
    _ = try walk(root) {
        if let id = identifier($0) { ids.append(id) }
        strings.append(contentsOf: labels($0))
        return false
    }
    return (ids, strings)
}
private func contains(_ strings: [String], _ fragments: [String]) -> Bool {
    fragments.allSatisfy { fragment in strings.contains(where: { $0.contains(fragment) }) }
}

do {
    let window = try mainWindow()
    if phase == "window" { print("PASS: ZC-042-001 exactly one visible main window"); exit(0) }
    try pressReviews(window)
    let container = try find(evidenceContainerID, in: window)
    let snapshot = try subtree(container)
    let exposedLayers = Set(snapshot.ids.filter { $0.hasPrefix("reviews.evidence-layers.") })
    guard exposedLayers == Set(layerIDs) else { throw ProbeError.failure("exactly three distinct evidence layers were not exposed") }
    guard privateSentinels.allSatisfy({ sentinel in
        snapshot.strings.allSatisfy { !$0.localizedCaseInsensitiveContains(sentinel) }
    }) else { throw ProbeError.failure("private fixture evidence escaped into Accessibility output") }

    let facts = labels(try find(layerIDs[0], in: window))
    let context = labels(try find(layerIDs[1], in: window))
    let hypothesis = labels(try find(layerIDs[2], in: window))
    guard contains(facts, ["OBSERVED FACTS", "corrected local evidence and task records"]),
          contains(context, ["CONTEXT AND LIMITS", "never rewrites an observed fact"]),
          contains(hypothesis, ["POSSIBLE HYPOTHESIS", "never presented as fact"])
    else { throw ProbeError.failure("evidence layer labels or epistemic hints are incomplete") }

    switch phase {
    case "positive":
        guard contains(facts, ["3 corrected observed minutes", "2 sessions"]),
              contains(context, ["1 observed minute remains Unknown", "personal note supplies user context"]),
              contains(hypothesis, ["Observed work time was the largest covered category", "may indicate"])
        else { throw ProbeError.failure("positive evidence-layer content is incorrect") }
    case "limited":
        guard contains(facts, ["2 corrected observed minutes", "1 session"]),
              contains(context, ["2 observed minutes remain Unknown", "personal note supplies user context"]),
              contains(hypothesis, ["No possible explanation was generated", "insufficient"])
        else { throw ProbeError.failure("limited evidence was promoted beyond its support") }
    case "empty":
        guard contains(facts, ["No covered activity or completed task was recorded"]),
              contains(context, ["Screenwatch contributed no corrected minutes"]),
              contains(hypothesis, ["No possible explanation was generated", "insufficient"])
        else { throw ProbeError.failure("empty evidence-layer content is incorrect") }
    default: break
    }
    print("PASS: ZC-042-001 AX phase \(phase)")
} catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: unexpected ZC-042-001 AX verifier failure\n", stderr)
    exit(1)
}
