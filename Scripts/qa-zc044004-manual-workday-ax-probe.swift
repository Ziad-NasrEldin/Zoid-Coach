#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private let arguments = CommandLine.arguments
guard arguments.count == 5,
      arguments[1] == "--pid",
      let pid = Int32(arguments[2]),
      arguments[3] == "--phase"
else {
    fputs("usage: qa-zc044004-manual-workday-ax-probe.swift --pid <pid> --phase <settings-select-manual|ready-start|active-end|ended>\n", stderr)
    exit(2)
}

private let phase = arguments[4]
private let application = AXUIElementCreateApplication(pid)
private let maximumNodes = 4_000

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute as CFString)
}

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func roots() throws -> [AXUIElement] {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    return (attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? []
}

private func find(_ description: String, matching: (AXUIElement) -> Bool) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(8)
    var queue = try roots()
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty, Date() < deadline {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { break }
        if matching(element) { return element }
        queue.append(contentsOf: children(element))
    }
    throw ProbeError.failure("required AX target is unavailable: \(description)")
}

private func findIdentifier(_ expected: String) throws -> AXUIElement {
    try find(expected) { identifier($0) == expected }
}

private func targetExists(_ expected: String) -> Bool {
    (try? findIdentifier(expected)) != nil
}

private func press(_ element: AXUIElement, name: String) throws {
    _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("could not press \(name)")
    }
    Thread.sleep(forTimeInterval: 0.35)
}

private func requireLabel(_ expected: String, on element: AXUIElement) throws {
    guard labels(element).contains(expected) else {
        throw ProbeError.failure("AX label mismatch for \(expected): \(labels(element))")
    }
}

private func requireEnabled(_ expected: Bool, element: AXUIElement, name: String) throws {
    let enabled = (attribute(element, kAXEnabledAttribute as CFString) as? NSNumber)?.boolValue
    guard enabled == expected else {
        throw ProbeError.failure("\(name) enabled state was \(String(describing: enabled)), expected \(expected)")
    }
}

private func descendant(_ root: AXUIElement, label expected: String) throws -> AXUIElement {
    var queue = children(root)
    while !queue.isEmpty {
        let element = queue.removeFirst()
        if labels(element).contains(expected) { return element }
        queue.append(contentsOf: children(element))
    }
    throw ProbeError.failure("missing descendant labeled \(expected)")
}

do {
    switch phase {
    case "settings-select-manual":
        let picker = try findIdentifier("settings.schedule.workday-control")
        _ = try findIdentifier("settings.schedule.workday-control.detail")
        let fixedHours = try findIdentifier("settings.schedule.fixed-hours")
        try requireEnabled(true, element: fixedHours, name: "fixed-hours baseline")
        let manual = try descendant(picker, label: "Manual start and end")
        try press(manual, name: "Manual start and end")
        try requireEnabled(false, element: try findIdentifier("settings.schedule.fixed-hours"), name: "fixed-hours manual mode")
        let save = try find("SAVE CHANGES") { labels($0).contains("SAVE CHANGES") }
        try press(save, name: "Save Changes")
        _ = try find("All changes saved") { labels($0).contains("All changes saved") }
    case "ready-start":
        _ = try findIdentifier("menu-bar.manual-workday.status")
        let start = try findIdentifier("menu-bar.task.start")
        try requireLabel("Start workday with recommended task", on: start)
        guard !targetExists("menu-bar.task.end-workday") else {
            throw ProbeError.failure("End Workday must be omitted while the task is ready")
        }
        try press(start, name: "Start Workday")
    case "active-end":
        _ = try findIdentifier("menu-bar.manual-workday.status")
        guard !targetExists("menu-bar.task.start") else {
            throw ProbeError.failure("Start Workday must be omitted while active")
        }
        let end = try findIdentifier("menu-bar.task.end-workday")
        try requireLabel("End the workday", on: end)
        try press(end, name: "End Workday")
        let confirm = try find("END WORKDAY confirmation") {
            labels($0).contains("END WORKDAY") && identifier($0) != "menu-bar.task.end-workday"
        }
        try press(confirm, name: "confirmed End Workday")
    case "ended":
        let status = try findIdentifier("menu-bar.manual-workday.status")
        guard labels(status).contains(where: { $0.localizedCaseInsensitiveContains("ended") }) else {
            throw ProbeError.failure("manual workday status does not expose the ended state")
        }
        guard !targetExists("menu-bar.task.start"), !targetExists("menu-bar.task.end-workday") else {
            throw ProbeError.failure("invalid Start or End Workday action remains after ending")
        }
        let resume = try findIdentifier("menu-bar.task.resume")
        try requireLabel("Start workday by resuming paused task", on: resume)
    default:
        throw ProbeError.failure("unsupported phase: \(phase)")
    }
    print("PASS: ZC-044-004 AX phase \(phase)")
} catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
