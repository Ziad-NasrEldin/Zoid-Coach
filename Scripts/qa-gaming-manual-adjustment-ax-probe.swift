import ApplicationServices
import Foundation

private struct ProbeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func descendants(_ root: AXUIElement, maximumDepth: Int = 16) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    while !queue.isEmpty {
        let (element, depth) = queue.removeFirst()
        guard depth < maximumDepth else { continue }
        let children = (attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? []
        result.append(contentsOf: children)
        queue.append(contentsOf: children.map { ($0, depth + 1) })
    }
    return result
}

private func first(identifier: String, in root: AXUIElement) -> AXUIElement? {
    descendants(root).first { string($0, kAXIdentifierAttribute as CFString) == identifier }
}

private func waitFor(identifier: String, in root: AXUIElement, timeout: TimeInterval = 5) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = first(identifier: identifier, in: root) { return element }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

private func window(pid: pid_t) throws -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    let deadline = Date().addingTimeInterval(5)
    repeat {
        if let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement],
           let first = windows.first {
            return first
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw ProbeFailure(message: "The signed QA app window is unavailable.")
}

private func press(_ element: AXUIElement, name: String) throws {
    guard bool(element, kAXEnabledAttribute as CFString) != false else {
        throw ProbeFailure(message: "The required control is disabled: \(name)")
    }
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeFailure(message: "Could not press: \(name)")
    }
}

private func setValue(_ value: String, on element: AXUIElement, name: String) throws {
    guard AXUIElementSetAttributeValue(
        element,
        kAXValueAttribute as CFString,
        value as CFTypeRef
    ) == .success else {
        throw ProbeFailure(message: "Could not set: \(name)")
    }
}

private let rejection = "Today or its time zone changed. Review the refreshed allowance before saving this adjustment."
private let unavailable = "Manual allowance history is unavailable. Refresh Today after checking Agent source health."

do {
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw ProbeFailure(message: "Usage: qa-gaming-manual-adjustment-ax-probe <pid> <open|submit|assert-rejection|assert-ledger-unavailable>")
    }
    let root = try window(pid: pid)
    switch CommandLine.arguments[2] {
    case "open":
        guard let button = waitFor(identifier: "today.gaming.manual-adjustment.open", in: root) else {
            throw ProbeFailure(message: "The manual adjustment control is unavailable.")
        }
        try press(button, name: "Adjust gaming time")
        guard waitFor(identifier: "today.gaming.manual-adjustment.save", in: root) != nil else {
            throw ProbeFailure(message: "The manual adjustment sheet did not open.")
        }
        print("PASS: the signed manual adjustment sheet is open.")
    case "submit":
        guard let note = waitFor(identifier: "today.gaming.manual-adjustment.note", in: root),
              let save = waitFor(identifier: "today.gaming.manual-adjustment.save", in: root) else {
            throw ProbeFailure(message: "The manual adjustment form is incomplete.")
        }
        try setValue("qa-zc030011-manual-grant", on: note, name: "Adjustment note")
        try press(save, name: "Add time")
        print("PASS: submitted the signed manual adjustment form.")
    case "assert-rejection":
        guard let error = waitFor(identifier: "today.gaming.manual-adjustment.error", in: root),
              string(error, kAXValueAttribute as CFString) == rejection else {
            throw ProbeFailure(message: "The stale Today/time-zone rejection is not visibly present.")
        }
        print("PASS: the signed app visibly rejected stale adjustment state and requested a refresh.")
    case "assert-ledger-unavailable":
        guard let message = waitFor(identifier: "today.gaming.manual-adjustment.unavailable", in: root),
              string(message, kAXValueAttribute as CFString) == unavailable,
              let button = waitFor(identifier: "today.gaming.manual-adjustment.open", in: root),
              bool(button, kAXEnabledAttribute as CFString) == false else {
            throw ProbeFailure(message: "The unavailable-ledger disclosure or disabled adjustment control is missing.")
        }
        print("PASS: unavailable ledger state is visible and adjustment saving is disabled.")
    default:
        throw ProbeFailure(message: "Unknown probe command: \(CommandLine.arguments[2])")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
