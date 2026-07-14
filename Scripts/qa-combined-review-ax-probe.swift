#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

private enum ExitCode: Int32 {
    case success = 0
    case usage = 2
    case attach = 3
    case window = 4
    case navigation = 5
    case dailyReview = 6
    case weeklyReview = 7
    case behaviorEvidence = 8
    case timeout = 9
    case accessibilityPermission = 10
    case action = 11
}

private struct ProbeFailure: Error {
    let code: ExitCode
    let message: String
}

private struct Arguments {
    let pid: pid_t
    let expandWeekly: Bool
    let skipDaily: Bool
    let acceptHypothesis: Bool
    let expectLearned: Bool
    let deleteLearning: Bool

    static func parse() throws -> Arguments {
        var pid: pid_t?
        var expandWeekly = false
        var skipDaily = false
        var acceptHypothesis = false
        var expectLearned = false
        var deleteLearning = false
        var index = 1
        while index < CommandLine.arguments.count {
            switch CommandLine.arguments[index] {
            case "--pid":
                index += 1
                guard index < CommandLine.arguments.count,
                      let value = Int32(CommandLine.arguments[index]),
                      value > 0 else {
                    throw ProbeFailure(code: .usage, message: "--pid requires a positive process identifier")
                }
                pid = value
            case "--expand-weekly":
                expandWeekly = true
            case "--skip-daily":
                skipDaily = true
            case "--accept-hypothesis":
                acceptHypothesis = true
            case "--expect-learned":
                expectLearned = true
            case "--delete-learning":
                deleteLearning = true
            case "--help", "-h":
                throw ProbeFailure(code: .usage, message: usage)
            default:
                throw ProbeFailure(code: .usage, message: "unsupported argument")
            }
            index += 1
        }
        guard let pid else {
            throw ProbeFailure(code: .usage, message: "--pid is required")
        }
        guard !(acceptHypothesis && expectLearned) else {
            throw ProbeFailure(code: .usage, message: "--accept-hypothesis and --expect-learned are mutually exclusive")
        }
        return Arguments(
            pid: pid,
            expandWeekly: expandWeekly,
            skipDaily: skipDaily,
            acceptHypothesis: acceptHypothesis,
            expectLearned: expectLearned,
            deleteLearning: deleteLearning
        )
    }
}

private let usage = "Usage: qa-combined-review-ax-probe.swift --pid <pid> [--expand-weekly] [--skip-daily] [--accept-hypothesis|--expect-learned] [--delete-learning]"
private let maximumNodesPerTarget = 2_000
private let targetTimeout: TimeInterval = 4
private let scrollToVisibleAction = "AXScrollToVisible" as CFString

private let privateSentinels = [
    "qa-review-private-sentinel",
    "secret-review-",
    "https://private.invalid/qa-review",
]

private let dailySections: [(id: String, label: String, value: String?, hint: String)] = [
    (
        "reviews.evidence-boundary.observed-facts",
        "OBSERVED FACTS",
        nil,
        "These values come from corrected local activity. Missing time stays unobserved instead of being filled in."
    ),
    (
        "reviews.evidence-boundary.user-context",
        "USER CONTEXT",
        "PERSONAL CONTEXT ADDED",
        "A personal note can explain circumstances, but it is never treated as observed behavior or learned automatically."
    ),
    (
        "reviews.evidence-boundary.hypothesis",
        "HYPOTHESIS",
        "UNCONFIRMED HYPOTHESIS",
        "A possible explanation is kept separate and remains a hypothesis, not an observed fact."
    ),
]

private let workCategories: [(suffix: String, label: String, hint: String)] = [
    ("deep_work", "Deep work, 5 minutes", "Work observed in explicitly recognized development tools."),
    ("creative_work", "Creative work, 5 minutes", "Work observed in explicitly recognized design and media tools."),
    ("research", "Research, 5 minutes", "Work observed in explicitly recognized research tools."),
    ("communication", "Communication, 5 minutes", "Work observed in explicitly recognized communication tools."),
    ("administration", "Administration, 5 minutes", "Work observed in explicitly recognized planning and administration tools."),
    ("uncategorized", "Uncategorized work, 5 minutes", "Work that cannot be safely categorized from the application name alone."),
]

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func identifier(of element: AXUIElement) -> String? {
    stringAttribute(element, kAXIdentifierAttribute as CFString)
}

private func role(of element: AXUIElement) -> String? {
    stringAttribute(element, kAXRoleAttribute as CFString)
}

private func publicStrings(of element: AXUIElement) -> [String] {
    [
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
        stringAttribute(element, kAXHelpAttribute as CFString),
    ].compactMap { $0 }
}

