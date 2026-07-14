#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ExitCode: Int32 {
    case success = 0
    case usage = 2
    case attach = 3
    case window = 4
    case navigation = 5
    case assertion = 6
    case action = 7
    case timeout = 8
    case accessibilityPermission = 9
}

private struct ProbeFailure: Error {
    let code: ExitCode
    let message: String
}

private struct Arguments {
    let pid: pid_t
    let exerciseControls: Bool

    static func parse() throws -> Arguments {
        var suppliedPID: pid_t?
        var exerciseControls = false
        var index = 1
        let values = CommandLine.arguments

        while index < values.count {
            switch values[index] {
            case "--pid":
                index += 1
                guard index < values.count,
                      let value = Int32(values[index]),
                      value > 0 else {
                    throw ProbeFailure(code: .usage, message: "--pid requires a positive process identifier")
                }
                suppliedPID = value
            case "--exercise-controls":
                exerciseControls = true
            case "--help", "-h":
                throw ProbeFailure(code: .usage, message: usage)
            default:
                throw ProbeFailure(code: .usage, message: "unsupported argument")
            }
            index += 1
        }

        guard let suppliedPID else {
            throw ProbeFailure(code: .usage, message: "--pid is required")
        }
        return Arguments(pid: suppliedPID, exerciseControls: exerciseControls)
    }
}

private let usage = "Usage: qa-settings-signals-ax-probe.swift --pid <pid> [--exercise-controls]"
private let maximumNodesPerTarget = 2_000
private let targetTimeout: TimeInterval = 4
private let scrollToVisibleAction = "AXScrollToVisible" as CFString

private let expectedRules: [(id: String, label: String)] = [
    ("work-developer", "developer.*, Work"),
    ("work-figma", "figma, Work"),
    ("work-github", "github, Work"),
    ("work-stackoverflow", "stackoverflow, Work"),
    ("gaming-battle-net", "battle.net, Gaming"),
    ("gaming-playstation", "playstation, Gaming"),
    ("gaming-steam", "steam, Gaming"),
    ("gaming-twitch", "twitch, Gaming"),
    ("gaming-xbox", "xbox, Gaming"),
    ("distraction-instagram", "instagram, Distraction"),
    ("distraction-reddit", "reddit, Distraction"),
    ("distraction-tiktok", "tiktok, Distraction"),
    ("distraction-twitter", "twitter, Distraction"),
    ("distraction-x-home", "x.com/home, Distraction"),
]

private let privacyCopy = "Only built-in rule patterns are shown. Window titles, visited URLs, and browsing history never appear in this review."
private let choices = ["automatic", "work", "communication", "gaming"]

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func identifier(of element: AXUIElement) -> String? {
    stringAttribute(element, kAXIdentifierAttribute as CFString)
}

private func role(of element: AXUIElement) -> String? {
    stringAttribute(element, kAXRoleAttribute as CFString)
}

private func knownStrings(of element: AXUIElement) -> [String] {
    [
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
    ].compactMap { $0 }
}

private func hasExactLabel(_ expected: String, element: AXUIElement) -> Bool {
    knownStrings(of: element).contains(expected)
}

private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
    CFEqual(lhs, rhs)
}

private func boundedWalk(
    from root: AXUIElement,
    targetName: String,
    visit: (AXUIElement) throws -> Bool
) throws -> AXUIElement? {
    let deadline = Date().addingTimeInterval(targetTimeout)
    var stack = [root]
    var visited = Set<CFHashCode>()
    var nodeCount = 0

    while let element = stack.popLast() {
        if Date() >= deadline {
            throw ProbeFailure(code: .timeout, message: "timed out while locating \(targetName)")
        }
        let key = CFHash(element)
        guard visited.insert(key).inserted else { continue }
        nodeCount += 1
        guard nodeCount <= maximumNodesPerTarget else {
            throw ProbeFailure(code: .timeout, message: "node limit reached while locating \(targetName)")
        }
        if try visit(element) { return element }
        stack.append(contentsOf: children(of: element).reversed())
    }
    return nil
}

