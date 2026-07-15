#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let toggleIdentifier = "settings.gaming.advanced-limits.toggle"
private let contentIdentifier = "settings.gaming.advanced-limits.content"
private let coreIdentifiers = [
    "settings.gaming.budget-enabled",
    "settings.gaming.daily-budget",
    "settings.gaming.priority-reward",
    "settings.gaming.intentional-override",
]
private let advancedIdentifiers = [
    "settings.gaming.work-hours-maximum-enabled",
    "settings.gaming.work-hours-maximum",
    "settings.gaming.daily-prompt-cap",
    "settings.gaming.prompt-cooldown",
    "settings.gaming.task-start-grace",
    "settings.gaming.return-from-idle-grace",
]
private let maximumNodes = 6_000

private func matchesDisclosure(label: String, value: String, help: String, expanded: Bool) -> Bool {
    label == "Advanced Coaching Limits"
        && value == (expanded ? "Expanded" : "Collapsed")
        && help == (expanded
            ? "Hide advanced gaming coaching limits"
            : "Show advanced gaming coaching limits")
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard coreIdentifiers.count == 4,
          advancedIdentifiers.count == 6,
          Set(coreIdentifiers).isDisjoint(with: Set(advancedIdentifiers)),
          matchesDisclosure(
            label: "Advanced Coaching Limits",
            value: "Collapsed",
            help: "Show advanced gaming coaching limits",
            expanded: false
          ), matchesDisclosure(
            label: "Advanced Coaching Limits",
            value: "Expanded",
            help: "Hide advanced gaming coaching limits",
            expanded: true
          ), !matchesDisclosure(
            label: "Advanced Coaching Limits",
            value: "Collapsed",
            help: "Hide advanced gaming coaching limits",
            expanded: false
          ) else {
        fputs("FAIL: ZC-056-009 AX self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-056-009 AX self-test rejects stale disclosure state and mixed control groups")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case statusItemUnavailable
    case settingsDidNotOpen
    case missing(String)
    case contract(String)

    var description: String {
        switch self {
        case .invalidArguments: "usage: probe --pid PID"
        case .accessibilityPermission: "Accessibility permission is required."
        case .processUnavailable: "The exact app process is unavailable."
        case .statusItemUnavailable: "The signed app status item is unavailable or ambiguous."
        case .settingsDidNotOpen: "Settings did not open through the app's menu-bar action."
        case let .missing(identifier): "Missing accessibility element: \(identifier)"
        case let .contract(message): message
        }
    }
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String {
    attribute(element, name) as? String ?? ""
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func elements(from root: AXUIElement) throws -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        result.append(element)
        guard result.count <= maximumNodes else {
            throw ProbeError.contract("Accessibility tree exceeded the traversal limit.")
        }
        queue.append(contentsOf: children(element))
    }
    return result
}

private func find(_ identifier: String, in root: AXUIElement) throws -> AXUIElement? {
    try elements(from: root).first {
        string($0, kAXIdentifierAttribute as CFString) == identifier
    }
}

private func waitFor(_ identifier: String, in root: AXUIElement, timeout: TimeInterval = 8) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = try find(identifier, in: root) { return element }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

private func waitUntilAbsent(_ identifiers: [String], in root: AXUIElement, timeout: TimeInterval = 8) throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let visible = try identifiers.contains { try find($0, in: root) != nil }
        if !visible { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
}

private func openSettings(application: AXUIElement) throws {
    if try waitFor(toggleIdentifier, in: application, timeout: 0.2) != nil { return }
    guard let rawExtras = attribute(application, kAXExtrasMenuBarAttribute as CFString),
          CFGetTypeID(rawExtras) == AXUIElementGetTypeID()
    else { throw ProbeError.statusItemUnavailable }
    let extras = unsafeBitCast(rawExtras, to: AXUIElement.self)
    let items = try elements(from: extras).filter {
        string($0, kAXRoleAttribute as CFString) == "AXMenuBarItem"
    }
    guard items.count == 1,
          AXUIElementPerformAction(items[0], kAXPressAction as CFString) == .success
    else { throw ProbeError.statusItemUnavailable }
    guard let settings = try waitFor("menu-bar.open-settings", in: application),
          AXUIElementPerformAction(settings, kAXPressAction as CFString) == .success,
          try waitFor(toggleIdentifier, in: application) != nil
    else { throw ProbeError.settingsDidNotOpen }
}

private func require(_ identifiers: [String], in application: AXUIElement) throws {
    for identifier in identifiers where try waitFor(identifier, in: application, timeout: 1) == nil {
        throw ProbeError.missing(identifier)
    }
}

private func assertToggle(_ toggle: AXUIElement, expanded: Bool) throws {
    let label = string(toggle, kAXDescriptionAttribute as CFString)
    let value = string(toggle, kAXValueAttribute as CFString)
    let help = string(toggle, kAXHelpAttribute as CFString)
    guard matchesDisclosure(label: label, value: value, help: help, expanded: expanded) else {
        throw ProbeError.contract("Disclosure mismatch: label=\(label) value=\(value) help=\(help)")
    }
}

private func run() throws {
    guard CommandLine.arguments.count == 3,
          CommandLine.arguments[1] == "--pid",
          let pid = pid_t(CommandLine.arguments[2]),
          pid > 0
    else { throw ProbeError.invalidArguments }
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    guard kill(pid, 0) == 0 else { throw ProbeError.processUnavailable }
    let application = AXUIElementCreateApplication(pid)
    try openSettings(application: application)
    guard let collapsedToggle = try waitFor(toggleIdentifier, in: application) else {
        throw ProbeError.missing(toggleIdentifier)
    }
    try assertToggle(collapsedToggle, expanded: false)
    try require(coreIdentifiers, in: application)
    guard try waitUntilAbsent([contentIdentifier] + advancedIdentifiers, in: application, timeout: 0.2) else {
        throw ProbeError.contract("Advanced controls are exposed while collapsed.")
    }

    guard AXUIElementPerformAction(collapsedToggle, kAXPressAction as CFString) == .success,
          let expandedToggle = try waitFor(toggleIdentifier, in: application)
    else { throw ProbeError.contract("Advanced limits could not be expanded.") }
    try assertToggle(expandedToggle, expanded: true)
    try require([contentIdentifier] + advancedIdentifiers, in: application)
    try require(coreIdentifiers, in: application)

    guard AXUIElementPerformAction(expandedToggle, kAXPressAction as CFString) == .success,
          let finalToggle = try waitFor(toggleIdentifier, in: application)
    else { throw ProbeError.contract("Advanced limits could not be collapsed.") }
    try assertToggle(finalToggle, expanded: false)
    guard try waitUntilAbsent([contentIdentifier] + advancedIdentifiers, in: application) else {
        throw ProbeError.contract("Advanced controls remained exposed after collapse.")
    }
    print("PASS: ZC-056-009 core gaming allowance stays visible while advanced tuning is disclosed on demand")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