private func hasExactPublicString(_ expected: String, element: AXUIElement) -> Bool {
    publicStrings(of: element).contains(expected)
}

private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(lhs, rhs)
}

private func boundedWalk(
    from root: AXUIElement,
    targetName: String,
    visit: (AXUIElement) throws -> Bool
) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(targetTimeout)
    var stack = [root]
    var visited = Set<CFHashCode>()
    var count = 0

    while let element = stack.popLast() {
        if Date() >= deadline {
            throw ProbeFailure(code: .timeout, message: "timed out while locating \(targetName)")
        }
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodesPerTarget else {
            throw ProbeFailure(code: .timeout, message: "node limit reached while locating \(targetName)")
        }
        if try visit(element) { return element }
        stack.append(contentsOf: children(of: element).reversed())
    }
    return nil
}

private func requireTarget(
    in root: AXUIElement,
    name: String,
    code: ExitCode,
    matching: (AXUIElement) -> Bool
) throws -> AXUIElement {
    if let result = try boundedWalk(from: root, targetName: name, visit: matching) {
        return result
    }
    throw ProbeFailure(code: code, message: "required target is unavailable: \(name)")
}

private func requireIdentifier(
    _ expected: String,
    in root: AXUIElement,
    code: ExitCode
) throws -> AXUIElement {
    try requireTarget(in: root, name: expected, code: code) { identifier(of: $0) == expected }
}

private func requireIdentifierByScrolling(
    _ expected: String,
    in window: AXUIElement,
    code: ExitCode,
    maximumPages: Int = 16
) throws -> AXUIElement {
    for page in 0...maximumPages {
        if let element = try boundedWalk(
            from: window,
            targetName: expected,
            visit: { identifier(of: $0) == expected }
        ) {
            return element
        }
        guard page < maximumPages else { break }
        var scrollAreas: [AXUIElement] = []
        _ = try boundedWalk(from: window, targetName: "scroll areas") { element in
            if role(of: element) == (kAXScrollAreaRole as String) {
                scrollAreas.append(element)
            }
            return false
        }
        var scrolled = false
        for scrollArea in scrollAreas.reversed() {
            if AXUIElementPerformAction(scrollArea, "AXScrollDownByPage" as CFString) == .success {
                scrolled = true
                break
            }
        }
        if !scrolled {
            guard let wheel = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: -12,
                wheel2: 0,
                wheel3: 0
            ) else {
                throw ProbeFailure(code: code, message: "could not scroll toward \(expected)")
            }
            wheel.post(tap: CGEventTapLocation.cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    let snapshot = try subtreeSnapshot(root: window, name: "scroll diagnostics")
    throw ProbeFailure(
        code: code,
        message: "required target is unavailable after scrolling: \(expected); identifiers=\(snapshot.identifiers.prefix(120).joined(separator: " | ")); visible strings=\(snapshot.strings.prefix(120).joined(separator: " | "))"
    )
}

private func press(_ element: AXUIElement, name: String, code: ExitCode) throws {
    _ = AXUIElementPerformAction(element, scrollToVisibleAction)
    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
        return
    }
    guard let positionValue = attribute(element, kAXPositionAttribute as CFString),
          let sizeValue = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        throw ProbeFailure(code: code, message: "could not activate \(name)")
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
          AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else {
        throw ProbeFailure(code: code, message: "could not resolve the clickable frame for \(name)")
    }
    let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        throw ProbeFailure(code: code, message: "could not create a click for \(name)")
    }
    down.post(tap: CGEventTapLocation.cghidEventTap)
    up.post(tap: CGEventTapLocation.cghidEventTap)
}

private func pauseForPresentation() {
    Thread.sleep(forTimeInterval: 0.3)
}

private func subtreeSnapshot(
    root: AXUIElement,
    name: String
) throws -> (identifiers: [String], strings: [String]) {
    var identifiers: [String] = []
    var strings: [String] = []
    _ = try boundedWalk(from: root, targetName: name) { element in
        if let identifier = identifier(of: element) { identifiers.append(identifier) }
        strings.append(contentsOf: publicStrings(of: element))
        return false
    }
    return (identifiers, strings)
}

private func assertNoPrivateSentinel(_ strings: [String], code: ExitCode, scope: String) throws {
    let normalized = strings.map { $0.lowercased() }
    guard normalized.allSatisfy({ value in
        privateSentinels.allSatisfy { !value.contains($0) }
    }) else {
        throw ProbeFailure(code: code, message: "private fixture evidence escaped into \(scope)")
    }
}

