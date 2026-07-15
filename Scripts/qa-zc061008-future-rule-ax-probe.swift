#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error { case failure(String) }

private let mainWindowID = "zoid-666.main-window"
private let rowPrefix = "reviews.session."
private let rowSuffixes = [
    ".unknown-explanation", ".classification", ".task", ".split", ".future-rule",
    ".future-rule.active", ".future-rule.remove", ".future-rule.preview", ".apply",
    ".merge-next", ".merge-candidate",
]
private let privateSentinels = [
    "qa-zc061008-private-future-window",
    "qa-zc061008.private.invalid",
]

private func exactSessionID(_ identifier: String) -> String? {
    guard identifier.hasPrefix(rowPrefix),
          !rowSuffixes.contains(where: identifier.hasSuffix)
    else { return nil }
    return String(identifier.dropFirst(rowPrefix.count))
}

private func provesJourney(rows: [String: [String]], rules: [[String]]) -> Bool {
    let safariRows = rows.filter { _, labels in
        labels.contains { $0.caseInsensitiveCompare("Safari") == .orderedSame }
    }
    guard safariRows.count == 2,
          safariRows.values.allSatisfy({ labels in
              labels.contains { $0.localizedCaseInsensitiveContains("WORK") }
          }),
          rules.count >= 1
    else { return false }
    let visible = (Array(safariRows.values) + rules).flatMap { $0 }
    guard !visible.contains(where: { label in
        label.localizedCaseInsensitiveContains("research")
            || privateSentinels.contains(where: label.localizedCaseInsensitiveContains)
    }) else { return false }
    return rules.contains { labels in
        let text = labels.joined(separator: "\n")
        return text.localizedCaseInsensitiveContains("FUTURE RULE")
            && text.localizedCaseInsensitiveContains("Safari")
            && text.localizedCaseInsensitiveContains("WORK")
            && text.localizedCaseInsensitiveContains("Historical records are unchanged")
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let safeRows = [
        "2026-07-15:100": ["Safari", "WORK", "9:00 AM - 9:01 AM"],
        "2026-07-15:200": ["Safari", "WORK", "10:00 AM - 10:01 AM"],
    ]
    let safeRule = [["FUTURE RULE", "Safari → WORK", "Historical records are unchanged."]]
    guard exactSessionID("reviews.session.2026-07-15:100") == "2026-07-15:100",
          exactSessionID("reviews.session.2026-07-15:100.classification") == nil,
          provesJourney(rows: safeRows, rules: safeRule),
          !provesJourney(rows: ["one": ["Safari", "WORK"]], rules: safeRule),
          !provesJourney(rows: safeRows, rules: [["FUTURE RULE", "Safari → RESEARCH"]]),
          !provesJourney(
              rows: safeRows,
              rules: [["FUTURE RULE", "Safari → WORK", privateSentinels[0]]]
          )
    else {
        fputs("FAIL: ZC-061-008 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-061-008 AX probe self-test")
    exit(0)
}

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2])
else {
    fputs("usage: qa-zc061008-future-rule-ax-probe.swift --self-test | --pid <pid>\n", stderr)
    exit(2)
}

private let application = AXUIElementCreateApplication(pid)

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

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func walk(_ root: AXUIElement, visit: (AXUIElement) -> Void) throws {
    var queue = [root]
    var seen = Set<CFHashCode>()
    var count = 0
    while let current = queue.first {
        queue.removeFirst()
        guard seen.insert(CFHash(current)).inserted else { continue }
        count += 1
        guard count <= 5_000 else { throw ProbeError.failure("AX traversal exceeded 5000 nodes") }
        visit(current)
        queue.append(contentsOf: children(current))
    }
}

private func allLabels(_ root: AXUIElement) throws -> [String] {
    var result: [String] = []
    try walk(root) { result.append(contentsOf: labels($0)) }
    return result
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw ProbeError.failure("the supplied process is not running") }
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    let candidates = try windows.filter { window in
        guard string(window, kAXRoleAttribute as CFString) == (kAXWindowRole as String),
              (attribute(window, kAXMinimizedAttribute as CFString) as? NSNumber)?.boolValue != true
        else { return false }
        if identifier(window) == mainWindowID { return true }
        let text = try allLabels(window)
        return text.contains("Today") && text.contains("Reviews")
    }
    guard candidates.count == 1 else {
        throw ProbeError.failure("expected one visible main window, found \(candidates.count)")
    }
    return candidates[0]
}

private func pressReviews(in window: AXUIElement) throws {
    var target: AXUIElement?
    try walk(window) { element in
        if identifier(element) == "sidebar.navigation.reviews" { target = element }
    }
    guard let target else { throw ProbeError.failure("Reviews navigation is unavailable") }
    guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("Reviews navigation could not be pressed")
    }
}

do {
    let window = try mainWindow()
    try pressReviews(in: window)
    var lastFailure = "Reviews evidence did not settle"
    for _ in 0..<60 {
        var rowElements: [String: AXUIElement] = [:]
        var ruleElements: [AXUIElement] = []
        try walk(window) { element in
            guard let id = identifier(element) else { return }
            if let sessionID = exactSessionID(id) { rowElements[sessionID] = element }
            if id.hasPrefix(rowPrefix), id.hasSuffix(".future-rule.active") {
                ruleElements.append(element)
            }
        }
        let rows = try rowElements.mapValues(allLabels)
        let rules = try ruleElements.map(allLabels)
        if provesJourney(rows: rows, rules: rules) {
            print("PASS: two distinct Safari Work sessions and the private active future-rule badge are visible")
            exit(0)
        }
        lastFailure = "expected exactly two Safari Work session rows and one safe active future-rule badge"
        Thread.sleep(forTimeInterval: 0.25)
    }
    throw ProbeError.failure(lastFailure)
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
