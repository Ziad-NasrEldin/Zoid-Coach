#!/usr/bin/env swift
import ApplicationServices
import Darwin
import Foundation

private enum Mode: String {
    case settingsEnabled = "settings-enabled"
    case settingsPersisted = "settings-persisted"
    case withinWorkWindow = "within-work-window"
    case outsideWorkWindow = "outside-work-window"
    case disabled
    case partialLockedReward = "partial-locked-reward"
}

private struct Failure: Error { let message: String }

private let expected: [Mode: [String]] = [
    .withinWorkWindow: [
        "Base 30m · Earned 0m · Used 20m · Locked 0m · Remaining 10m · Same-day overage 0m",
        "Work-hours gaming is capped at 30 minutes. The normal daily allowance returns outside configured work hours."
    ],
    .outsideWorkWindow: ["Base 60m · Earned 15m · Used 20m · Locked 0m · Remaining 55m · Same-day overage 0m"],
    .disabled: ["Base 60m · Earned 15m · Used 20m · Locked 0m · Remaining 55m · Same-day overage 0m"],
    .partialLockedReward: ["Base 60m · Earned 0m · Used 0m · Locked 10m · Remaining 60m · Same-day overage 0m"]
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

private func press(_ element: AXUIElement, name: String) throws {
    try requireEnabled(element, name: name)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw Failure(message: "could not press \(name)")
    }
    Thread.sleep(forTimeInterval: 0.35)
}

private func singleWindow(pid: pid_t) throws -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement],
          let window = windows.first(where: { (attribute($0, kAXMinimizedAttribute as CFString) as? Bool) != true })
    else { throw Failure(message: "no non-minimized application window") }
    return window
}

private func assertSettings(elements: [AXUIElement], exercise: Bool) throws {
    let toggle = try requireIdentifier("settings.gaming.work-hours-maximum-enabled", in: elements)
    let control = try requireIdentifier("settings.gaming.work-hours-maximum", in: elements)
    let detail = try requireIdentifier("settings.gaming.work-hours-maximum-detail", in: elements)
    try requireEnabled(toggle, name: "work-hours maximum toggle")
    guard strings(detail).contains("During configured work windows, total available gaming cannot exceed this maximum, including unlocked rewards. Outside work hours, the normal daily allowance applies.") else {
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
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]),
          let mode = Mode(rawValue: CommandLine.arguments[2])
    else { throw Failure(message: "usage: probe <pid> <settings-enabled|settings-persisted|within-work-window|outside-work-window|disabled|partial-locked-reward>") }
    guard AXIsProcessTrusted() else { throw Failure(message: "Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw Failure(message: "process is not running") }
    let elements = walk(try singleWindow(pid: pid))
    switch mode {
    case .settingsEnabled:
        try assertSettings(elements: elements, exercise: true)
    case .settingsPersisted:
        try assertSettings(elements: elements, exercise: false)
    case .withinWorkWindow, .outsideWorkWindow, .disabled, .partialLockedReward:
        _ = try requireIdentifier("today.gaming.status", in: elements)
        for value in expected[mode, default: []] where !containsExact(value, in: elements) {
            throw Failure(message: "rendered Today gaming state did not match \(mode.rawValue)")
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
