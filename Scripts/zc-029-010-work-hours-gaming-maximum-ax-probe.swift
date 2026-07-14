#!/usr/bin/env swift
import ApplicationServices
import Darwin
import Foundation

private enum Mode: String {
    case settingsEnabled = "settings-enabled"
    case settingsPersisted = "settings-persisted"
    case settingsLowerBound = "settings-lower-bound"
    case settingsUpperBound = "settings-upper-bound"
    case withinWorkWindow = "within-work-window"
    case outsideWorkWindow = "outside-work-window"
    case disabled
    case partialLockedReward = "partial-locked-reward"
    case menuWithinWorkWindow = "menu-within-work-window"
    case menuOutsideWorkWindow = "menu-outside-work-window"
    case menuAwaitingRefresh = "menu-awaiting-refresh"
    case menuPrivacyScan = "menu-privacy-scan"
    case menuOmitted = "menu-omitted"
}

private struct Failure: Error { let message: String }

private let expected: [Mode: [String]] = [
    .withinWorkWindow: [
        "Base 30m · Earned 0m · Used 20m · Locked 0m · Remaining 10m · Same-day overage 0m",
        "Work-hours gaming is capped at 30 minutes. The normal daily allowance returns outside configured work hours."
    ],
    .outsideWorkWindow: ["Base 60m · Earned 15m · Used 20m · Locked 0m · Remaining 55m · Same-day overage 0m"],
    .disabled: ["Base 60m · Earned 15m · Used 20m · Locked 0m · Remaining 55m · Same-day overage 0m"],
    .partialLockedReward: ["Base 60m · Earned 0m · Used 0m · Locked 10m · Remaining 60m · Same-day overage 0m"],
    .menuWithinWorkWindow: ["30 MIN MAXIMUM", "Active in the current work window · 10m remaining"],
    .menuOutsideWorkWindow: ["30 MIN MAXIMUM", "Not active now · Normal allowance has 55m remaining"],
    .menuAwaitingRefresh: ["Current allowance is awaiting a work-hours policy refresh"]
]

private let forbiddenPrivacyFragments = [
    "PRIVATE-ZC029010-WINDOW-SENTINEL",
    "private-zc029010.invalid",
    "secret=sentinel"
]

private func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
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

private func strings(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func walk(_ root: AXUIElement, limit: Int = 2_500) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    while !queue.isEmpty && result.count < limit {
        let next = queue.removeFirst()
        result.append(next)
        queue.append(contentsOf: children(next))
    }
    return result
}

private func requireIdentifier(_ value: String, in elements: [AXUIElement]) throws -> AXUIElement {
    guard let match = elements.first(where: { identifier($0) == value }) else {
        throw Failure(message: "missing accessibility identifier \(value)")
    }
    return match
}

private func containsExact(_ value: String, in elements: [AXUIElement]) -> Bool {
    elements.contains { strings($0).contains(value) }
}

private func requireEnabled(_ element: AXUIElement, name: String) throws {
    if let enabled = attribute(element, kAXEnabledAttribute as CFString) as? Bool, !enabled {
        throw Failure(message: "\(name) is disabled")
    }
}

private func assertPrivacy(_ elements: [AXUIElement]) throws {
    if let fragment = privacyViolation(in: elements.flatMap(strings)) {
        throw Failure(message: "private fixture evidence leaked into accessibility: \(fragment)")
    }
}

private func privacyViolation(in values: [String]) -> String? {
    let exposed = values.joined(separator: "\n")
    return forbiddenPrivacyFragments.first {
        exposed.localizedCaseInsensitiveContains($0)
    }
}