private func requireTarget(
    in root: AXUIElement,
    name: String,
    code: ExitCode = .assertion,
    matching: (AXUIElement) -> Bool
) throws -> AXUIElement {
    if let match = try boundedWalk(from: root, targetName: name, visit: matching) {
        return match
    }
    throw ProbeFailure(code: code, message: "required target is unavailable: \(name)")
}

private func requireIdentifier(
    _ expected: String,
    in root: AXUIElement,
    code: ExitCode = .assertion
) throws -> AXUIElement {
    try requireTarget(in: root, name: expected, code: code) { identifier(of: $0) == expected }
}

private func press(_ element: AXUIElement, name: String, code: ExitCode) throws {
    _ = AXUIElementPerformAction(element, scrollToVisibleAction)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeFailure(code: code, message: "could not activate \(name)")
    }
}

private func pauseForPresentation() {
    Thread.sleep(forTimeInterval: 0.25)
}

private func requireValue(_ expected: String, element: AXUIElement, name: String) throws {
    guard stringAttribute(element, kAXValueAttribute as CFString) == expected else {
        throw ProbeFailure(code: .assertion, message: "unexpected accessibility value for \(name)")
    }
}

private func subtreeSnapshot(
    root: AXUIElement,
    name: String
) throws -> (identifiers: [String], strings: [String]) {
    var identifiers: [String] = []
    var strings: [String] = []
    _ = try boundedWalk(from: root, targetName: name) { element in
        if let value = identifier(of: element) { identifiers.append(value) }
        strings.append(contentsOf: knownStrings(of: element))
        return false
    }
    return (identifiers, strings)
}

private func singleMainWindow(application: AXUIElement) throws -> AXUIElement {
    guard let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        throw ProbeFailure(code: .attach, message: "the supplied process does not expose application windows")
    }
    let eligible = windows.filter {
        role(of: $0) == (kAXWindowRole as String)
            && boolAttribute($0, kAXMinimizedAttribute as CFString) != true
    }
    guard eligible.count == 1, let window = eligible.first else {
        throw ProbeFailure(code: .window, message: "expected exactly one non-minimized application window")
    }
    if let mainValue = attribute(application, kAXMainWindowAttribute as CFString),
       CFGetTypeID(mainValue) == AXUIElementGetTypeID() {
        let main = unsafeBitCast(mainValue, to: AXUIElement.self)
        if !sameElement(main, window) {
            throw ProbeFailure(code: .window, message: "the single visible window is not the main window")
        }
    }
    return window
}

private func navigateToSignals(window: AXUIElement) throws {
    let settings = try requireTarget(in: window, name: "Settings", code: .navigation) {
        role(of: $0) == (kAXButtonRole as String) && hasExactLabel("Settings", element: $0)
    }
    try press(settings, name: "Settings", code: .navigation)
    pauseForPresentation()

    let signals = try requireTarget(in: window, name: "Signals, Apps and calendars", code: .navigation) {
        role(of: $0) == (kAXButtonRole as String)
            && hasExactLabel("Signals, Apps and calendars", element: $0)
    }
    try press(signals, name: "Settings > Signals", code: .navigation)
    pauseForPresentation()
    try requireValue("Selected", element: signals, name: "Settings > Signals")
}

