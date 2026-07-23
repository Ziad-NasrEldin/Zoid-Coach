#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let maximumNodes = 4_000

private func matchesPriorityState(label: String, value: String) -> Bool {
    label == "Priority task status" && value == "Incomplete"
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard matchesPriorityState(label: "Priority task status", value: "Incomplete"),
          !matchesPriorityState(label: "Priority task status", value: "Complete"),
          !matchesPriorityState(label: "Main objective", value: "Incomplete"),
          !matchesPriorityState(label: "Priority task status", value: "Status unknown")
    else {
        fputs("FAIL: ZC-059-001 AX matcher self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-059-001 AX matcher rejects complete, unknown, and non-priority states")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case missingState(String)
    case contract(String)

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: probe --pid PID --surface review|receipt --task-id TASK_ID"
        case .accessibilityPermission:
            "Accessibility permission is required."
        case .processUnavailable:
            "The exact app process is unavailable."
        case let .missingState(identifier):
            "The priority state is unavailable: \(identifier)"
        case let .contract(message):
            message
        }
    }
}

private struct Arguments {
    let pid: pid_t
    let surface: String
    let taskID: String

    init() throws {
        let values = CommandLine.arguments
        guard values.count == 7,
              values[1] == "--pid",
              let pid = pid_t(values[2]),
              pid > 0,
              values[3] == "--surface",
              ["review", "receipt"].contains(values[4]),
              values[5] == "--task-id",
              !values[6].isEmpty
        else { throw ProbeError.invalidArguments }
        self.pid = pid
        surface = values[4]
        taskID = values[6]
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

private func run() throws {
    let arguments = try Arguments()
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    guard kill(arguments.pid, 0) == 0 else { throw ProbeError.processUnavailable }
    let identifier = "calendar-plan-\(arguments.surface).priority-state.\(arguments.taskID)"
    let application = AXUIElementCreateApplication(arguments.pid)
    guard let state = try elements(from: application).first(where: {
        string($0, kAXIdentifierAttribute as CFString) == identifier
    }) else { throw ProbeError.missingState(identifier) }
    let label = string(state, kAXDescriptionAttribute as CFString)
    let value = string(state, kAXValueAttribute as CFString)
    guard matchesPriorityState(label: label, value: value) else {
        throw ProbeError.contract("Priority state mismatch: label=\(label) value=\(value)")
    }
    print("SURFACE=\(arguments.surface)")
    print("PRIORITY_STATE=Incomplete")
    print("PASS: ZC-059-001 exposes an explicit incomplete priority task")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
