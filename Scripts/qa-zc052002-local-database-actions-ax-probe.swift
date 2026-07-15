#!/usr/bin/env swift
import ApplicationServices
import Darwin
import Foundation

private enum Phase: String {
    case window
    case healthy
    case readOnly = "read-only"
    case missing
    case unverified
}

private struct ProbeFailure: Error {
    let message: String
}

private struct ElementSnapshot {
    let identifier: String?
    let values: [String]
}

private let mainWindowIdentifier = "zoid-666.main-window"
private let navigationIdentifier = "sidebar.navigation.source-health"
private let availabilityIdentifier = "source-health.local-database.availability"
private let refreshIdentifier = "source-health.local-system.refresh"
private let retryIdentifier = "source-health.local-database.retry"
private let unavailableActions = [
    "Plan, start, pause, switch, complete, or reschedule tasks",
    "Save settings, coaching responses, or gaming adjustments",
    "Correct, note, skip, or confirm a review"
]
private let privateFragments = [
    "PRIVATE-ZC052002-RAW-DATABASE-SENTINEL",
    "original-private-bytes",
    ".zc052002-original-bytes"
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

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
}

private func walk(_ root: AXUIElement, limit: Int = 6_000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    while !queue.isEmpty && result.count < limit {
        let next = queue.removeFirst()
        result.append(next)
        queue.append(contentsOf: children(next))
    }
    return result
}

private func snapshots(_ elements: [AXUIElement]) -> [ElementSnapshot] {
    elements.map { ElementSnapshot(identifier: identifier($0), values: values($0)) }
}

private func exposedText(_ snapshots: [ElementSnapshot]) -> String {
    snapshots.flatMap(\.values).joined(separator: "\n")
}

private func containsFragment(_ fragment: String, in snapshots: [ElementSnapshot]) -> Bool {
    snapshots.flatMap(\.values).contains {
        $0.localizedCaseInsensitiveContains(fragment)
    }
}

private func containsIdentifier(_ expected: String, in snapshots: [ElementSnapshot]) -> Bool {
    snapshots.contains { $0.identifier == expected }
}

private func assertPrivacy(_ snapshots: [ElementSnapshot]) throws {
    let text = exposedText(snapshots)
    if let leaked = privateFragments.first(where: { text.localizedCaseInsensitiveContains($0) }) {
        throw ProbeFailure(message: "private database fixture content leaked through Accessibility: \(leaked)")
    }
}

private func assertUnavailableActions(_ snapshots: [ElementSnapshot]) throws {
    guard containsFragment("TEMPORARILY UNAVAILABLE", in: snapshots) else {
        throw ProbeFailure(message: "temporarily unavailable heading is missing")
    }
    for action in unavailableActions where !containsFragment(action, in: snapshots) {
        throw ProbeFailure(message: "named unavailable action group is missing: \(action)")
    }
}

private func assertPhase(_ phase: Phase, snapshots: [ElementSnapshot]) throws {
    try assertPrivacy(snapshots)
    switch phase {
    case .window:
        guard containsIdentifier(navigationIdentifier, in: snapshots) else {
            throw ProbeFailure(message: "unique main window does not expose Source health navigation")
        }
    case .healthy:
        guard containsIdentifier(availabilityIdentifier, in: snapshots),
              containsFragment("ACTIONS AVAILABLE", in: snapshots),
              containsFragment("Planning, task, coaching, and review changes are available.", in: snapshots),
              containsFragment("passed its integrity check on the current schema", in: snapshots)
        else { throw ProbeFailure(message: "healthy action-availability guidance is incomplete") }
        guard !containsFragment("TEMPORARILY UNAVAILABLE", in: snapshots),
              !containsIdentifier(retryIdentifier, in: snapshots)
        else { throw ProbeFailure(message: "healthy state incorrectly exposes unavailable actions or recovery") }
    case .readOnly:
        guard containsIdentifier(availabilityIdentifier, in: snapshots),
              containsFragment("READ-ONLY SAFETY", in: snapshots),
              containsFragment("Changes are paused while the local schema is out of date.", in: snapshots),
              containsFragment("will not claim that a change was saved until migration succeeds", in: snapshots)
        else { throw ProbeFailure(message: "read-only safety explanation is incomplete") }
        try assertUnavailableActions(snapshots)
        guard containsFragment("Quit and reopen Zoid 666", in: snapshots),
              containsFragment("database is left unchanged if verification still fails", in: snapshots),
              containsIdentifier(retryIdentifier, in: snapshots),
              containsFragment("RETRY AFTER RESTART", in: snapshots)
        else { throw ProbeFailure(message: "read-only recovery path is incomplete") }
    case .missing:
        guard containsIdentifier(availabilityIdentifier, in: snapshots),
              containsFragment("ACTIONS UNAVAILABLE", in: snapshots),
              containsFragment("local database is not ready", in: snapshots),
              containsFragment("cannot safely load or record durable changes", in: snapshots)
        else { throw ProbeFailure(message: "missing-database explanation is incomplete") }
        try assertUnavailableActions(snapshots)
        try assertRetryableUnavailable(snapshots)
    case .unverified:
        guard containsIdentifier(availabilityIdentifier, in: snapshots),
              containsFragment("ACTIONS UNAVAILABLE", in: snapshots),
              containsFragment("local database could not be verified", in: snapshots),
              containsFragment("cannot safely read current state or record durable changes", in: snapshots)
        else { throw ProbeFailure(message: "unverified-database explanation is incomplete") }
        try assertUnavailableActions(snapshots)
        try assertRetryableUnavailable(snapshots)
    }
}