private func assertSettingsBound(
    elements: [AXUIElement],
    value: Int,
    decreaseEnabled: Bool,
    increaseEnabled: Bool
) throws {
    let control = try requireIdentifier("settings.gaming.work-hours-maximum", in: elements)
    guard walk(control).flatMap(strings).contains("MAXIMUM DURING WORK HOURS, \(value) MIN") else {
        throw Failure(message: "work-hours maximum does not expose the expected bound")
    }
    guard let decrease = elements.first(where: { strings($0).contains("Decrease MAXIMUM DURING WORK HOURS") }),
          let increase = elements.first(where: { strings($0).contains("Increase MAXIMUM DURING WORK HOURS") })
    else { throw Failure(message: "bounded decrement/increment controls are missing") }
    let actualDecrease = (attribute(decrease, kAXEnabledAttribute as CFString) as? Bool) ?? true
    let actualIncrease = (attribute(increase, kAXEnabledAttribute as CFString) as? Bool) ?? true
    guard actualDecrease == decreaseEnabled, actualIncrease == increaseEnabled else {
        throw Failure(message: "work-hours maximum bound controls are not truthful")
    }
}

private func press(_ element: AXUIElement, name: String) throws {
    try requireEnabled(element, name: name)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw Failure(message: "could not press \(name)")
    }
    Thread.sleep(forTimeInterval: 0.35)
}

private func requiredIdentifier(for mode: Mode) -> String {
    switch mode {
    case .settingsEnabled, .settingsPersisted, .settingsLowerBound, .settingsUpperBound:
        "settings.gaming.work-hours-maximum-enabled"
    case .withinWorkWindow, .outsideWorkWindow, .disabled, .partialLockedReward:
        "today.gaming.status"
    case .menuWithinWorkWindow, .menuOutsideWorkWindow, .menuAwaitingRefresh, .menuPrivacyScan:
        "menu-bar.gaming.work-hours"
    case .menuOmitted:
        "menu-bar.coach"
    }
}

private func usesApplicationRoot(_ mode: Mode) -> Bool {
    switch mode {
    case .menuWithinWorkWindow, .menuOutsideWorkWindow, .menuAwaitingRefresh, .menuPrivacyScan, .menuOmitted:
        true
    default:
        false
    }
}

private func selectedWindowIndex(mode: Mode, identifiersByWindow: [[String]]) -> Int? {
    let required = requiredIdentifier(for: mode)
    return identifiersByWindow.firstIndex { $0.contains(required) }
}

private func modeRoot(pid: pid_t, mode: Mode) throws -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    if usesApplicationRoot(mode) {
        guard walk(app, limit: 10_000).contains(where: { identifier($0) == requiredIdentifier(for: mode) }) else {
            throw Failure(message: "application accessibility tree does not contain \(requiredIdentifier(for: mode))")
        }
        return app
    }
    guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement],
          !windows.isEmpty
    else { throw Failure(message: "no application windows") }
    let candidates = windows.filter {
        (attribute($0, kAXMinimizedAttribute as CFString) as? Bool) != true
    }
    let identifiers = candidates.map { window in walk(window).compactMap(identifier) }
    let matches = identifiers.indices.filter { identifiers[$0].contains(requiredIdentifier(for: mode)) }
    guard matches.count == 1, let index = matches.first else {
        throw Failure(message: "no application window contains \(requiredIdentifier(for: mode))")
    }
    return candidates[index]
}

private func runSelfTest() throws {
    let identifiers = [
        ["today.gaming.status", "settings.navigation"],
        ["menu-bar.coach", "menu-bar.gaming.work-hours"],
        ["settings.gaming.work-hours-maximum-enabled"],
    ]
    guard selectedWindowIndex(mode: .settingsEnabled, identifiersByWindow: identifiers) == 2,
          selectedWindowIndex(mode: .withinWorkWindow, identifiersByWindow: identifiers) == 0,
          usesApplicationRoot(.menuPrivacyScan),
          usesApplicationRoot(.menuOmitted),
          !usesApplicationRoot(.settingsEnabled)
    else { throw Failure(message: "mode-specific AX window selection failed") }
    guard privacyViolation(in: ["30 MIN MAXIMUM", "10m remaining"]) == nil,
          privacyViolation(in: ["PRIVATE-ZC029010-WINDOW-SENTINEL"]) == forbiddenPrivacyFragments[0]
    else { throw Failure(message: "recursive accessibility privacy scan failed") }
    print("PASS: ZC-029-010 accessibility probe selection and privacy self-test")
}

