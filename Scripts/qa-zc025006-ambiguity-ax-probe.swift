#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let visible: Bool
    let hasToday: Bool
    let hasReviews: Bool
}

private enum MainSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private let mainWindowIdentifier = "zoid-666.main-window"
private let privateSentinels = [
    "qa-zc025006-private-window-secret",
    "qa-zc025006.private.invalid",
]
private let actionSuffixes = [
    "classify_as_supporting_work",
    "classify_as_gaming",
    "keep_activity_unknown",
]

private func selectMain(_ windows: [WindowTraits]) -> MainSelection {
    let candidates = windows.indices.filter { index in
        let window = windows[index]
        guard !window.minimized, window.visible else { return false }
        return window.identifier == mainWindowIdentifier || (window.hasToday && window.hasReviews)
    }
    switch candidates.count {
    case 1: return .selected(candidates[0])
    case 0: return .missing
    default: return .ambiguous
    }
}

private func containsPrivateEvidence(_ strings: [String]) -> Bool {
    strings.contains { value in
        privateSentinels.contains { value.localizedCaseInsensitiveContains($0) }
    }
}

private func expectedStatus(for phase: String) -> String? {
    switch phase {
    case "choose-work":
        "The observed session is now counted as supporting work for QA focus task."
    case "choose-gaming":
        "The observed session is now counted as gaming."
    case "choose-unknown":
        "The observed session remains unknown. Coaching was not changed."
    default:
        nil
    }
}

private func expectedActionSuffix(for phase: String) -> String? {
    switch phase {
    case "choose-work": "classify_as_supporting_work"
    case "choose-gaming": "classify_as_gaming"
    case "choose-unknown": "keep_activity_unknown"
    default: nil
    }
}

private func expectedHistoryChoice(for phase: String) -> String? {
    switch phase {
    case "history-work": "CHOICE · CLASSIFY AS SUPPORTING WORK"
    case "history-gaming": "CHOICE · CLASSIFY AS GAMING"
    case "history-unknown": "CHOICE · KEEP ACTIVITY UNKNOWN"
    default: nil
    }
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
    let main = WindowTraits(
        identifier: mainWindowIdentifier,
        minimized: false,
        visible: true,
        hasToday: true,
        hasReviews: true
    )
    let auxiliary = WindowTraits(
        identifier: "agent-lifecycle",
        minimized: false,
        visible: true,
        hasToday: false,
        hasReviews: false
    )
    let fallback = WindowTraits(
        identifier: nil,
        minimized: false,
        visible: true,
        hasToday: true,
        hasReviews: true
    )
    let hidden = WindowTraits(
        identifier: mainWindowIdentifier,
        minimized: false,
        visible: false,
        hasToday: true,
        hasReviews: true
    )
    guard selectMain([main, auxiliary]) == .selected(0),
          selectMain([auxiliary, fallback]) == .selected(1),
          selectMain([main, fallback]) == .ambiguous,
          selectMain([hidden, auxiliary]) == .missing,
          expectedStatus(for: "choose-work")?.contains("QA focus task") == true,
          expectedStatus(for: "choose-gaming")?.contains("gaming") == true,
          expectedStatus(for: "choose-unknown")?.contains("remains unknown") == true,
          expectedActionSuffix(for: "choose-work") == actionSuffixes[0],
          expectedHistoryChoice(for: "history-unknown") == "CHOICE · KEEP ACTIVITY UNKNOWN",
          containsPrivateEvidence(["private qa-zc025006-private-window-secret"]),
          !containsPrivateEvidence(["about 10 minutes in Safari", "cannot show your intent"])
    else {
        fputs("FAIL: ZC-025-006 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-025-006 AX probe self-test")
    exit(0)
}

let arguments = CommandLine.arguments
guard arguments.count == 5,
      arguments[1] == "--pid",
      let pid = Int32(arguments[2]),
      arguments[3] == "--phase",
      [
          "prompt", "choose-work", "choose-gaming", "choose-unknown",
          "history-work", "history-gaming", "history-unknown", "absent", "window",
      ].contains(arguments[4])
else {
    fputs("usage: qa-zc025006-ambiguity-ax-probe.swift --self-test | --pid <pid> --phase <prompt|choose-work|choose-gaming|choose-unknown|history-work|history-gaming|history-unknown|absent|window>\n", stderr)
    exit(2)
}

private let phase = arguments[4]
private let application = AXUIElementCreateApplication(pid)
private let maximumNodes = 4_000
private let maximumPolls = 60

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

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func actionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func walk(root: AXUIElement, visit: (AXUIElement) -> Void) throws {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(CFHash(current)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw ProbeError.failure("AX traversal exceeded \(maximumNodes) nodes")
        }
        visit(current)
        queue.append(contentsOf: children(current))
    }
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("Accessibility permission is required")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeError.failure("the supplied process is not running")
    }
    let windows = ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter { role($0) == (kAXWindowRole as String) }
    let traits = try windows.map { window in
        var navigation = Set<String>()
        try walk(root: window) { element in
            guard role(element) == (kAXButtonRole as String) else { return }
            navigation.formUnion(labels(element))
        }
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            visible: bool(window, "AXVisible" as CFString) != false,
            hasToday: navigation.contains("Today"),
            hasReviews: navigation.contains("Reviews")
        )
    }
    switch selectMain(traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}