private func assertRetryableUnavailable(_ snapshots: [ElementSnapshot]) throws {
    guard containsIdentifier(retryIdentifier, in: snapshots),
          containsFragment("RETRY STORAGE CHECK", in: snapshots),
          containsFragment("Check again now", in: snapshots),
          containsFragment("quit and reopen Zoid 666", in: snapshots),
          containsFragment("No database repair or deletion is performed by this check", in: snapshots)
    else { throw ProbeFailure(message: "retryable non-destructive recovery guidance is incomplete") }
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

private func press(identifier expected: String, in window: AXUIElement) throws {
    let matches = walk(window).filter { identifier($0) == expected }
    guard matches.count == 1, let element = matches.first else {
        throw ProbeFailure(message: "expected one \(expected) control, found \(matches.count)")
    }
    _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeFailure(message: "could not press \(expected)")
    }
}

private func scrollDown(in window: AXUIElement) {
    let scrollAreas = walk(window).filter { role($0) == (kAXScrollAreaRole as String) }
    for scrollArea in scrollAreas.reversed() {
        if AXUIElementPerformAction(scrollArea, "AXScrollDownByPage" as CFString) == .success {
            return
        }
    }
}

private func navigateToDiagnostics(pid: pid_t) throws -> AXUIElement {
    var window = try uniqueMainWindow(pid: pid)
    var current = snapshots(walk(window))
    if !containsIdentifier(availabilityIdentifier, in: current) {
        try press(identifier: navigationIdentifier, in: window)
    }
    for attempt in 1...60 {
        window = try uniqueMainWindow(pid: pid)
        current = snapshots(walk(window))
        try assertPrivacy(current)
        if containsIdentifier(availabilityIdentifier, in: current) {
            return window
        }
        if attempt % 4 == 0 { scrollDown(in: window) }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeFailure(message: "Local database availability card is unavailable after bounded Source health navigation")
}

private func waitForPhase(_ phase: Phase, pid: pid_t) throws -> AXUIElement {
    var latestFailure = "phase did not become visible"
    for attempt in 1...50 {
        let window = try navigateToDiagnostics(pid: pid)
        let current = snapshots(walk(window))
        do {
            try assertPhase(phase, snapshots: current)
            return window
        } catch let failure as ProbeFailure {
            latestFailure = failure.message
        }
        if attempt % 5 == 0 { scrollDown(in: window) }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeFailure(message: latestFailure)
}

private func makeSnapshots(_ values: [String], retry: Bool) -> [ElementSnapshot] {
    var result = [
        ElementSnapshot(identifier: availabilityIdentifier, values: values),
        ElementSnapshot(identifier: navigationIdentifier, values: ["Source health"]),
        ElementSnapshot(identifier: refreshIdentifier, values: ["REFRESH"])
    ]
    if retry {
        result.append(ElementSnapshot(identifier: retryIdentifier, values: values))
    }
    return result
}

private func runSelfTest() throws {
    let healthy = makeSnapshots([
        "ACTIONS AVAILABLE",
        "Planning, task, coaching, and review changes are available.",
        "The local database passed its integrity check on the current schema."
    ], retry: false)
    try assertPhase(.healthy, snapshots: healthy)

    let commonUnavailable = ["TEMPORARILY UNAVAILABLE"] + unavailableActions
    let readOnly = makeSnapshots(commonUnavailable + [
        "READ-ONLY SAFETY",
        "Changes are paused while the local schema is out of date.",
        "Zoid 666 will not claim that a change was saved until migration succeeds.",
        "Quit and reopen Zoid 666. The database is left unchanged if verification still fails.",
        "RETRY AFTER RESTART"
    ], retry: true)
    try assertPhase(.readOnly, snapshots: readOnly)

    let retry = [
        "ACTIONS UNAVAILABLE",
        "Check again now, then quit and reopen Zoid 666. No database repair or deletion is performed by this check.",
        "RETRY STORAGE CHECK"
    ]
    let missing = makeSnapshots(commonUnavailable + retry + [
        "The local database is not ready and cannot safely load or record durable changes."
    ], retry: true)
    try assertPhase(.missing, snapshots: missing)
    let unverified = makeSnapshots(commonUnavailable + retry + [
        "The local database could not be verified and cannot safely read current state or record durable changes."
    ], retry: true)
    try assertPhase(.unverified, snapshots: unverified)

    do {
        try assertPhase(.healthy, snapshots: readOnly)
        throw ProbeFailure(message: "self-test accepted read-only content as healthy")
    } catch let failure as ProbeFailure where failure.message != "self-test accepted read-only content as healthy" {
        // Expected rejection.
    }
    let incomplete = missing.map {
        ElementSnapshot(
            identifier: $0.identifier,
            values: $0.values.filter { !$0.contains("coaching responses") }
        )
    }
    do {
        try assertPhase(.missing, snapshots: incomplete)
        throw ProbeFailure(message: "self-test accepted a missing unavailable-action group")
    } catch let failure as ProbeFailure where failure.message != "self-test accepted a missing unavailable-action group" {
        // Expected rejection.
    }
    do {
        try assertPrivacy([ElementSnapshot(identifier: nil, values: [privateFragments[0]])])
        throw ProbeFailure(message: "self-test accepted a private database sentinel")
    } catch let failure as ProbeFailure where failure.message != "self-test accepted a private database sentinel" {
        // Expected rejection.
    }
    print("PASS: ZC-052-002 AX state, action, recovery, accessibility, and privacy self-test")
}

private func run() throws {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try runSelfTest()
        return
    }
    guard CommandLine.arguments.count >= 5,
          CommandLine.arguments[1] == "--pid",
          let pid = pid_t(CommandLine.arguments[2]),
          CommandLine.arguments[3] == "--phase",
          let phase = Phase(rawValue: CommandLine.arguments[4])
    else {
        throw ProbeFailure(message: "usage: probe --self-test | --pid <pid> --phase <window|healthy|read-only|missing|unverified> [--refresh] [--press-retry]")
    }
    let options = Set(CommandLine.arguments.dropFirst(5))
    guard options.isSubset(of: ["--refresh", "--press-retry"]) else {
        throw ProbeFailure(message: "unsupported probe option")
    }
    guard AXIsProcessTrusted() else {
        throw ProbeFailure(message: "Accessibility permission is required")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeFailure(message: "application process is not running")
    }

    if phase == .window {
        let window = try uniqueMainWindow(pid: pid)
        try assertPhase(.window, snapshots: snapshots(walk(window)))
        print("PASS: ZC-052-002 unique main window contract verified")
        return
    }

    var window = try navigateToDiagnostics(pid: pid)
    if options.contains("--refresh") {
        try press(identifier: refreshIdentifier, in: window)
    }
    window = try waitForPhase(phase, pid: pid)
    if options.contains("--press-retry") {
        guard phase != .healthy else {
            throw ProbeFailure(message: "healthy phase must not expose a recovery retry")
        }
        try press(identifier: retryIdentifier, in: window)
        _ = try waitForPhase(phase, pid: pid)
    }
    print("PASS: ZC-052-002 \(phase.rawValue) Accessibility, recovery, and privacy contract verified")
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
