#!/usr/bin/env swift
import ApplicationServices
import Darwin
import Foundation

private enum Phase: String {
    case coaching
    case observation
    case recoaching
    case window
}

private struct ProbeFailure: Error {
    let message: String
}

private struct ElementSnapshot {
    let identifier: String?
    let values: [String]
}

private let mainWindowIdentifier = "zoid-666.main-window"
private let waitingPrefix = "today.prompt."
private let waitingSuffix = ".waiting"
private let historySuffix = ".history"
private let expectedTitle = "Ready for an easy return?"
private let expectedSummaryFragments = [
    "10 observed minutes in Steam",
    "ZC-035-011 priority objective remains unfinished",
    "This shows activity, not why it happened or what you intended."
]
private let expectedActionLabels = [
    "RETURN TO ZC-035-011 PRIORITY OBJECTIVE",
    "START A 10-MINUTE RECOVERY SPRINT",
    "FIVE MORE MINUTES",
    "CONTINUE INTENTIONALLY",
    "DISMISS"
]
private let forbiddenPrivacyFragments = [
    "PRIVATE-ZC035011-WINDOW-SENTINEL",
    "private-zc035011.invalid",
    "secret=sentinel"
]

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

private func values(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func walk(_ root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    while !queue.isEmpty && result.count < limit {
        let next = queue.removeFirst()
        result.append(next)
        queue.append(contentsOf: children(next))
    }
    return result
}

private func snapshot(_ elements: [AXUIElement]) -> [ElementSnapshot] {
    elements.map { ElementSnapshot(identifier: identifier($0), values: values($0)) }
}

private func privacyViolation(in snapshots: [ElementSnapshot]) -> String? {
    let exposed = snapshots.flatMap(\.values).joined(separator: "\n")
    return forbiddenPrivacyFragments.first {
        exposed.localizedCaseInsensitiveContains($0)
    }
}

private func matchingRows(
    in snapshots: [ElementSnapshot],
    suffix: String
) -> [ElementSnapshot] {
    snapshots.filter {
        guard let identifier = $0.identifier else { return false }
        return identifier.hasPrefix(waitingPrefix) && identifier.hasSuffix(suffix)
    }
}

private func contains(_ expected: String, in snapshots: [ElementSnapshot]) -> Bool {
    snapshots.flatMap(\.values).contains(expected)
}

private func containsFragment(_ expected: String, in snapshots: [ElementSnapshot]) -> Bool {
    snapshots.flatMap(\.values).contains {
        $0.localizedCaseInsensitiveContains(expected)
    }
}

private func assertPhase(_ phase: Phase, snapshots: [ElementSnapshot]) throws {
    if let violation = privacyViolation(in: snapshots) {
        throw ProbeFailure(message: "private source evidence leaked through Accessibility: \(violation)")
    }
    let waiting = matchingRows(in: snapshots, suffix: waitingSuffix)
    let history = matchingRows(in: snapshots, suffix: historySuffix)
    switch phase {
    case .window:
        guard snapshots.contains(where: { $0.identifier == "sidebar.navigation.today" }),
              snapshots.contains(where: { $0.identifier == "today.prompt-inbox" })
        else { throw ProbeFailure(message: "the unique main window is not on the Today surface") }
    case .coaching:
        guard waiting.count == 1 else {
            throw ProbeFailure(message: "expected exactly one waiting decision, found \(waiting.count)")
        }
        guard contains(expectedTitle, in: snapshots) else {
            throw ProbeFailure(message: "gentle gaming coaching title is missing")
        }
        for fragment in expectedSummaryFragments where !containsFragment(fragment, in: snapshots) {
            throw ProbeFailure(message: "coaching explanation is missing: \(fragment)")
        }
        for label in expectedActionLabels where !contains(label, in: snapshots) {
            throw ProbeFailure(message: "usable coaching action is missing: \(label)")
        }
    case .observation:
        guard waiting.isEmpty else {
            throw ProbeFailure(message: "stale coaching remains actionable after aligned work")
        }
        guard history.count == 1,
              contains(expectedTitle, in: snapshots),
              contains("DISMISSED", in: snapshots)
        else { throw ProbeFailure(message: "withdrawn coaching is not preserved as one non-actionable history row") }
    case .recoaching:
        guard waiting.count == 1, history.count == 1 else {
            throw ProbeFailure(message: "expected one new decision and one withdrawn history row")
        }
        guard contains(expectedTitle, in: snapshots),
              contains("DISMISSED", in: snapshots)
        else { throw ProbeFailure(message: "recoaching or withdrawn history content is missing") }
        for fragment in expectedSummaryFragments where !containsFragment(fragment, in: snapshots) {
            throw ProbeFailure(message: "later coaching explanation is missing: \(fragment)")
        }
        for label in expectedActionLabels where !contains(label, in: snapshots) {
            throw ProbeFailure(message: "later usable coaching action is missing: \(label)")
        }
    }
}

private func uniqueMainWindow(pid: pid_t) throws -> AXUIElement {
    let application = AXUIElementCreateApplication(pid)
    guard let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        throw ProbeFailure(message: "application exposes no windows")
    }
    let candidates = windows.filter {
        (attribute($0, kAXMinimizedAttribute as CFString) as? Bool) != true
            && identifier($0) == mainWindowIdentifier
    }
    guard candidates.count == 1, let window = candidates.first else {
        throw ProbeFailure(message: "expected one visible main window, found \(candidates.count)")
    }
    return window
}

