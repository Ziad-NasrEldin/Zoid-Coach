#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let dayStateIdentifier = "today.day-state"
private let maximumNodes = 4_000

private func matchesPausedState(
    label: String,
    value: String,
    expectedTitle: String,
    expectedDetail: String,
    expectedValue: String
) -> Bool {
    label.localizedCaseInsensitiveContains("Day state: \(expectedTitle). \(expectedDetail)")
        && value == expectedValue
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard matchesPausedState(
        label: "Wednesday, 15 July. Day state: WORK PAUSED. A task is paused and ready to resume.",
        value: "paused",
        expectedTitle: "WORK PAUSED",
        expectedDetail: "A task is paused and ready to resume.",
        expectedValue: "paused"
    ),
    !matchesPausedState(
        label: "Wednesday, 15 July. Day state: PLANNED DAY. Today's commitments are ready.",
        value: "planned",
        expectedTitle: "WORK PAUSED",
        expectedDetail: "A task is paused and ready to resume.",
        expectedValue: "paused"
    ),
    !matchesPausedState(
        label: "Wednesday, 15 July. Day state: WORK PAUSED. A task is paused and ready to resume.",
        value: "planned",
        expectedTitle: "WORK PAUSED",
        expectedDetail: "A task is paused and ready to resume.",
        expectedValue: "paused"
    ) else {
        fputs("FAIL: ZC-056-006 paused day-state AX self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-056-006 AX self-test rejects planned fallback and stale accessibility value")
    exit(0)
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermission
    case processUnavailable
    case ambiguousWindow
    case missingDayState
    case wrongState(label: String, value: String)

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: probe --pid PID --expected-title TITLE --expected-detail DETAIL --expected-value VALUE"
        case .accessibilityPermission:
            "Accessibility permission is required."
        case .processUnavailable:
            "The exact app process is unavailable."
        case .ambiguousWindow:
            "Expected exactly one main window."
        case .missingDayState:
            "The Today day-state element is unavailable."
        case let .wrongState(label, value):
            "The day state did not match. label=\(label) value=\(value)"
        }
    }
}

private struct Arguments {
    let pid: pid_t
    let expectedTitle: String
    let expectedDetail: String
    let expectedValue: String

    init(_ values: [String]) throws {
        var pid: pid_t?
        var title: String?
        var detail: String?
        var value: String?
        var index = 1
        while index < values.count {
            guard index + 1 < values.count else { throw ProbeError.invalidArguments }
            switch values[index] {
            case "--pid": pid = pid_t(values[index + 1])
            case "--expected-title": title = values[index + 1]
            case "--expected-detail": detail = values[index + 1]
            case "--expected-value": value = values[index + 1]
            default: throw ProbeError.invalidArguments
            }
            index += 2
        }
        guard let pid, pid > 0,
              let title, !title.isEmpty,
              let detail, !detail.isEmpty,
              let value, !value.isEmpty
        else { throw ProbeError.invalidArguments }
        self.pid = pid
        expectedTitle = title
        expectedDetail = detail
        expectedValue = value
    }
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
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
        guard result.count <= maximumNodes else { throw ProbeError.missingDayState }
        queue.append(contentsOf: children(element))
    }
    return result
}

private func mainWindow(_ application: AXUIElement) throws -> AXUIElement {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    let main = windows.filter {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
    guard main.count == 1 else { throw ProbeError.ambiguousWindow }
    return main[0]
}

private func run() throws {
    let arguments = try Arguments(CommandLine.arguments)
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    guard kill(arguments.pid, 0) == 0 else { throw ProbeError.processUnavailable }
    let application = AXUIElementCreateApplication(arguments.pid)
    let deadline = Date().addingTimeInterval(12)
    var lastLabel = ""
    var lastValue = ""
    repeat {
        let window = try mainWindow(application)
        let matches = try elements(from: window).filter {
            string($0, kAXIdentifierAttribute as CFString) == dayStateIdentifier
        }
        guard matches.count <= 1 else { throw ProbeError.missingDayState }
        if let dayState = matches.first {
            lastLabel = string(dayState, kAXDescriptionAttribute as CFString)
                ?? string(dayState, kAXTitleAttribute as CFString)
                ?? ""
            lastValue = string(dayState, kAXValueAttribute as CFString) ?? ""
            if matchesPausedState(
                label: lastLabel,
                value: lastValue,
                expectedTitle: arguments.expectedTitle,
                expectedDetail: arguments.expectedDetail,
                expectedValue: arguments.expectedValue
            ) {
                print("PASS: ZC-056-006 paused day state is explicit and accessibility-identifiable")
                return
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    guard !lastLabel.isEmpty || !lastValue.isEmpty else { throw ProbeError.missingDayState }
    throw ProbeError.wrongState(label: lastLabel, value: lastValue)
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
