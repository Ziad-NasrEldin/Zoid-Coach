#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private func containsForbidden(_ exposed: String, forbiddenStrings: [String]) -> Bool {
    forbiddenStrings.contains { exposed.localizedCaseInsensitiveContains($0) }
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
    let forbidden = ["private-token", "/private/tmp/qa-root"]
    guard containsForbidden("PRIVATE-TOKEN", forbiddenStrings: forbidden),
          containsForbidden("database: /private/tmp/qa-root/zoid.sqlite", forbiddenStrings: forbidden),
          !containsForbidden("Manual workday is active", forbiddenStrings: forbidden)
    else {
        fputs("FAIL: AX privacy sentinel matcher self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-044-004 AX probe self-test")
    exit(0)
}

private struct Options {
    let pid: Int32
    let phase: String
    let expectedTaskTitle: String?
    let forbiddenStrings: [String]
}

private func usage() -> Never {
    fputs("usage: qa-zc044004-manual-workday-ax-probe.swift --self-test | --pid <pid> --phase <settings-select-manual|settings-persisted|ready-start|stale-start|active-end|stale-end|ended> [--expected-task-title <title>] [--forbid <private-string>]...\n", stderr)
    exit(2)
}

private func parseOptions() -> Options {
    var pid: Int32?
    var phase: String?
    var expectedTaskTitle: String?
    var forbiddenStrings = [
        "qa-zc044004-manual-workday-task",
        "qa.zc044004.original-policy-version",
        "ZC-044-004 signed QA fixture",
    ]
    var index = 1
    while index < CommandLine.arguments.count {
        let option = CommandLine.arguments[index]
        guard index + 1 < CommandLine.arguments.count else { usage() }
        let value = CommandLine.arguments[index + 1]
        switch option {
        case "--pid": pid = Int32(value)
        case "--phase": phase = value
        case "--expected-task-title": expectedTaskTitle = value
        case "--forbid": forbiddenStrings.append(value)
        default: usage()
        }
        index += 2
    }
    guard let pid, let phase else { usage() }
    return Options(
        pid: pid,
        phase: phase,
        expectedTaskTitle: expectedTaskTitle,
        forbiddenStrings: forbiddenStrings.filter { !$0.isEmpty }
    )
}

private let options = parseOptions()
private let application = AXUIElementCreateApplication(options.pid)
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

private func exposedStrings(_ element: AXUIElement) -> [String] {
    [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
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
    repeat {
        var queue = try roots()
        var visited = Set<CFHashCode>()
        var count = 0
        while !queue.isEmpty {
            let element = queue.removeFirst()
            guard visited.insert(CFHash(element)).inserted else { continue }
            count += 1
            guard count <= maximumNodes else { break }
            if matching(element) { return element }
            queue.append(contentsOf: children(element))
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
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

private func requireLabelContaining(_ expected: String, on element: AXUIElement, name: String) throws {
    guard labels(element).contains(where: { $0.localizedCaseInsensitiveContains(expected) }) else {
        throw ProbeError.failure("\(name) does not contain \(expected): \(labels(element))")
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

private func requireSelected(_ element: AXUIElement, picker: AXUIElement) throws {
    let selected = (attribute(element, kAXSelectedAttribute as CFString) as? NSNumber)?.boolValue
    let value = (attribute(element, kAXValueAttribute as CFString) as? NSNumber)?.boolValue
    let pickerValue = string(picker, kAXValueAttribute as CFString)
    guard selected == true || value == true || pickerValue?.localizedCaseInsensitiveContains("Manual start and end") == true else {
        throw ProbeError.failure("Manual start and end is not selected after relaunch")
    }
}

private func requirePrivacy() throws {
    var queue = try roots()
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw ProbeError.failure("privacy scan exceeded \(maximumNodes) AX nodes")
        }
        for value in exposedStrings(element) {
            if containsForbidden(value, forbiddenStrings: options.forbiddenStrings) {
                throw ProbeError.failure("private sentinel leaked through Accessibility")
            }
        }
        queue.append(contentsOf: children(element))
    }
}

private func requireManualSettings() throws {
    let picker = try findIdentifier("settings.schedule.workday-control")
    _ = try findIdentifier("settings.schedule.workday-control.detail")
    let manual = try descendant(picker, label: "Manual start and end")
    try requireSelected(manual, picker: picker)
    try requireEnabled(false, element: try findIdentifier("settings.schedule.fixed-hours"), name: "fixed-hours manual mode")
}

do {
    switch options.phase {
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
    case "settings-persisted":
        try requireManualSettings()
    case "ready-start":
        _ = try findIdentifier("menu-bar.manual-workday.status")
        if let title = options.expectedTaskTitle {
            try requireLabelContaining(title, on: try findIdentifier("menu-bar.task.summary"), name: "ready task summary")
        }
        let start = try findIdentifier("menu-bar.task.start")
        try requireLabel("Start workday with recommended task", on: start)
        guard !targetExists("menu-bar.task.end-workday") else {
            throw ProbeError.failure("End Workday must be omitted while the task is ready")
        }
        try press(start, name: "Start Workday")
    case "stale-start":
        let start = try findIdentifier("menu-bar.task.start")
        try press(start, name: "stale Start Workday")
        let error = try findIdentifier("menu-bar.error")
        try requireLabelContaining("changed before Start", on: error, name: "stale Start error")
        guard !targetExists("menu-bar.task.start") else {
            throw ProbeError.failure("stale Start remained available after the fresh state was loaded")
        }
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
    case "stale-end":
        let end = try findIdentifier("menu-bar.task.end-workday")
        try press(end, name: "stale End Workday")
        let confirm = try find("END WORKDAY confirmation") {
            labels($0).contains("END WORKDAY") && identifier($0) != "menu-bar.task.end-workday"
        }
        try press(confirm, name: "confirmed stale End Workday")
        let error = try findIdentifier("menu-bar.error")
        try requireLabelContaining("active task changed before confirmation", on: error, name: "stale End error")
        guard !targetExists("menu-bar.task.end-workday") else {
            throw ProbeError.failure("stale End remained available after the fresh state was loaded")
        }
    case "ended":
        let status = try findIdentifier("menu-bar.manual-workday.status")
        try requireLabelContaining("ended", on: status, name: "manual workday status")
        guard !targetExists("menu-bar.task.start"), !targetExists("menu-bar.task.end-workday") else {
            throw ProbeError.failure("invalid Start or End Workday action remains after ending")
        }
        let resume = try findIdentifier("menu-bar.task.resume")
        try requireLabel("Start workday by resuming paused task", on: resume)
    default:
        throw ProbeError.failure("unsupported phase: \(options.phase)")
    }
    try requirePrivacy()
    print("PASS: ZC-044-004 AX phase \(options.phase)")
} catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
