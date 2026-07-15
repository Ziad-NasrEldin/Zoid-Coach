#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let toggleIdentifier = "menu-bar.voice-controls.toggle"
private let contentIdentifier = "menu-bar.voice-controls.content"
private let maximumNodes = 4_000

private func matchesDisclosure(
    label: String,
    value: String,
    help: String,
    expanded: Bool
) -> Bool {
    label == "Voice controls"
        && value == (expanded ? "Expanded" : "Collapsed")
        && help == (expanded ? "Collapse voice controls" : "Expand voice controls")
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard matchesDisclosure(
        label: "Voice controls",
        value: "Collapsed",
        help: "Expand voice controls",
        expanded: false
    ), matchesDisclosure(
        label: "Voice controls",
        value: "Expanded",
        help: "Collapse voice controls",
        expanded: true
    ), !matchesDisclosure(
        label: "Voice controls",
        value: "Collapsed",
        help: "Collapse voice controls",
        expanded: false
    ), !matchesDisclosure(
        label: "Voice controls",
        value: "Expanded",
        help: "Expand voice controls",
        expanded: false
    ) else {
        fputs("FAIL: ZC-056-007 AX matcher self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-056-007 AX matcher rejects stale values and inverted actions")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case statusItemUnavailable
    case statusItemDidNotOpen
    case missingToggle
    case contract(String)

    var description: String {
        switch self {
        case .invalidArguments: "usage: probe --pid PID"
        case .accessibilityPermission: "Accessibility permission is required."
        case .processUnavailable: "The exact app process is unavailable."
        case .statusItemUnavailable: "The signed app status item is unavailable or ambiguous."
        case .statusItemDidNotOpen: "The general task menu did not open."
        case .missingToggle: "The Voice controls toggle is unavailable."
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

private func matches(_ element: AXUIElement, identifier: String) -> Bool {
    string(element, kAXIdentifierAttribute as CFString) == identifier
}

private func waitForElement(
    in root: AXUIElement,
    identifier: String,
    timeout: TimeInterval = 8
) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let found = try elements(from: root).first { matches($0, identifier: identifier) }
        if let found { return found }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

private func waitUntilAbsent(
    in root: AXUIElement,
    identifier: String,
    timeout: TimeInterval = 8
) throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let found = try elements(from: root).contains { matches($0, identifier: identifier) }
        if !found { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
}

private func openMenu(application: AXUIElement) throws {
    if try waitForElement(in: application, identifier: toggleIdentifier, timeout: 0.2) != nil {
        return
    }
    guard let rawExtras = attribute(application, kAXExtrasMenuBarAttribute as CFString),
          CFGetTypeID(rawExtras) == AXUIElementGetTypeID()
    else { throw ProbeError.statusItemUnavailable }
    let extras = unsafeBitCast(rawExtras, to: AXUIElement.self)
    let items = try elements(from: extras).filter {
        string($0, kAXRoleAttribute as CFString) == "AXMenuBarItem"
    }
    guard items.count == 1 else { throw ProbeError.statusItemUnavailable }
    guard AXUIElementPerformAction(items[0], kAXPressAction as CFString) == .success else {
        throw ProbeError.statusItemUnavailable
    }
    guard try waitForElement(in: application, identifier: toggleIdentifier) != nil else {
        throw ProbeError.statusItemDidNotOpen
    }
}

private func assertToggle(_ toggle: AXUIElement, expanded: Bool) throws {
    let label = string(toggle, kAXDescriptionAttribute as CFString)
    let value = string(toggle, kAXValueAttribute as CFString)
    let help = string(toggle, kAXHelpAttribute as CFString)
    guard matchesDisclosure(label: label, value: value, help: help, expanded: expanded) else {
        throw ProbeError.contract("Voice disclosure mismatch: label=\(label) value=\(value) help=\(help)")
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
    try openMenu(application: application)
    guard let toggle = try waitForElement(
        in: application,
        identifier: toggleIdentifier
    ) else { throw ProbeError.missingToggle }

    try assertToggle(toggle, expanded: false)
    guard try waitUntilAbsent(
        in: application,
        identifier: contentIdentifier,
        timeout: 0.2
    ) else { throw ProbeError.contract("Voice content is exposed while collapsed.") }

    guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success else {
        throw ProbeError.contract("Voice disclosure could not be expanded.")
    }
    guard let expandedToggle = try waitForElement(
        in: application,
        identifier: toggleIdentifier
    ) else { throw ProbeError.missingToggle }
    try assertToggle(expandedToggle, expanded: true)
    guard try waitForElement(in: application, identifier: contentIdentifier) != nil else {
        throw ProbeError.contract("Voice content is not exposed while expanded.")
    }

    guard AXUIElementPerformAction(expandedToggle, kAXPressAction as CFString) == .success else {
        throw ProbeError.contract("Voice disclosure could not be collapsed.")
    }
    guard let collapsedToggle = try waitForElement(
        in: application,
        identifier: toggleIdentifier
    ) else { throw ProbeError.missingToggle }
    try assertToggle(collapsedToggle, expanded: false)
    guard try waitUntilAbsent(in: application, identifier: contentIdentifier) else {
        throw ProbeError.contract("Voice content remained exposed after collapse.")
    }
    print("PASS: ZC-056-007 signed menu disclosure is Sumi-structured and state truthful")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
