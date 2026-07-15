#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case accessibilityPermission
    case processUnavailable
    case missingElement(String)
    case actionFailed(String)
    case contract(String)

    var description: String {
        switch self {
        case let .invalidArguments(message): message
        case .accessibilityPermission: "Accessibility permission is required."
        case .processUnavailable: "The exact app process is unavailable."
        case let .missingElement(identifier): "Missing accessibility element: \(identifier)"
        case let .actionFailed(action): "Accessibility action failed: \(action)"
        case let .contract(message): message
        }
    }
}

private struct Arguments {
    let pid: pid_t
    let taskTitle: String
    let compactEstimate: String
    let compactUnit: String
    let wideBreakDuration: String

    init(_ values: [String]) throws {
        var pid: pid_t?
        var taskTitle: String?
        var compactEstimate: String?
        var compactUnit: String?
        var wideBreakDuration: String?
        var index = 1
        while index < values.count {
            guard index + 1 < values.count else {
                throw ProbeError.invalidArguments("Every option requires a value.")
            }
            switch values[index] {
            case "--pid": pid = pid_t(values[index + 1])
            case "--task-title": taskTitle = values[index + 1]
            case "--compact-estimate": compactEstimate = values[index + 1]
            case "--compact-unit": compactUnit = values[index + 1]
            case "--wide-break-duration": wideBreakDuration = values[index + 1]
            default: throw ProbeError.invalidArguments("Unsupported option: \(values[index])")
            }
            index += 2
        }
        guard let pid, pid > 0,
              let taskTitle, !taskTitle.isEmpty,
              let compactEstimate, !compactEstimate.isEmpty,
              let compactUnit, !compactUnit.isEmpty,
              let wideBreakDuration, !wideBreakDuration.isEmpty
        else {
            throw ProbeError.invalidArguments(
                "usage: probe --pid PID --task-title TITLE --compact-estimate TEXT --compact-unit TEXT --wide-break-duration TEXT"
            )
        }
        self.pid = pid
        self.taskTitle = taskTitle
        self.compactEstimate = compactEstimate
        self.compactUnit = compactUnit
        self.wideBreakDuration = wideBreakDuration
    }
}

private func durationContract(
    summary: String,
    menuValues: [String],
    taskTitle: String,
    compactEstimate: String,
    compactUnit: String,
    wideBreakDuration: String
) -> Bool {
    let menu = menuValues.joined(separator: " ")
    return summary.contains(taskTitle)
        && summary.contains("\(compactEstimate) estimate")
        && summary.contains("\(compactUnit) tracked")
        && summary.localizedCaseInsensitiveContains("active")
        && menu.contains("Start a break lasting \(wideBreakDuration)")
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let nbsp = "\u{00a0}"
    guard durationContract(
        summary: "Review localized duration copy. Active. 12\(nbsp)min tracked. 45\(nbsp)min estimate.",
        menuValues: ["Start a break lasting 15 minutes"],
        taskTitle: "Review localized duration copy",
        compactEstimate: "45\(nbsp)min",
        compactUnit: "\(nbsp)min",
        wideBreakDuration: "15 minutes"
    ),
    !durationContract(
        summary: "Review localized duration copy. Active. 12 min tracked. 45 min estimate.",
        menuValues: ["Start a break lasting 15 minutes"],
        taskTitle: "Review localized duration copy",
        compactEstimate: "45\(nbsp)min",
        compactUnit: "\(nbsp)min",
        wideBreakDuration: "15 minutes"
    ),
    !durationContract(
        summary: "Review localized duration copy. Active. 12\(nbsp)min tracked. 45\(nbsp)min estimate.",
        menuValues: ["Start break"],
        taskTitle: "Review localized duration copy",
        compactEstimate: "45\(nbsp)min",
        compactUnit: "\(nbsp)min",
        wideBreakDuration: "15 minutes"
    ) else {
        fputs("FAIL: ZC-056-001 AX contract self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-056-001 AX self-test rejects fallback spacing and missing wide accessibility duration")
    exit(0)
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

private func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute as CFString)
}

private func publicStrings(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
        .filter { !$0.isEmpty }
}

private func elements(from root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while !queue.isEmpty, result.count < limit {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        result.append(element)
        queue.append(contentsOf: children(element))
    }
    return result
}

private func waitForElement(
    in root: AXUIElement,
    timeout: TimeInterval = 12,
    matching predicate: (AXUIElement) -> Bool
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let match = elements(from: root).first(where: predicate) { return match }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

private func press(_ element: AXUIElement, action: String) throws {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeError.actionFailed(action)
    }
}

private func openCompactMenu(_ application: AXUIElement) throws -> AXUIElement {
    guard let extrasValue = attribute(application, kAXExtrasMenuBarAttribute as CFString),
          CFGetTypeID(extrasValue) == AXUIElementGetTypeID()
    else { throw ProbeError.missingElement("menu-bar.status-item") }
    let extras = unsafeBitCast(extrasValue, to: AXUIElement.self)
    guard let statusItem = waitForElement(in: extras, matching: {
        publicStrings($0).contains("A task is active")
    }) else { throw ProbeError.missingElement("active menu-bar status item") }
    if waitForElement(in: application, timeout: 0.2, matching: {
        identifier($0) == "menu-bar.task.summary"
    }) == nil {
        try press(statusItem, action: "open compact task menu")
    }
    return statusItem
}

private func run() throws {
    let arguments = try Arguments(CommandLine.arguments)
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    guard kill(arguments.pid, 0) == 0 else { throw ProbeError.processUnavailable }
    let application = AXUIElementCreateApplication(arguments.pid)
    let statusItem = try openCompactMenu(application)
    let summaries = elements(from: application).filter {
        identifier($0) == "menu-bar.task.summary"
    }
    guard summaries.count == 1 else {
        throw ProbeError.contract("Expected exactly one compact task summary, got \(summaries.count).")
    }
    let summary = publicStrings(summaries[0]).joined(separator: " ")
    let menuValues = elements(from: application).flatMap(publicStrings)
    guard durationContract(
        summary: summary,
        menuValues: menuValues,
        taskTitle: arguments.taskTitle,
        compactEstimate: arguments.compactEstimate,
        compactUnit: arguments.compactUnit,
        wideBreakDuration: arguments.wideBreakDuration
    ) else {
        throw ProbeError.contract("Menu-bar duration copy does not match the requested locale and semantic contract.")
    }
    print("PASS: ZC-056-001 menu-bar compact and accessibility durations match the launched locale")
    try? press(statusItem, action: "close compact task menu")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
