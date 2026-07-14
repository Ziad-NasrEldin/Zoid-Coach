#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private func containsForbidden(_ exposed: String, forbiddenStrings: [String]) -> Bool {
    forbiddenStrings.contains { exposed.localizedCaseInsensitiveContains($0) }
}

private func boundedPageIndexes(maximumPages: Int) -> ClosedRange<Int> {
    0...maximumPages
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
    let forbidden = ["private-token", "/private/tmp/qa-root"]
    guard containsForbidden("PRIVATE-TOKEN", forbiddenStrings: forbidden),
          containsForbidden("database: /private/tmp/qa-root/zoid.sqlite", forbiddenStrings: forbidden),
          !containsForbidden("Manual workday is active", forbiddenStrings: forbidden),
          Array(boundedPageIndexes(maximumPages: 12)) == Array(0...12)
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
private let maximumSettingsScrollPages = 12
private var boundWindow: AXUIElement?

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

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
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

private func applicationWindows() throws -> [AXUIElement] {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    return ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter {
            role($0) == (kAXWindowRole as String)
                && bool($0, kAXMinimizedAttribute as CFString) != true
        }
}

private func roots() throws -> [AXUIElement] {
    if let boundWindow { return [boundWindow] }
    return try applicationWindows()
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

private func findOnce(in root: AXUIElement, matching: (AXUIElement) -> Bool) -> AXUIElement? {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { return nil }
        if matching(element) { return element }
        queue.append(contentsOf: children(element))
    }
    return nil
}

private func existingSettingsWindow() throws -> AXUIElement? {
    for window in try applicationWindows() {
        if findOnce(in: window, matching: {
            labels($0).contains(where: { $0.contains("SETTINGS / POLICY") })
        }) != nil {
            return window
        }
    }
    return nil
}

private func settingsWindow() throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(8)
    repeat {
        if let window = try existingSettingsWindow() { return window }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw ProbeError.failure("the normal Settings route did not expose a visible SETTINGS / POLICY window")
}

private func navigateToSettings() throws -> AXUIElement {
    if let existing = try existingSettingsWindow() { return existing }

    let windows = try applicationWindows()
    if let menuSettings = windows.lazy.compactMap({ window in
        findOnce(in: window, matching: { identifier($0) == "menu-bar.open-settings" })
    }).first {
        try press(menuSettings, name: "menu-bar Settings")
        return try settingsWindow()
    }

    if let sidebarSettings = windows.lazy.compactMap({ window in
        findOnce(in: window) {
            role($0) == (kAXButtonRole as String) && labels($0).contains("Settings")
        }
    }).first {
        try press(sidebarSettings, name: "sidebar Settings")
        return try settingsWindow()
    }

    if windows.contains(where: { window in
        findOnce(in: window, matching: { identifier($0) == "onboarding.root" }) != nil
    }) {
        throw ProbeError.failure(
            "onboarding is still visible; establish the supported QA ready state before verifying post-onboarding Settings"
        )
    }

    throw ProbeError.failure(
        "the normal Settings route is unavailable; finish or seed the supported QA onboarding ready state, then use the menu Settings button or sidebar Settings button"
    )
}

private func findSettingsIdentifier(_ expected: String) throws -> AXUIElement {
    guard let window = boundWindow else {
        throw ProbeError.failure("Settings window is not bound")
    }
    for page in boundedPageIndexes(maximumPages: maximumSettingsScrollPages) {
        if let element = findOnce(in: window, matching: { identifier($0) == expected }) {
            _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
            return element
        }
        guard page < maximumSettingsScrollPages else { break }
        var scrollAreas: [AXUIElement] = []
        _ = findOnce(in: window) { element in
            if role(element) == (kAXScrollAreaRole as String) { scrollAreas.append(element) }
            return false
        }
        guard scrollAreas.reversed().contains(where: {
            AXUIElementPerformAction($0, "AXScrollDownByPage" as CFString) == .success
        }) else {
            throw ProbeError.failure("could not scroll the visible Settings window toward \(expected)")
        }
        Thread.sleep(forTimeInterval: 0.15)
    }
    throw ProbeError.failure("required Settings target is unavailable after bounded scrolling: \(expected)")
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
    let picker = try findSettingsIdentifier("settings.schedule.workday-control")
    _ = try findSettingsIdentifier("settings.schedule.workday-control.detail")
    let manual = try descendant(picker, label: "Manual start and end")
    try requireSelected(manual, picker: picker)
    try requireEnabled(false, element: try findSettingsIdentifier("settings.schedule.fixed-hours"), name: "fixed-hours manual mode")
}

do {
    if options.phase == "settings-select-manual" || options.phase == "settings-persisted" {
        boundWindow = try navigateToSettings()
    }
    switch options.phase {
    case "settings-select-manual":
        let picker = try findSettingsIdentifier("settings.schedule.workday-control")
        _ = try findSettingsIdentifier("settings.schedule.workday-control.detail")
        let fixedHours = try findSettingsIdentifier("settings.schedule.fixed-hours")
        try requireEnabled(true, element: fixedHours, name: "fixed-hours baseline")
        let manual = try descendant(picker, label: "Manual start and end")
        try press(manual, name: "Manual start and end")
        try requireEnabled(false, element: try findSettingsIdentifier("settings.schedule.fixed-hours"), name: "fixed-hours manual mode")
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
