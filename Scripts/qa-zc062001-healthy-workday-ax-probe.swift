#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error { case failure(String) }

private let mainWindowID = "zoid-666.main-window"
private let privateSentinels = [
    "qa-zc062001-private-window",
    "qa-zc062001.private.invalid",
]
private let requiredEvidenceRows = [
    "Planned day - Today's commitments are ready",
    "Apple Reminders - Healthy",
    "Screenwatch - Current and ingested",
    "Zoid 666 Agent - Running",
    "Local database - Healthy",
]

private struct AXRowEvidence {
    let identity: CFHashCode
    let labels: [String]
}

private func safeEvidenceRows(
    dayState: [String],
    todayText: String,
    healthRows: [[String]]
) -> [String]? {
    guard healthRows.count == 4 else { return nil }
    let healthText = healthRows.map { $0.joined(separator: "\n") }
    let visible = dayState.joined(separator: "\n") + "\n" + todayText + "\n" + healthText.joined(separator: "\n")
    guard dayState.contains(where: { $0.localizedCaseInsensitiveContains("PLANNED DAY") }),
          dayState.contains(where: { $0.localizedCaseInsensitiveContains("commitments are ready") }),
          todayText.localizedCaseInsensitiveContains("Reminders"),
          todayText.localizedCaseInsensitiveContains("available"),
          todayText.localizedCaseInsensitiveContains("Screenwatch"),
          todayText.localizedCaseInsensitiveContains("current"),
          todayText.localizedCaseInsensitiveContains("agent"),
          todayText.localizedCaseInsensitiveContains("running"),
          healthText[0].localizedCaseInsensitiveContains("Apple Reminders"),
          healthText[0].localizedCaseInsensitiveContains("HEALTHY"),
          healthText[1].localizedCaseInsensitiveContains("Screenwatch"),
          healthText[1].localizedCaseInsensitiveContains("HEALTHY"),
          healthText[2].localizedCaseInsensitiveContains("Zoid 666 Agent"),
          healthText[2].localizedCaseInsensitiveContains("HEALTHY"),
          healthText[3].localizedCaseInsensitiveContains("Local database"),
          healthText[3].localizedCaseInsensitiveContains("HEALTHY"),
          !visible.localizedCaseInsensitiveContains("stale"),
          !visible.localizedCaseInsensitiveContains("limited"),
          !privateSentinels.contains(where: visible.localizedCaseInsensitiveContains)
    else { return nil }
    return requiredEvidenceRows
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let safe = safeEvidenceRows(
        dayState: ["Day state: PLANNED DAY. Today's commitments are ready."],
        todayText: "Reminders AVAILABLE\nScreenwatch CURRENT\nZoid 666 Agent RUNNING",
        healthRows: [
            ["Apple Reminders", "HEALTHY"],
            ["Screenwatch", "HEALTHY"],
            ["Zoid 666 Agent", "HEALTHY"],
            ["Local database", "HEALTHY"],
        ]
    )
    guard safe == requiredEvidenceRows,
          Set(safe ?? []).count == 5,
          safeEvidenceRows(
              dayState: ["PLANNED DAY", "Today's commitments are ready."],
              todayText: "Reminders AVAILABLE Screenwatch STALE Agent RUNNING",
              healthRows: [
                  ["Apple Reminders", "HEALTHY"], ["Screenwatch", "HEALTHY"],
                  ["Zoid 666 Agent", "HEALTHY"], ["Local database", "HEALTHY"],
              ]
          ) == nil,
          safeEvidenceRows(
              dayState: ["PLANNED DAY", "Today's commitments are ready."],
              todayText: "Reminders AVAILABLE Screenwatch CURRENT Agent RUNNING \(privateSentinels[0])",
              healthRows: [
                  ["Apple Reminders", "HEALTHY"], ["Screenwatch", "HEALTHY"],
                  ["Zoid 666 Agent", "HEALTHY"], ["Local database", "HEALTHY"],
              ]
          ) == nil
    else {
        fputs("FAIL: ZC-062-001 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-062-001 AX probe self-test")
    exit(0)
}

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2])
else {
    fputs("usage: qa-zc062001-healthy-workday-ax-probe.swift --self-test | --pid <pid>\n", stderr)
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
        guard count <= 6_000 else { throw ProbeError.failure("AX traversal exceeded 6000 nodes") }
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

private func element(_ id: String, in root: AXUIElement) throws -> AXUIElement? {
    var match: AXUIElement?
    try walk(root) { candidate in
        if identifier(candidate) == id { match = candidate }
    }
    return match
}

private func rowEvidence(named title: String, state: String, in root: AXUIElement) throws -> AXRowEvidence? {
    var candidates: [AXUIElement] = []
    try walk(root) { candidate in
        if labels(candidate).contains(where: { $0.localizedCaseInsensitiveContains(title) }) {
            candidates.append(candidate)
        }
    }
    for candidate in candidates {
        var current: AXUIElement? = candidate
        for _ in 0..<5 {
            guard let node = current else { break }
            let text = try allLabels(node)
            if text.contains(where: { $0.localizedCaseInsensitiveContains(title) }),
               text.contains(where: { $0.localizedCaseInsensitiveContains(state) }) {
                return AXRowEvidence(identity: CFHash(node), labels: text)
            }
            guard let parent = attribute(node, kAXParentAttribute as CFString),
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else {
                current = nil
                break
            }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
    }
    return nil
}

private func press(_ id: String, in window: AXUIElement) throws {
    guard let target = try element(id, in: window) else {
        throw ProbeError.failure("navigation is unavailable: \(id)")
    }
    guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("navigation could not be pressed: \(id)")
    }
}

do {
    let window = try mainWindow()
    try press("sidebar.navigation.today", in: window)
    var dayState: [String] = []
    var todayText = ""
    for _ in 0..<60 {
        if let day = try element("today.day-state", in: window) {
            dayState = try allLabels(day)
            todayText = try allLabels(window).joined(separator: "\n")
            if dayState.contains(where: { $0.localizedCaseInsensitiveContains("PLANNED DAY") }) { break }
        }
        Thread.sleep(forTimeInterval: 0.25)
    }

    try press("sidebar.navigation.source-health", in: window)
    var healthRows: [[String]] = []
    for _ in 0..<60 {
        if let reminders = try rowEvidence(named: "Apple Reminders", state: "HEALTHY", in: window),
           let screenwatch = try rowEvidence(named: "Screenwatch", state: "HEALTHY", in: window),
           let agent = try rowEvidence(named: "Zoid 666 Agent", state: "HEALTHY", in: window),
           let database = try rowEvidence(named: "Local database", state: "HEALTHY", in: window),
           Set([reminders.identity, screenwatch.identity, agent.identity, database.identity]).count == 4 {
            healthRows = [reminders.labels, screenwatch.labels, agent.labels, database.labels]
            break
        }
        Thread.sleep(forTimeInterval: 0.25)
    }

    guard let rows = safeEvidenceRows(
        dayState: dayState,
        todayText: todayText,
        healthRows: healthRows
    ) else {
        throw ProbeError.failure("planned-day or five-row healthy evidence is incomplete, stale, limited, or private")
    }
    for row in rows { print("EVIDENCE_ROW: \(row)") }
    print("PASS: exactly five privacy-safe planned-day health rows are visible")
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