private struct Snapshot {
    let identifiers: [String]
    let strings: [String]
    let elementsByIdentifier: [String: [AXUIElement]]
}

private func snapshot() throws -> Snapshot {
    let window = try mainWindow()
    var identifiers: [String] = []
    var strings: [String] = []
    var elementsByIdentifier: [String: [AXUIElement]] = [:]
    try walk(root: window) { element in
        if let id = identifier(element) {
            identifiers.append(id)
            elementsByIdentifier[id, default: []].append(element)
        }
        strings.append(contentsOf: labels(element))
    }
    return Snapshot(
        identifiers: identifiers,
        strings: strings,
        elementsByIdentifier: elementsByIdentifier
    )
}

private func combined(_ strings: [String]) -> String {
    strings.joined(separator: "\n")
}

private func assertPrivacy(_ snapshot: Snapshot) throws {
    if containsPrivateEvidence(snapshot.strings) {
        throw ProbeError.failure("private window-title or URL evidence escaped into Today")
    }
}

private func actionIdentifiers(_ snapshot: Snapshot) -> [String] {
    snapshot.identifiers.filter { identifier in
        identifier.hasPrefix("today.prompt.") && identifier.contains(".action.")
    }
}

private func assertWaitingPrompt(_ snapshot: Snapshot) throws {
    try assertPrivacy(snapshot)
    let text = combined(snapshot.strings)
    guard text.contains("Did this support QA focus task?"),
          text.contains("about 10 minutes in Safari"),
          text.contains("cannot show your intent"),
          text.localizedCaseInsensitiveContains("It supported QA focus task"),
          text.localizedCaseInsensitiveContains("It was gaming"),
          text.localizedCaseInsensitiveContains("Keep it unknown")
    else {
        throw ProbeError.failure("the complete privacy-safe ambiguity prompt is not visible")
    }
    let actions = actionIdentifiers(snapshot)
    guard actions.count == 3,
          actionSuffixes.allSatisfy({ suffix in actions.contains(where: { $0.hasSuffix(".action.\(suffix)") }) })
    else {
        throw ProbeError.failure("the prompt does not expose exactly the three accessible response actions")
    }
    let waitingRows = snapshot.identifiers.filter {
        $0.hasPrefix("today.prompt.") && $0.hasSuffix(".waiting")
    }
    guard waitingRows.count == 1 else {
        throw ProbeError.failure("expected exactly one waiting ambiguity prompt row")
    }
}