private func singleMainWindow(application: AXUIElement) throws -> AXUIElement {
    guard let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        throw ProbeFailure(code: .attach, message: "the supplied process does not expose application windows")
    }
    let eligible = windows.filter {
        role(of: $0) == (kAXWindowRole as String)
            && boolAttribute($0, kAXMinimizedAttribute as CFString) != true
    }
    guard eligible.count == 1, let window = eligible.first else {
        throw ProbeFailure(code: .window, message: "expected exactly one non-minimized application window")
    }
    if let mainValue = attribute(application, kAXMainWindowAttribute as CFString),
       CFGetTypeID(mainValue) == AXUIElementGetTypeID() {
        let main = unsafeBitCast(mainValue, to: AXUIElement.self)
        guard sameElement(main, window) else {
            throw ProbeFailure(code: .window, message: "the visible application window is not the main window")
        }
    }
    return window
}

private func navigate(_ label: String, in window: AXUIElement) throws {
    if let button = try boundedWalk(from: window, targetName: label, visit: {
        role(of: $0) == (kAXButtonRole as String) && hasExactPublicString(label, element: $0)
    }) {
        try press(button, name: label, code: .navigation)
        pauseForPresentation()
        return
    }
    let snapshot = try subtreeSnapshot(root: window, name: "navigation diagnostics")
    throw ProbeFailure(
        code: .navigation,
        message: "required navigation target is unavailable: \(label); visible strings=\(snapshot.strings.prefix(80).joined(separator: " | "))"
    )
}

private func assertDailyReview(window: AXUIElement) throws {
    let boundary = try requireIdentifier("reviews.evidence-boundary", in: window, code: .dailyReview)
    _ = AXUIElementPerformAction(boundary, scrollToVisibleAction)

    var elements: [AXUIElement] = []
    for section in dailySections {
        let element = try requireIdentifier(section.id, in: boundary, code: .dailyReview)
        guard hasExactPublicString(section.label, element: element),
              stringAttribute(element, kAXHelpAttribute as CFString) == section.hint else {
            throw ProbeFailure(code: .dailyReview, message: "Daily Review evidence contract mismatch for \(section.id)")
        }
        if let value = section.value,
           stringAttribute(element, kAXValueAttribute as CFString) != value {
            throw ProbeFailure(code: .dailyReview, message: "Daily Review evidence status mismatch for \(section.id)")
        }
        elements.append(element)
    }

    guard Set(elements.map(CFHash)).count == dailySections.count else {
        throw ProbeFailure(code: .dailyReview, message: "Daily Review evidence sections are not distinct AX elements")
    }
    let observedStatus = stringAttribute(elements[0], kAXValueAttribute as CFString) ?? ""
    let observedPattern = #"^[1-9][0-9]* OBSERVED SESSIONS? · [1-9][0-9]* MIN$"#
    guard observedStatus.range(of: observedPattern, options: .regularExpression) != nil else {
        throw ProbeFailure(code: .dailyReview, message: "Daily Review observed facts do not expose session and minute totals")
    }

    let snapshot = try subtreeSnapshot(root: boundary, name: "Daily Review evidence boundary")
    let ordered = snapshot.identifiers.filter { $0.hasPrefix("reviews.evidence-boundary.") }
    guard ordered == dailySections.map(\.id) else {
        throw ProbeFailure(code: .dailyReview, message: "Daily Review evidence sections are missing, duplicated, or out of order")
    }
    try assertNoPrivateSentinel(snapshot.strings, code: .dailyReview, scope: "Daily Review collapsed evidence")
}

