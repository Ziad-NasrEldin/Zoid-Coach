#!/usr/bin/env swift

import AppKit
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

private struct MenuItemSnapshot {
    let title: String
    let enabled: Bool
    let commandCharacter: String?
    let virtualKey: Int?
    let modifiers: Int?
}

private struct MenuItemExpectation: Equatable {
    let title: String
    let enabled: Bool
    let commandCharacter: String?
    let virtualKey: Int?
}

private struct PhaseExpectation: Equatable {
    let items: [MenuItemExpectation]
}

private let primaryTitle = "QA keyboard lifecycle primary"
private let targetTitle = "QA keyboard lifecycle switch target"
private let mainWindowIdentifier = "zoid-666.main-window"
private let requiredModifiers = 2
private let maximumNodes = 6_000
private let maximumPolls = 80

private let keyCodes = [
    "start": CGKeyCode(1),
    "pause": CGKeyCode(35),
    "resume": CGKeyCode(35),
    "switch": CGKeyCode(40),
    "complete": CGKeyCode(36),
]

private func selectMainWindow(from windows: [WindowTraits]) -> MainSelection {
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

private func item(
    _ title: String,
    enabled: Bool,
    character: String? = nil,
    virtualKey: Int? = nil
) -> MenuItemExpectation {
    MenuItemExpectation(
        title: title,
        enabled: enabled,
        commandCharacter: character,
        virtualKey: virtualKey
    )
}

private func expectation(for phase: String) -> PhaseExpectation? {
    switch phase {
    case "ready":
        PhaseExpectation(items: [
            item("Start Recommended Task: \(primaryTitle)", enabled: true, character: "s"),
            item("Pause or Resume Current Task", enabled: false, character: "p"),
            item("Switch to Recommended Task", enabled: false, character: "k"),
            item("Complete Current Task", enabled: false, virtualKey: 36),
        ])
    case "active-primary":
        PhaseExpectation(items: [
            item("Start Recommended Task", enabled: false, character: "s"),
            item("Pause Current Task: \(primaryTitle)", enabled: true, character: "p"),
            item("Switch from \(primaryTitle) to \(targetTitle) and Preserve Time", enabled: true, character: "k"),
            item("Complete Task: \(primaryTitle)", enabled: true, virtualKey: 36),
        ])
    case "paused-primary", "primary-paused":
        PhaseExpectation(items: [
            item("Start Recommended Task", enabled: false, character: "s"),
            item("Resume Paused Task: \(primaryTitle)", enabled: true, character: "p"),
            item("Switch to Recommended Task", enabled: false, character: "k"),
            item("Complete Task: \(primaryTitle)", enabled: true, virtualKey: 36),
        ])
    case "switched-target":
        PhaseExpectation(items: [
            item("Start Recommended Task", enabled: false, character: "s"),
            item("Pause Current Task: \(targetTitle)", enabled: true, character: "p"),
            item("Switch to Recommended Task", enabled: false, character: "k"),
            item("Complete Task: \(targetTitle)", enabled: true, virtualKey: 36),
        ])
    case "ambiguous", "no-active":
        PhaseExpectation(items: [
            item("Start Recommended Task", enabled: false, character: "s"),
            item("Pause or Resume Current Task", enabled: false, character: "p"),
            item("Switch to Recommended Task", enabled: false, character: "k"),
            item("Complete Current Task", enabled: false, virtualKey: 36),
        ])
    default:
        nil
    }
}

private func successorPhase(from phase: String, action: String) -> String? {
    switch (phase, action) {
    case ("ready", "start"): "active-primary"
    case ("active-primary", "pause"): "paused-primary"
    case ("paused-primary", "resume"): "active-primary"
    case ("active-primary", "switch"): "switched-target"
    case ("switched-target", "complete"): "primary-paused"
    case ("primary-paused", "complete"): "no-active"
    case ("ambiguous", "pause"), ("ambiguous", "complete"): "ambiguous"
    case ("no-active", "complete"): "no-active"
    default: nil
    }
}

private func containsForbidden(_ strings: [String], forbidden: [String]) -> Bool {
    strings.contains { value in
        forbidden.contains { sentinel in
            value.localizedCaseInsensitiveContains(sentinel)
        }
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
    let fallback = WindowTraits(
        identifier: nil,
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
    guard selectMainWindow(from: [main, auxiliary]) == .selected(0),
          selectMainWindow(from: [auxiliary, fallback]) == .selected(1),
          selectMainWindow(from: [main, fallback]) == .ambiguous,
          expectation(for: "ready")?.items.first?.title == "Start Recommended Task: \(primaryTitle)",
          expectation(for: "active-primary")?.items[2].enabled == true,
          expectation(for: "ambiguous")?.items.allSatisfy({ !$0.enabled }) == true,
          expectation(for: "no-active")?.items.allSatisfy({ !$0.enabled }) == true,
          successorPhase(from: "ready", action: "start") == "active-primary",
          successorPhase(from: "active-primary", action: "switch") == "switched-target",
          successorPhase(from: "ambiguous", action: "complete") == "ambiguous",
          successorPhase(from: "ready", action: "complete") == nil,
          keyCodes["start"] == 1,
          keyCodes["pause"] == 35,
          keyCodes["switch"] == 40,
          keyCodes["complete"] == 36,
          containsForbidden(["private QA-ZC055003-private-note"], forbidden: ["qa-zc055003-private-note"]),
          !containsForbidden(["Complete Task: QA keyboard lifecycle primary"], forbidden: ["qa-zc055003-private-note"])
    else {
        fputs("FAIL: ZC-055-003 keyboard AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-055-003 keyboard AX probe self-test")
    exit(0)
}

private var pid: pid_t?
private var phase: String?
private var action: String?
private var forbidden: [String] = []
private var index = 1
private let arguments = CommandLine.arguments
while index < arguments.count {
    switch arguments[index] {
    case "--pid":
        guard index + 1 < arguments.count, let value = Int32(arguments[index + 1]) else {
            fputs("FAIL: --pid requires a numeric process ID\n", stderr)
            exit(2)
        }
        pid = value
        index += 2
    case "--phase":
        guard index + 1 < arguments.count else {
            fputs("FAIL: --phase requires a value\n", stderr)
            exit(2)
        }
        phase = arguments[index + 1]
        index += 2
    case "--send":
        guard index + 1 < arguments.count else {
            fputs("FAIL: --send requires a value\n", stderr)
            exit(2)
        }
        action = arguments[index + 1]
        index += 2
    case "--forbid":
        guard index + 1 < arguments.count else {
            fputs("FAIL: --forbid requires a value\n", stderr)
            exit(2)
        }
        forbidden.append(arguments[index + 1])
        index += 2
    default:
        fputs("FAIL: unsupported argument \(arguments[index])\n", stderr)
        exit(2)
    }
}

guard let pid,
      let phase,
      let initialExpectation = expectation(for: phase)
else {
    fputs("usage: qa-zc055003-keyboard-lifecycle-ax-probe.swift --self-test | --pid <pid> --phase <ready|active-primary|paused-primary|switched-target|primary-paused|ambiguous|no-active> [--send <start|pause|resume|switch|complete>] [--forbid <sentinel>]...\n", stderr)
    exit(2)
}

if let action, successorPhase(from: phase, action: action) == nil {
    fputs("FAIL: action \(action) is invalid from phase \(phase)\n", stderr)
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

private func integer(_ element: AXUIElement, _ name: CFString) -> Int? {
    (attribute(element, name) as? NSNumber)?.intValue
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
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

private func walk(root: AXUIElement, visit: (AXUIElement) -> Void) throws {
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
        visit(element)
        queue.append(contentsOf: children(element))
    }
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("Accessibility permission is required for the verifier")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeError.failure("the supplied installed-app process is not running")
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
    switch selectMainWindow(from: traits) {
    case let .selected(selected): return windows[selected]
    case .missing: throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}

private func menuItems() throws -> [MenuItemSnapshot] {
    guard let menuBarValue = attribute(application, kAXMenuBarAttribute as CFString) else {
        throw ProbeError.failure("installed app menu bar is unavailable")
    }
    let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
    var items: [MenuItemSnapshot] = []
    try walk(root: menuBar) { element in
        guard role(element) == (kAXMenuItemRole as String),
              let title = string(element, kAXTitleAttribute as CFString),
              !title.isEmpty
        else { return }
        items.append(MenuItemSnapshot(
            title: title,
            enabled: bool(element, kAXEnabledAttribute as CFString) == true,
            commandCharacter: string(element, kAXMenuItemCmdCharAttribute as CFString),
            virtualKey: integer(element, kAXMenuItemCmdVirtualKeyAttribute as CFString),
            modifiers: integer(element, kAXMenuItemCmdModifiersAttribute as CFString)
        ))
    }
    return items
}

private func exposedStrings() throws -> [String] {
    let window = try mainWindow()
    var strings: [String] = []
    try walk(root: window) { strings.append(contentsOf: labels($0)) }
    let menu = try menuItems()
    strings.append(contentsOf: menu.map(\.title))
    return strings
}

private func assertMenu(_ expected: PhaseExpectation) throws {
    let actual = try menuItems()
    for itemExpectation in expected.items {
        let matches = actual.filter { $0.title == itemExpectation.title }
        guard matches.count == 1, let match = matches.first else {
            throw ProbeError.failure("expected exactly one Task menu item named '\(itemExpectation.title)', found \(matches.count)")
        }
        guard match.enabled == itemExpectation.enabled else {
            throw ProbeError.failure("Task menu item '\(itemExpectation.title)' enabled state was \(match.enabled), expected \(itemExpectation.enabled)")
        }
        guard match.modifiers == requiredModifiers else {
            throw ProbeError.failure("Task menu item '\(itemExpectation.title)' does not expose exact Command-Option modifiers")
        }
        if let expectedCharacter = itemExpectation.commandCharacter {
            guard match.commandCharacter?.lowercased() == expectedCharacter else {
                throw ProbeError.failure("Task menu item '\(itemExpectation.title)' has the wrong shortcut character")
            }
        }
        if let expectedVirtualKey = itemExpectation.virtualKey {
            guard match.virtualKey == expectedVirtualKey else {
                throw ProbeError.failure("Task menu item '\(itemExpectation.title)' has the wrong virtual key")
            }
        }
    }
    let shortcutItems = actual.filter { candidate in
        expected.items.contains(where: { $0.title == candidate.title })
    }
    guard shortcutItems.count == 4 else {
        throw ProbeError.failure("Task menu does not expose exactly four lifecycle shortcut items")
    }
}

private func assertPhase(_ expected: PhaseExpectation) throws {
    try assertMenu(expected)
    let exposed = try exposedStrings()
    if containsForbidden(exposed, forbidden: forbidden) {
        throw ProbeError.failure("private fixture, database, or QA-root evidence escaped into the accessibility tree")
    }
}

private func postKeyboardChord(action: String) throws {
    guard let keyCode = keyCodes[action] else {
        throw ProbeError.failure("unsupported keyboard action: \(action)")
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        throw ProbeError.failure("installed Zoid 666 app is not frontmost before keyboard injection")
    }
    guard CGPreflightPostEventAccess() else {
        throw ProbeError.failure("the verifier does not have permission to post a physical keyboard chord")
    }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
        throw ProbeError.failure("unable to construct the keyboard chord")
    }
    keyDown.flags = [.maskCommand, .maskAlternate]
    keyUp.flags = [.maskCommand, .maskAlternate]
    keyDown.post(tap: .cghidEventTap)
    usleep(70_000)
    keyUp.post(tap: .cghidEventTap)
}

do {
    try assertPhase(initialExpectation)
    if let action,
       let successor = successorPhase(from: phase, action: action),
       let successorExpectation = expectation(for: successor) {
        try postKeyboardChord(action: action)
        var latestError: Error?
        var passed = false
        for _ in 0..<maximumPolls {
            do {
                try assertPhase(successorExpectation)
                passed = true
                break
            } catch {
                latestError = error
                usleep(150_000)
            }
        }
        guard passed else {
            throw latestError ?? ProbeError.failure("keyboard action did not reach its expected successor state")
        }
        print("PASS: physical Command-Option keyboard action \(action) moved \(phase) to \(successor)")
    } else {
        print("PASS: Task menu labels, shortcut discoverability, enabled states, main-window uniqueness, and privacy passed for \(phase)")
    }
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
