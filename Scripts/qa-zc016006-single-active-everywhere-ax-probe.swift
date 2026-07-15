#!/usr/bin/env swift

import ApplicationServices
import CryptoKit
import Foundation

private let privateSentinel = "zc016006-private-window-title"

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
    let taskID: String
    let taskTitle: String
    let previousTitle: String?
    let activate: Bool

    init(_ values: [String]) throws {
        var pid: pid_t?
        var taskID: String?
        var taskTitle: String?
        var previousTitle: String?
        var activate = false
        var index = 1
        while index < values.count {
            if values[index] == "--activate" {
                activate = true
                index += 1
                continue
            }
            guard index + 1 < values.count else {
                throw ProbeError.invalidArguments("Every option except --activate requires a value.")
            }
            switch values[index] {
            case "--pid": pid = pid_t(values[index + 1])
            case "--task-id": taskID = values[index + 1]
            case "--task-title": taskTitle = values[index + 1]
            case "--previous-title": previousTitle = values[index + 1]
            default: throw ProbeError.invalidArguments("Unsupported option: \(values[index])")
            }
            index += 2
        }
        guard let pid, pid > 0,
              let taskID, !taskID.isEmpty,
              let taskTitle, !taskTitle.isEmpty
        else {
            throw ProbeError.invalidArguments(
                "usage: probe --pid PID --task-id ID --task-title TITLE [--previous-title TITLE] [--activate]"
            )
        }
        self.pid = pid
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.previousTitle = previousTitle
        self.activate = activate
    }
}