private func assertWeeklyReview(
    window: AXUIElement,
    expand: Bool,
    acceptHypothesis: Bool,
    expectLearned: Bool
) throws {
    let patterns = window
    let patternsSnapshot = try subtreeSnapshot(root: patterns, name: "Weekly Review patterns")
    let prefix = "reviews.weekly.pattern."
    let learningStatusSuffix = ".learning-status"
    let patternIDs = patternsSnapshot.identifiers.compactMap { identifier -> String? in
        guard identifier.hasPrefix(prefix), identifier.hasSuffix(learningStatusSuffix) else { return nil }
        return String(identifier.dropLast(learningStatusSuffix.count))
    }
    guard patternIDs.count == 1, let patternID = patternIDs.first else {
        throw ProbeFailure(code: .weeklyReview, message: "expected exactly one Weekly Review pattern")
    }

    var card = patterns
    var status = try requireIdentifier("\(patternID).learning-status", in: card, code: .weeklyReview)
    let initialStatus = expectLearned ? "LEARNED FROM EXPLICIT ACCEPTANCE" : "NOT LEARNED"
    guard hasExactPublicString(initialStatus, element: status) else {
        throw ProbeFailure(code: .weeklyReview, message: "Weekly Review pattern is missing \(initialStatus)")
    }
    if expectLearned {
        let acceptID = "\(patternID).accept-hypothesis"
        let accept = try boundedWalk(from: card, targetName: acceptID) { identifier(of: $0) == acceptID }
        guard accept == nil else {
            throw ProbeFailure(code: .weeklyReview, message: "learned Weekly Review pattern still exposes acceptance")
        }
    }
    var evidenceButton = try requireIdentifier("\(patternID).evidence", in: card, code: .weeklyReview)
    guard hasExactPublicString("SHOW EVIDENCE", element: evidenceButton) else {
        throw ProbeFailure(code: .weeklyReview, message: "Weekly Review pattern did not start collapsed")
    }
    var cardSnapshot = try subtreeSnapshot(root: card, name: "collapsed Weekly Review pattern")
    guard cardSnapshot.strings.allSatisfy({
        !$0.localizedCaseInsensitiveContains("Observed evidence:")
            && !$0.localizedCaseInsensitiveContains("Alternative explanation:")
    }) else {
        throw ProbeFailure(code: .weeklyReview, message: "Weekly Review collapsed pattern exposed hidden evidence")
    }
    try assertNoPrivateSentinel(cardSnapshot.strings, code: .weeklyReview, scope: "Weekly Review collapsed pattern")

    if acceptHypothesis {
        let acceptID = "\(patternID).accept-hypothesis"
        let accept = try requireIdentifier(acceptID, in: card, code: .weeklyReview)
        _ = AXUIElementPerformAction(accept, scrollToVisibleAction)
        guard AXUIElementPerformAction(accept, kAXPressAction as CFString) == .success else {
            throw ProbeFailure(code: .action, message: "could not activate Weekly Review hypothesis acceptance")
        }
        pauseForPresentation()
        card = patterns
        status = try requireIdentifier("\(patternID).learning-status", in: card, code: .weeklyReview)
        guard hasExactPublicString("LEARNED FROM EXPLICIT ACCEPTANCE", element: status) else {
            throw ProbeFailure(code: .weeklyReview, message: "accepted Weekly Review hypothesis did not become learned")
        }
        let remainingAccept = try boundedWalk(from: card, targetName: acceptID) { identifier(of: $0) == acceptID }
        guard remainingAccept == nil else {
            throw ProbeFailure(code: .weeklyReview, message: "accepted Weekly Review hypothesis still exposes acceptance")
        }
    }

    guard expand else { return }
    try press(evidenceButton, name: "Weekly Review evidence", code: .action)
    pauseForPresentation()
    card = patterns
    status = try requireIdentifier("\(patternID).learning-status", in: card, code: .weeklyReview)
    evidenceButton = try requireIdentifier("\(patternID).evidence", in: card, code: .weeklyReview)
    let expandedStatus = (acceptHypothesis || expectLearned)
        ? "LEARNED FROM EXPLICIT ACCEPTANCE"
        : "NOT LEARNED"
    guard hasExactPublicString(expandedStatus, element: status),
          hasExactPublicString("HIDE EVIDENCE", element: evidenceButton) else {
        throw ProbeFailure(code: .weeklyReview, message: "expanded Weekly Review did not retain its learning boundary")
    }
    cardSnapshot = try subtreeSnapshot(root: card, name: "expanded Weekly Review pattern")
    guard cardSnapshot.strings.contains(where: { $0.localizedCaseInsensitiveContains("Observed evidence:") }),
          cardSnapshot.strings.contains(where: { $0.localizedCaseInsensitiveContains("Alternative explanation:") }) else {
        throw ProbeFailure(code: .weeklyReview, message: "expanded Weekly Review did not expose evidence and an alternative")
    }
    try assertNoPrivateSentinel(cardSnapshot.strings, code: .weeklyReview, scope: "Weekly Review expanded pattern")
}