private func assertDomainRules(window: AXUIElement) throws {
    let toggle = try requireIdentifier("settings.domain-rules.toggle", in: window)
    try requireValue("Collapsed", element: toggle, name: "Domain Rules toggle before expansion")
    try press(toggle, name: "Domain Rules", code: .assertion)
    pauseForPresentation()
    try requireValue("Expanded", element: toggle, name: "Domain Rules toggle after expansion")

    let container = try requireIdentifier("settings.domain-rules", in: window)
    let privacy = try requireIdentifier("settings.domain-rules.privacy", in: container)
    guard knownStrings(of: privacy).contains(privacyCopy) else {
        throw ProbeFailure(code: .assertion, message: "Domain Rules privacy copy does not match the public contract")
    }

    var foundRuleIDs: [String] = []
    for rule in expectedRules {
        let fullID = "settings.domain-rules.rule.\(rule.id)"
        let row = try requireIdentifier(fullID, in: container)
        guard hasExactLabel(rule.label, element: row) else {
            throw ProbeFailure(code: .assertion, message: "Domain Rules row label mismatch for \(rule.id)")
        }
        foundRuleIDs.append(rule.id)
    }

    let snapshot = try subtreeSnapshot(root: container, name: "Domain Rules subtree")
    let orderedIDs = snapshot.identifiers.compactMap { value -> String? in
        let prefix = "settings.domain-rules.rule."
        guard value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }
    guard orderedIDs == foundRuleIDs, foundRuleIDs == expectedRules.map(\.id) else {
        throw ProbeFailure(code: .assertion, message: "Domain Rules must expose exactly 14 ordered public rule identifiers")
    }
    guard snapshot.strings.allSatisfy({ !$0.localizedCaseInsensitiveContains("https://") }) else {
        throw ProbeFailure(code: .assertion, message: "Domain Rules exposed an HTTPS value")
    }
}

private func assertContextRows(window: AXUIElement, exerciseControls: Bool) throws {
    for app in ["discord", "twitch"] {
        let row = try requireIdentifier("settings.app-rules.row.\(app)", in: window)
        let context = try requireIdentifier("settings.app-rules.context.\(app)", in: row)
        let snapshot = try subtreeSnapshot(root: row, name: "\(app) contextual row")
        guard snapshot.strings.contains("AUTO BY CONTEXT") else {
            throw ProbeFailure(code: .assertion, message: "\(app) is missing AUTO BY CONTEXT copy")
        }
        guard knownStrings(of: context).contains(where: { $0.hasPrefix("Uses local window and URL context") }) else {
            throw ProbeFailure(code: .assertion, message: "\(app) contextual explanation is unavailable")
        }

        var controls: [String: AXUIElement] = [:]
        for choice in choices {
            let controlID = "settings.app-rules.\(app).\(choice)"
            controls[choice] = try requireIdentifier(controlID, in: row)
        }

        if exerciseControls {
            do {
                for choice in ["work", "communication", "gaming"] {
                    guard let control = controls[choice] else { continue }
                    try press(control, name: "\(app) \(choice)", code: .action)
                    pauseForPresentation()
                    try requireValue("Selected", element: control, name: "\(app) \(choice)")
                }
            } catch {
                if let automatic = controls["automatic"] {
                    _ = AXUIElementPerformAction(automatic, kAXPressAction as CFString)
                }
                throw error
            }
            guard let automatic = controls["automatic"] else {
                throw ProbeFailure(code: .action, message: "\(app) Automatic control is unavailable for restoration")
            }
            try press(automatic, name: "\(app) Automatic restoration", code: .action)
            pauseForPresentation()
            try requireValue("Selected", element: automatic, name: "\(app) Automatic restoration")
        }
    }
}

private func run() throws {
    let arguments = try Arguments.parse()
    guard AXIsProcessTrusted() else {
        throw ProbeFailure(code: .accessibilityPermission, message: "Accessibility permission is required")
    }
    guard kill(arguments.pid, 0) == 0 else {
        throw ProbeFailure(code: .attach, message: "the supplied process is not running")
    }

    let application = AXUIElementCreateApplication(arguments.pid)
    let window = try singleMainWindow(application: application)
    try navigateToSignals(window: window)
    try assertDomainRules(window: window)
    try assertContextRows(window: window, exerciseControls: arguments.exerciseControls)

    let mode = arguments.exerciseControls ? "controls exercised and restored to Automatic" : "assertion-only"
    print("PASS: Settings > Signals AX contract verified (\(mode))")
}

do {
    try run()
    exit(ExitCode.success.rawValue)
} catch let failure as ProbeFailure {
    fputs("FAIL: \(failure.message)\n", stderr)
    if failure.code == .usage { fputs("\(usage)\n", stderr) }
    exit(failure.code.rawValue)
} catch {
    fputs("FAIL: unexpected verifier error (details redacted)\n", stderr)
    exit(ExitCode.assertion.rawValue)
}
