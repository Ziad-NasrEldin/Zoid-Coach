#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let statusIdentifier = "today.prompt.action-status"
private let expectedStatus = "Intentional gaming recorded. Equivalent gaming prompts are paused for your configured override window. Returning to aligned work ends the pause early."
private let maximumNodes = 4_000

private func matchesStatus(_ value: String) -> Bool {
    value == expectedStatus && value.rangeOfCharacter(from: .decimalDigits) == nil
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard matchesStatus(expectedStatus),
          !matchesStatus("Equivalent gaming prompts are paused for 45 minutes."),
          !matchesStatus("Intentional gaming recorded."),
          !matchesStatus("Equivalent gaming prompts are paused indefinitely.")
    else {
        fputs("FAIL: ZC-060-004 AX matcher self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-060-004 AX matcher rejects invented countdowns and incomplete feedback")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case missingAction(String)
    case actionFailed
    case promptStayedOpen(String)
    case missingStatus
    case contract(String)

    var description: String {
        switch self {
        case .invalidArguments: "usage: probe --pid PID --prompt-id PROMPT_ID"
        case .accessibilityPermission: "Accessibility permission is required."
        case .processUnavailable: "The exact app process is unavailable."
        case let .missingAction(identifier): "Continue intentionally action is unavailable: \(identifier)"
        case .actionFailed: "Continue intentionally could not be applied."
        case let .promptStayedOpen(identifier): "Resolved prompt remained open: \(identifier)"
        case .missingStatus: "Intentional override status is unavailable."
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

private func find(
    in root: AXUIElement,
    identifier: String,
    timeout: TimeInterval = 8
) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let found = try elements(from: root).first(where: {
            string($0, kAXIdentifierAttribute as CFString) == identifier
        }) { return found }
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
        if try elements(from: root).allSatisfy({
            string($0, kAXIdentifierAttribute as CFString) != identifier
        }) { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
}

private func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 5,
          arguments[1] == "--pid",
          let pid = pid_t(arguments[2]),
          pid > 0,
          arguments[3] == "--prompt-id",
          !arguments[4].isEmpty
    else { throw ProbeError.invalidArguments }
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    guard kill(pid, 0) == 0 else { throw ProbeError.processUnavailable }

    let promptID = arguments[4]
    let actionIdentifier = "today.prompt.\(promptID).action.continue_intentionally"
    let waitingIdentifier = "today.prompt.\(promptID).waiting"
    let application = AXUIElementCreateApplication(pid)
    guard let action = try find(in: application, identifier: actionIdentifier) else {
        throw ProbeError.missingAction(actionIdentifier)
    }
    guard AXUIElementPerformAction(action, kAXPressAction as CFString) == .success else {
        throw ProbeError.actionFailed
    }
    guard try waitUntilAbsent(in: application, identifier: waitingIdentifier) else {
        throw ProbeError.promptStayedOpen(waitingIdentifier)
    }
    guard let status = try find(in: application, identifier: statusIdentifier) else {
        throw ProbeError.missingStatus
    }
    let value = string(status, kAXValueAttribute as CFString)
    let description = string(status, kAXDescriptionAttribute as CFString)
    guard matchesStatus(value) || matchesStatus(description) else {
        throw ProbeError.contract("Intentional override status mismatch: value=\(value) description=\(description)")
    }
    print("PROMPT_CLOSED=true")
    print("OVERRIDE_STATUS=visible")
    print("PASS: ZC-060-004 prompt closes with factual configured-window feedback")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
