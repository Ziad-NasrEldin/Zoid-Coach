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
    "qa-zc061005-private-tutorial-secret",
    "qa-zc061005.private.invalid",
]
private let strongDriftWording = [
    "Is this gaming intentional?",
    "Ready for an easy return?",
    "Your five minutes are up",
]
private let ambiguityActionSuffixes = [
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

private func combined(_ strings: [String]) -> String {
    strings.joined(separator: "\n")
}

private func containsPrivateEvidence(_ strings: [String]) -> Bool {
    strings.contains { value in
        privateSentinels.contains { value.localizedCaseInsensitiveContains($0) }
    }
}

private func containsStrongDriftWording(_ strings: [String]) -> Bool {
    let text = combined(strings)
    return strongDriftWording.contains { text.localizedCaseInsensitiveContains($0) }
}

private func provesScopedConfirmation(strings: [String], identifiers: [String]) -> Bool {
    let text = combined(strings)
    let actions = identifiers.filter {
        $0.hasPrefix("today.prompt.") && $0.contains(".action.")
    }
    let waiting = identifiers.filter {
        $0.hasPrefix("today.prompt.") && $0.hasSuffix(".waiting")
    }
    return text.contains("Did this support QA ZC-061-005 technical task?")
        && text.contains("about 10 minutes in Safari")
        && text.contains("cannot show your intent")
        && ambiguityActionSuffixes.allSatisfy { suffix in
            actions.contains { $0.hasSuffix(".action.\(suffix)") }
        }
        && actions.count == 3
        && waiting.count == 1
        && !text.localizedCaseInsensitiveContains("research")
        && !containsStrongDriftWording(strings)
        && !containsPrivateEvidence(strings)
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
    let identifiers = [
        "today.prompt.ambiguity.waiting",
        "today.prompt.ambiguity.action.classify_as_supporting_work",
        "today.prompt.ambiguity.action.classify_as_gaming",
        "today.prompt.ambiguity.action.keep_activity_unknown",
    ]
    let safe = [
        "Did this support QA ZC-061-005 technical task?",
        "Zoid 666 observed about 10 minutes in Safari.",
        "Application and duration alone cannot show your intent.",
    ]
    guard selectMain([main, auxiliary]) == .selected(0),
          selectMain([auxiliary, fallback]) == .selected(1),
          selectMain([main, fallback]) == .ambiguous,
          provesScopedConfirmation(strings: safe, identifiers: identifiers),
          !provesScopedConfirmation(
              strings: safe + ["Is this gaming intentional?"],
              identifiers: identifiers
          ),
          containsPrivateEvidence(["qa-zc061005-private-tutorial-secret"]),
          containsStrongDriftWording(["Your five minutes are up"])
    else {
        fputs("FAIL: ZC-061-005 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-061-005 AX probe self-test")
    exit(0)
}

let arguments = CommandLine.arguments
guard arguments.count == 5,
      arguments[1] == "--pid",
      let pid = Int32(arguments[2]),
      arguments[3] == "--phase",
      ["confirmation", "absent"].contains(arguments[4])
else {
    fputs("usage: qa-zc061005-insufficient-evidence-ax-probe.swift --self-test | --pid <pid> --phase <confirmation|absent>\n", stderr)
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

private func refresh(_ snapshot: Snapshot) {
    guard let buttons = snapshot.elementsByIdentifier["today.prompt-inbox.refresh"],
          buttons.count == 1,
          let button = buttons.first,
          actionNames(button).contains(kAXPressAction as String)
    else { return }
    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
}

private func assertGlobalSafety(_ snapshot: Snapshot) throws {
    if containsPrivateEvidence(snapshot.strings) {
        throw ProbeError.failure("private tutorial title or URL escaped into Today")
    }
    if containsStrongDriftWording(snapshot.strings) {
        throw ProbeError.failure("strong gaming-drift wording remains visible")
    }
    if combined(snapshot.strings).localizedCaseInsensitiveContains("research") {
        throw ProbeError.failure("the uncertain session was incorrectly labeled Research")
    }
}

do {
    if phase == "confirmation" {
        for poll in 1...maximumPolls {
            let current = try snapshot()
            try assertGlobalSafety(current)
            if provesScopedConfirmation(
                strings: current.strings,
                identifiers: current.identifiers
            ) {
                print("PASS: one privacy-safe ambiguity confirmation is visible with no strong drift wording")
                exit(0)
            }
            if poll == 10 || poll == 30 { refresh(current) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ProbeError.failure("timed out waiting for the scoped ambiguity confirmation")
    }

    let current = try snapshot()
    try assertGlobalSafety(current)
    let text = combined(current.strings)
    let ambiguityActions = current.identifiers.filter { identifier in
        identifier.hasPrefix("today.prompt.")
            && ambiguityActionSuffixes.contains { suffix in
                identifier.hasSuffix(".action.\(suffix)")
            }
    }
    guard !text.contains("Did this support QA ZC-061-005 technical task?"), ambiguityActions.isEmpty else {
        throw ProbeError.failure("an ambiguity confirmation appeared for an ineligible boundary")
    }
    print("PASS: ineligible uncertainty remains quiet with no strong drift prompt")
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