private func runSelfTest() throws {
    let safe = [
        ElementSnapshot(identifier: "today.prompt.initial.waiting", values: [expectedTitle]),
        ElementSnapshot(identifier: nil, values: expectedSummaryFragments + expectedActionLabels)
    ]
    try assertPhase(.coaching, snapshots: safe)
    let observation = [
        ElementSnapshot(identifier: "today.prompt.initial.history", values: [expectedTitle, "DISMISSED"])
    ]
    try assertPhase(.observation, snapshots: observation)
    let recoaching = observation + [
        ElementSnapshot(identifier: "today.prompt.later.waiting", values: [expectedTitle]),
        ElementSnapshot(identifier: nil, values: expectedSummaryFragments + expectedActionLabels)
    ]
    try assertPhase(.recoaching, snapshots: recoaching)
    do {
        try assertPhase(.observation, snapshots: safe)
        throw ProbeFailure(message: "self-test accepted actionable coaching as observation-only")
    } catch let failure as ProbeFailure where failure.message != "self-test accepted actionable coaching as observation-only" {
        // Expected rejection.
    }
    guard privacyViolation(in: [ElementSnapshot(identifier: nil, values: [PRIVATE_SENTINEL_FOR_SELF_TEST])]) != nil else {
        throw ProbeFailure(message: "privacy self-test did not reject the private sentinel")
    }
    print("PASS: ZC-035-011 AX phase, action, history, and privacy self-test")
}

private let PRIVATE_SENTINEL_FOR_SELF_TEST = "PRIVATE-ZC035011-WINDOW-SENTINEL"

private func run() throws {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try runSelfTest()
        return
    }
    guard CommandLine.arguments.count == 5,
          CommandLine.arguments[1] == "--pid",
          let pid = pid_t(CommandLine.arguments[2]),
          CommandLine.arguments[3] == "--phase",
          let phase = Phase(rawValue: CommandLine.arguments[4])
    else {
        throw ProbeFailure(message: "usage: probe --self-test | --pid <pid> --phase <coaching|observation|recoaching|window>")
    }
    guard AXIsProcessTrusted() else {
        throw ProbeFailure(message: "Accessibility permission is required")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeFailure(message: "application process is not running")
    }
    var latestFailure = "phase did not become visible"
    for _ in 1...40 {
        let window = try uniqueMainWindow(pid: pid)
        do {
            try assertPhase(phase, snapshots: snapshot(walk(window)))
            print("PASS: ZC-035-011 \(phase.rawValue) accessibility and privacy contract verified")
            return
        } catch let failure as ProbeFailure {
            latestFailure = failure.message
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    throw ProbeFailure(message: latestFailure)
}

do {
    try run()
} catch let failure as ProbeFailure {
    fputs("FAIL: \(failure.message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: unexpected Accessibility probe error\n", stderr)
    exit(1)
}