private func opaqueTaskToken(_ persistedID: String) -> String {
    let input = Data("zoid-coach.accessibility.task.v1\u{0}\(persistedID)".utf8)
    return SHA256.hash(data: input)
        .prefix(16)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func crossSurfaceContract(
    todayValues: [String],
    menuSummary: String,
    activeTitle: String,
    previousTitle: String?
) -> Bool {
    let today = todayValues.joined(separator: " ")
    guard today.localizedCaseInsensitiveContains(activeTitle),
          today.localizedCaseInsensitiveContains("active"),
          menuSummary.localizedCaseInsensitiveContains(activeTitle),
          menuSummary.localizedCaseInsensitiveContains("active"),
          !today.localizedCaseInsensitiveContains(privateSentinel),
          !menuSummary.localizedCaseInsensitiveContains(privateSentinel)
    else { return false }
    return previousTitle.map {
        !menuSummary.localizedCaseInsensitiveContains($0)
    } ?? true
}

private enum ActivationControl: Equatable {
    case boundedSprint
    case titleBoundStart
    case missing
}

private func activationControl(hasBoundedSprint: Bool, hasTitleBoundStart: Bool) -> ActivationControl {
    if hasBoundedSprint { return .boundedSprint }
    if hasTitleBoundStart { return .titleBoundStart }
    return .missing
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let firstToken = opaqueTaskToken("qa-zc016006-first")
    let secondToken = opaqueTaskToken("qa-zc016006-second")
    guard firstToken.count == 32,
          secondToken.count == 32,
          firstToken != secondToken,
          activationControl(hasBoundedSprint: true, hasTitleBoundStart: true) == .boundedSprint,
          activationControl(hasBoundedSprint: false, hasTitleBoundStart: true) == .titleBoundStart,
          activationControl(hasBoundedSprint: false, hasTitleBoundStart: false) == .missing,
          crossSurfaceContract(
              todayValues: ["ACTIVE TASK", "Prepare the second focus review"],
              menuSummary: "Prepare the second focus review. Active sprint. 9 min left.",
              activeTitle: "Prepare the second focus review",
              previousTitle: "Write the first focus brief"
          ),
          !crossSurfaceContract(
              todayValues: ["ACTIVE TASK", "Prepare the second focus review"],
              menuSummary: "Write the first focus brief. Active.",
              activeTitle: "Prepare the second focus review",
              previousTitle: "Write the first focus brief"
          ),
          !crossSurfaceContract(
              todayValues: ["ACTIVE TASK", privateSentinel],
              menuSummary: "Prepare the second focus review. Active.",
              activeTitle: "Prepare the second focus review",
              previousTitle: nil
          )
    else {
        fputs("FAIL: ZC-016-006 AX self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-016-006 AX self-test covers both activation controls, identity, cross-surface mismatch, and privacy rejection")
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

private func mainWindow(_ application: AXUIElement) -> AXUIElement? {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    let main = windows.filter {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
    return main.count == 1 ? main[0] : nil
}

private func waitForTodayValues(
    in window: AXUIElement,
    activeTitle: String,
    timeout: TimeInterval = 12
) -> [String]? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let values = elements(from: window).flatMap(publicStrings)
        let combined = values.joined(separator: " ")
        if combined.localizedCaseInsensitiveContains(activeTitle),
           combined.localizedCaseInsensitiveContains("active") {
            return values
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

private func press(_ element: AXUIElement, action: String) throws {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeError.actionFailed(action)
    }
}

private func activateTask(
    application: AXUIElement,
    taskID: String,
    taskTitle: String,
    expectsSwitchConfirmation: Bool
) throws {
    guard let window = mainWindow(application) else {
        throw ProbeError.missingElement("unique main window")
    }
    let startIdentifier = "today.sprint.start.\(opaqueTaskToken(taskID))"
    let boundedSprint = waitForElement(in: window, timeout: 1, matching: {
        identifier($0) == startIdentifier
    })
    let exactStartTitle = "START \(taskTitle.uppercased())"
    let titleBoundStart = boundedSprint == nil ? waitForElement(in: window, matching: {
        publicStrings($0).contains(exactStartTitle)
    }) : nil
    switch activationControl(
        hasBoundedSprint: boundedSprint != nil,
        hasTitleBoundStart: titleBoundStart != nil
    ) {
    case .boundedSprint:
        try press(boundedSprint!, action: "open bounded sprint menu")
        guard let tenMinute = waitForElement(in: application, matching: {
            publicStrings($0).contains("10-minute recovery sprint")
        }) else {
            throw ProbeError.missingElement("10-minute recovery sprint")
        }
        try press(tenMinute, action: "start recovery sprint")
    case .titleBoundStart:
        try press(titleBoundStart!, action: "start exact Today task")
    case .missing:
        throw ProbeError.missingElement("\(startIdentifier) or \(exactStartTitle)")
    }
    if expectsSwitchConfirmation {
        guard let confirmation = waitForElement(in: application, matching: {
            publicStrings($0).contains("Switch and preserve time")
        }) else {
            throw ProbeError.missingElement("Switch and preserve time")
        }
        try press(confirmation, action: "confirm active-task switch")
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
    if arguments.activate {
        try activateTask(
            application: application,
            taskID: arguments.taskID,
            taskTitle: arguments.taskTitle,
            expectsSwitchConfirmation: arguments.previousTitle != nil
        )
    }
    guard let window = mainWindow(application),
          let todayValues = waitForTodayValues(in: window, activeTitle: arguments.taskTitle)
    else { throw ProbeError.missingElement("confirmed Today active task") }
    let statusItem = try openCompactMenu(application)
    let summaries = elements(from: application).filter {
        identifier($0) == "menu-bar.task.summary"
    }
    guard summaries.count == 1 else {
        throw ProbeError.contract("Expected exactly one compact active-task summary, got \(summaries.count).")
    }
    let summary = publicStrings(summaries[0]).joined(separator: " ")
    guard crossSurfaceContract(
        todayValues: todayValues,
        menuSummary: summary,
        activeTitle: arguments.taskTitle,
        previousTitle: arguments.previousTitle
    ) else {
        throw ProbeError.contract("Today and the menu bar do not expose the same privacy-safe active task.")
    }
    print("ACTIVE_TASK_ID=\(arguments.taskID)")
    print("PASS: ZC-016-006 Today and menu bar expose one matching active task")
    try? press(statusItem, action: "close compact task menu")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