private func assertSettings(elements: [AXUIElement], exercise: Bool) throws {
    let toggle = try requireIdentifier("settings.gaming.work-hours-maximum-enabled", in: elements)
    let control = try requireIdentifier("settings.gaming.work-hours-maximum", in: elements)
    let detail = try requireIdentifier("settings.gaming.work-hours-maximum-detail", in: elements)
    try requireEnabled(toggle, name: "work-hours maximum toggle")
    guard strings(detail).contains("During configured work windows, the total daily allowance, including base and unlocked rewards, cannot exceed this maximum. Outside work hours, the normal daily allowance applies.") else {
        throw Failure(message: "enabled consequence copy is missing")
    }
    guard walk(control).flatMap(strings).contains("MAXIMUM DURING WORK HOURS, 30 MIN") else {
        throw Failure(message: "bounded work-hours maximum does not expose 30 MIN")
    }
    if exercise {
        guard let decrease = elements.first(where: { strings($0).contains("Decrease MAXIMUM DURING WORK HOURS") }),
              let increase = elements.first(where: { strings($0).contains("Increase MAXIMUM DURING WORK HOURS") })
        else { throw Failure(message: "bounded decrement/increment controls are missing") }
        try press(decrease, name: "work-hours maximum decrement")
        try press(increase, name: "work-hours maximum increment")
        guard let save = elements.first(where: { strings($0).contains("SAVE CHANGES") }) else {
            throw Failure(message: "Save Changes is unavailable")
        }
        try press(save, name: "Save Changes")
    }
}

private func run() throws {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try runSelfTest()
        return
    }
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]),
          let mode = Mode(rawValue: CommandLine.arguments[2])
    else { throw Failure(message: "usage: probe <pid> <settings-enabled|settings-persisted|settings-lower-bound|settings-upper-bound|within-work-window|outside-work-window|disabled|partial-locked-reward|menu-within-work-window|menu-outside-work-window|menu-awaiting-refresh|menu-privacy-scan|menu-omitted>") }
    guard AXIsProcessTrusted() else { throw Failure(message: "Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw Failure(message: "process is not running") }
    let root = try modeRoot(pid: pid, mode: mode)
    let elements = walk(root, limit: usesApplicationRoot(mode) ? 10_000 : 2_500)
    try assertPrivacy(elements)
    switch mode {
    case .settingsEnabled:
        try assertSettings(elements: elements, exercise: true)
    case .settingsPersisted:
        try assertSettings(elements: elements, exercise: false)
    case .settingsLowerBound:
        try assertSettingsBound(elements: elements, value: 0, decreaseEnabled: false, increaseEnabled: true)
    case .settingsUpperBound:
        try assertSettingsBound(elements: elements, value: 1_440, decreaseEnabled: true, increaseEnabled: false)
    case .withinWorkWindow, .outsideWorkWindow, .disabled, .partialLockedReward:
        _ = try requireIdentifier("today.gaming.status", in: elements)
        for value in expected[mode, default: []] where !containsExact(value, in: elements) {
            throw Failure(message: "rendered Today gaming state did not match \(mode.rawValue)")
        }
    case .menuWithinWorkWindow, .menuOutsideWorkWindow, .menuAwaitingRefresh, .menuPrivacyScan:
        _ = try requireIdentifier("menu-bar.gaming.work-hours", in: elements)
        _ = try requireIdentifier("menu-bar.gaming.work-hours.maximum", in: elements)
        _ = try requireIdentifier("menu-bar.gaming.work-hours.status", in: elements)
        for value in expected[mode, default: []] where !containsExact(value, in: elements) {
            throw Failure(message: "rendered menu gaming state did not match \(mode.rawValue)")
        }
    case .menuOmitted:
        guard !elements.contains(where: { identifier($0) == "menu-bar.gaming.work-hours" }) else {
            throw Failure(message: "menu work-hours summary should be omitted")
        }
    }
    print("PASS: ZC-029-010 \(mode.rawValue) accessibility contract verified")
}

do {
    try run()
} catch let failure as Failure {
    fputs("FAIL: \(failure.message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: unexpected accessibility probe error\n", stderr)
    exit(1)
}