private func deleteReviewsAndLearning(window: AXUIElement) throws {
    try navigate("Settings", in: window)
    let records = try requireTarget(
        in: window,
        name: "Records, Local data and audit",
        code: .navigation
    ) {
        role(of: $0) == (kAXButtonRole as String)
            && hasExactPublicString("Records, Local data and audit", element: $0)
    }
    try press(records, name: "Records settings chapter", code: .navigation)
    pauseForPresentation()
    let delete = try requireIdentifierByScrolling(
        "settings.data.delete-reviews-learning",
        in: window,
        code: .action,
        maximumPages: 20
    )
    try press(delete, name: "Delete reviews and learned rules", code: .action)
    pauseForPresentation()
    let confirm = try requireTarget(
        in: window,
        name: "DELETE REVIEWS AND LEARNED RULES confirmation",
        code: .action
    ) {
        role(of: $0) == (kAXButtonRole as String)
            && hasExactPublicString("DELETE REVIEWS AND LEARNED RULES", element: $0)
    }
    try press(confirm, name: "Delete reviews and learned rules confirmation", code: .action)

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let status = try boundedWalk(
            from: window,
            targetName: "settings.data.deletion-status",
            visit: { identifier(of: $0) == "settings.data.deletion-status" }
        ), publicStrings(of: status).contains(where: {
            $0.localizedCaseInsensitiveContains("deleted")
                || $0.localizedCaseInsensitiveContains("already clear")
        }) {
            return
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeFailure(code: .action, message: "review and learning deletion did not report completion")
}

private func assertBehaviorEvidence(window: AXUIElement) throws {
    let open = try requireIdentifier("today.behavior-evidence.open", in: window, code: .behaviorEvidence)
    try press(open, name: "View all activity", code: .action)
    pauseForPresentation()

    let sheet = try requireIdentifier("today.behavior-evidence.sheet", in: window, code: .behaviorEvidence)
    let ledger = try requireIdentifier("today.behavior-evidence.work-categories", in: sheet, code: .behaviorEvidence)
    _ = AXUIElementPerformAction(ledger, scrollToVisibleAction)

    var elements: [AXUIElement] = []
    let expectedIDs = workCategories.map { "today.behavior-evidence.work-category.\($0.suffix)" }
    for (index, category) in workCategories.enumerated() {
        let element = try requireIdentifier(expectedIDs[index], in: ledger, code: .behaviorEvidence)
        guard hasExactPublicString(category.label, element: element),
              stringAttribute(element, kAXHelpAttribute as CFString) == category.hint else {
            throw ProbeFailure(code: .behaviorEvidence, message: "work-category AX contract mismatch for \(category.suffix)")
        }
        elements.append(element)
    }
    guard Set(elements.map(CFHash)).count == workCategories.count else {
        throw ProbeFailure(code: .behaviorEvidence, message: "work-category totals are not six distinct AX elements")
    }
    let snapshot = try subtreeSnapshot(root: ledger, name: "Behavior Evidence work categories")
    let ordered = snapshot.identifiers.filter { $0.hasPrefix("today.behavior-evidence.work-category.") }
    guard ordered == expectedIDs else {
        throw ProbeFailure(code: .behaviorEvidence, message: "work-category totals are missing, duplicated, or out of order")
    }
    let sheetSnapshot = try subtreeSnapshot(root: sheet, name: "Behavior Evidence sheet")
    try assertNoPrivateSentinel(sheetSnapshot.strings, code: .behaviorEvidence, scope: "Behavior Evidence")
}

private func run() throws {
    let arguments = try Arguments.parse()
    guard AXIsProcessTrusted() else {
        throw ProbeFailure(code: .accessibilityPermission, message: "Accessibility permission is required")
    }
    guard kill(arguments.pid, 0) == 0 else {
        throw ProbeFailure(code: .attach, message: "the supplied process is not running")
    }

    let application = AXUIElementCreateApplication(arguments.pid)
    _ = NSRunningApplication(processIdentifier: arguments.pid)?.activate(options: [])
    Thread.sleep(forTimeInterval: 0.2)
    let window = try singleMainWindow(application: application)
    if arguments.deleteLearning {
        try deleteReviewsAndLearning(window: window)
        print("PASS: review and learning privacy deletion completed through signed UI")
        return
    }
    try navigate("Reviews", in: window)
    if !arguments.skipDaily {
        try assertDailyReview(window: window)
    }
    try assertWeeklyReview(
        window: window,
        expand: arguments.expandWeekly,
        acceptHypothesis: arguments.acceptHypothesis,
        expectLearned: arguments.expectLearned
    )
    try navigate("Today", in: window)
    try assertBehaviorEvidence(window: window)

    let weeklyMode = arguments.expandWeekly ? "weekly expanded" : "weekly collapsed"
    print("PASS: combined review AX contract verified (\(weeklyMode))")
}

do {
    try run()
    exit(ExitCode.success.rawValue)
} catch let failure as ProbeFailure {
    fputs("FAIL: \(failure.message)\n", stderr)
    if failure.code == .usage { fputs("\(usage)\n", stderr) }
    exit(failure.code.rawValue)
} catch {
    fputs("FAIL: unexpected verifier error (details redacted)\n", stderr)
    exit(ExitCode.dailyReview.rawValue)
}
