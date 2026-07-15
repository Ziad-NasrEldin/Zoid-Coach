#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let openIdentifier = "today.behavior-evidence.open"
private let sheetIdentifier = "today.behavior-evidence.sheet"
private let boundaryIdentifier = "today.behavior-evidence.coaching-boundary"
private let closeIdentifier = "today.behavior-evidence.close"
private let maximumNodes = 6_000
private let policyDetail = "Strong gaming coaching also requires fresh, sustained, confident gaming and unfinished priority work."

private struct ExpectedContract {
    let title: String
    let requiredDetail: String
}

private let contracts = [
    "Limited evidence": ExpectedContract(
        title: "COACHING HOLDS WHEN EVIDENCE IS LIMITED",
        requiredDetail: "does not use stale or missing activity as strong drift evidence"
    ),
    "Unknown evidence excluded": ExpectedContract(
        title: "UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING",
        requiredDetail: "Unknown time stays out of work, gaming, and distraction"
    ),
    "Current evidence boundary": ExpectedContract(
        title: "CLASSIFICATION IS NOT INTENT",
        requiredDetail: "an app name alone does not prove why you used it"
    ),
]

private func matchesBoundary(label: String, value: String) -> Bool {
    guard let contract = contracts[value] else { return false }
    return label.contains(contract.title)
        && label.contains(contract.requiredDetail)
        && label.contains(policyDetail)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let limited = "COACHING HOLDS WHEN EVIDENCE IS LIMITED. Zoid 666 does not use stale or missing activity as strong drift evidence. Restore Source Health before trusting today's behavior picture. \(policyDetail)"
    let unknown = "UNKNOWN TIME DOES NOT TRIGGER STRONG COACHING. Unknown time stays out of work, gaming, and distraction. Review it if you know what happened; Zoid 666 does not guess. \(policyDetail)"
    let current = "CLASSIFICATION IS NOT INTENT. Fresh classifications can support coaching, but an app name alone does not prove why you used it or whether it supported the active task. \(policyDetail)"
    guard matchesBoundary(label: limited, value: "Limited evidence"),
          matchesBoundary(label: unknown, value: "Unknown evidence excluded"),
          matchesBoundary(label: current, value: "Current evidence boundary"),
          !matchesBoundary(label: limited, value: "Unknown evidence excluded"),
          !matchesBoundary(label: current.replacingOccurrences(of: policyDetail, with: ""), value: "Current evidence boundary"),
          !matchesBoundary(label: current, value: "Stale") else {
        fputs("FAIL: ZC-058-007 AX matcher self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-058-007 AX matcher distinguishes all evidence boundaries and requires policy context")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case missing(String)
    case contract(String)

    var description: String {
        switch self {
        case .invalidArguments: "usage: probe --pid PID"
        case .accessibilityPermission: "Accessibility permission is required."
        case .processUnavailable: "The exact app process is unavailable."
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

private func waitFor(_ identifier: String, in root: AXUIElement, timeout: TimeInterval = 10) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = try find(identifier, in: root) { return element }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

private func waitUntilAbsent(_ identifier: String, in root: AXUIElement, timeout: TimeInterval = 8) throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if try find(identifier, in: root) == nil { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
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
    guard let open = try waitFor(openIdentifier, in: application) else {
        throw ProbeError.missing(openIdentifier)
    }
    guard AXUIElementPerformAction(open, kAXPressAction as CFString) == .success,
          try waitFor(sheetIdentifier, in: application) != nil,
          let boundary = try waitFor(boundaryIdentifier, in: application)
    else { throw ProbeError.missing(boundaryIdentifier) }

    let label = string(boundary, kAXDescriptionAttribute as CFString)
    let value = string(boundary, kAXValueAttribute as CFString)
    guard matchesBoundary(label: label, value: value) else {
        throw ProbeError.contract("Evidence boundary mismatch: label=\(label) value=\(value)")
    }

    guard let close = try waitFor(closeIdentifier, in: application),
          AXUIElementPerformAction(close, kAXPressAction as CFString) == .success,
          try waitUntilAbsent(sheetIdentifier, in: application)
    else { throw ProbeError.contract("Behavior Evidence did not close cleanly.") }
    print("PASS: ZC-058-007 signed Behavior Evidence exposes a truthful coaching boundary state")
    print("BOUNDARY_VALUE=\(value)")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