private func waitForWaitingPrompt() throws -> Snapshot {
    for poll in 1...maximumPolls {
        let current = try snapshot()
        if (try? assertWaitingPrompt(current)) != nil { return current }
        if poll == 10 || poll == 30,
           let refresh = current.elementsByIdentifier["today.prompt-inbox.refresh"],
           refresh.count == 1,
           let button = refresh.first,
           actionNames(button).contains(kAXPressAction as String) {
            _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeError.failure("timed out waiting for the complete ambiguity prompt")
}

private func chooseAction(_ suffix: String, expectedStatus: String) throws {
    let before = try waitForWaitingPrompt()
    let matches = before.elementsByIdentifier.flatMap { key, elements in
        key.hasSuffix(".action.\(suffix)") ? elements : []
    }
    guard matches.count == 1, let button = matches.first else {
        throw ProbeError.failure("response action is missing or ambiguous: \(suffix)")
    }
    guard actionNames(button).contains(kAXPressAction as String) else {
        throw ProbeError.failure("response action has no AXPress action: \(suffix)")
    }
    _ = AXUIElementPerformAction(button, "AXScrollToVisible" as CFString)
    guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("response action could not be pressed: \(suffix)")
    }
    for _ in 1...maximumPolls {
        guard kill(pid, 0) == 0 else {
            throw ProbeError.failure("app exited while applying the response")
        }
        let after = try snapshot()
        try assertPrivacy(after)
        let status = after.elementsByIdentifier["today.prompt.action-status"]?
            .flatMap(labels)
            .joined(separator: "\n") ?? ""
        let waiting = after.identifiers.contains {
            $0.hasPrefix("today.prompt.") && $0.hasSuffix(".waiting")
        }
        let history = after.identifiers.contains {
            $0.hasPrefix("today.prompt.") && $0.hasSuffix(".history")
        }
        if status.contains(expectedStatus), !waiting, history { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeError.failure("visible success copy and resolved history did not appear after the response")
}

private func assertHistory(_ expectedChoice: String) throws {
    for _ in 1...maximumPolls {
        let current = try snapshot()
        try assertPrivacy(current)
        let text = combined(current.strings)
        let waiting = current.identifiers.contains {
            $0.hasPrefix("today.prompt.") && $0.hasSuffix(".waiting")
        }
        let historyCount = current.identifiers.filter {
            $0.hasPrefix("today.prompt.") && $0.hasSuffix(".history")
        }.count
        if !waiting, historyCount == 1, text.contains(expectedChoice), actionIdentifiers(current).isEmpty {
            return
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeError.failure("the resolved choice did not persist visibly after ordinary relaunch")
}

do {
    if phase == "window" {
        _ = try mainWindow()
        print("PASS: ZC-025-006 exactly one visible main window")
    } else if phase == "prompt" {
        _ = try waitForWaitingPrompt()
        print("PASS: ZC-025-006 one privacy-safe prompt exposes three accessible actions")
    } else if let suffix = expectedActionSuffix(for: phase),
              let status = expectedStatus(for: phase) {
        try chooseAction(suffix, expectedStatus: status)
        print("PASS: ZC-025-006 \(phase) exposed exact visible success copy")
    } else if let choice = expectedHistoryChoice(for: phase) {
        try assertHistory(choice)
        print("PASS: ZC-025-006 \(phase) persisted visibly without re-prompting")
    } else if phase == "absent" {
        let current = try snapshot()
        try assertPrivacy(current)
        let text = combined(current.strings)
        guard !text.contains("Did this support QA focus task?"),
              actionIdentifiers(current).allSatisfy({ identifier in
                  !actionSuffixes.contains(where: { identifier.hasSuffix(".action.\($0)") })
              })
        else {
            throw ProbeError.failure("an ambiguity confirmation appeared for an ineligible boundary fixture")
        }
        print("PASS: ZC-025-006 boundary fixture remains absent in Today")
    }
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
