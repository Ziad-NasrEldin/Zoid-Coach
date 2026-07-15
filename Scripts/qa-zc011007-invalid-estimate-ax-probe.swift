#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let visible: Bool
    let hasToday: Bool
    let hasReviews: Bool
}

private enum MainSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private struct EstimateCase: Equatable {
    let input: String
    let expectedError: String?
    let expectedMinutes: Int?
}

private struct ActionCandidate: Equatable {
    let identity: String
    let actionable: Bool
}

private enum UniqueActionSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private let mainWindowIdentifier = "zoid-666.main-window"
private let taskTitle = "QA invalid estimate matrix"
private let customTriggerLabel = "Enter a custom estimate for \(taskTitle)"
private let inputLabel = "Custom estimate for \(taskTitle) in minutes"
private let maximumNodes = 6_000
private let maximumPolls = 80
private let maximumScrollPages = 18
private let scrollDownByPageAction = "AXScrollDownByPage"

private func exactAXText(_ actual: String, _ expected: String) -> Bool {
    actual.caseInsensitiveCompare(expected) == .orderedSame
}

private func selectUniqueAction(from candidates: [ActionCandidate]) -> UniqueActionSelection {
    let actionable = candidates.indices.filter { candidates[$0].actionable }
    guard !actionable.isEmpty else { return .missing }
    let identities = Set(actionable.map { candidates[$0].identity })
    guard identities.count == 1 else { return .ambiguous }
    return .selected(actionable[0])
}

private func estimateCase(named name: String) -> EstimateCase? {
    switch name {
    case "empty":
        EstimateCase(input: "", expectedError: "Enter an estimate in minutes.", expectedMinutes: nil)
    case "whitespace":
        EstimateCase(input: "   ", expectedError: "Enter an estimate in minutes.", expectedMinutes: nil)
    case "unicode-whitespace":
        EstimateCase(input: "\u{00A0}\u{2007}", expectedError: "Enter an estimate in minutes.", expectedMinutes: nil)
    case "zero":
        EstimateCase(input: "0", expectedError: "Estimate must be at least 1 minute.", expectedMinutes: nil)
    case "negative":
        EstimateCase(input: "-15", expectedError: "Estimate must be at least 1 minute.", expectedMinutes: nil)
    case "decimal":
        EstimateCase(input: "1.5", expectedError: "Use a whole number of minutes, such as 25.", expectedMinutes: nil)
    case "text":
        EstimateCase(input: "tomorrow", expectedError: "Use a whole number of minutes, such as 25.", expectedMinutes: nil)
    case "localized-digits":
        EstimateCase(input: "٢٥", expectedError: "Use a whole number of minutes, such as 25.", expectedMinutes: nil)
    case "localized-decimal":
        EstimateCase(input: "25,0", expectedError: "Use a whole number of minutes, such as 25.", expectedMinutes: nil)
    case "too-large":
        EstimateCase(input: "481", expectedError: "Estimate must be 480 minutes or less. Split larger work into smaller tasks.", expectedMinutes: nil)
    case "valid-padded":
        EstimateCase(input: " 25 ", expectedError: nil, expectedMinutes: 25)
    default:
        nil
    }
}

private func selectMainWindow(from windows: [WindowTraits]) -> MainSelection {
    let candidates = windows.indices.filter { index in
        let window = windows[index]
        guard !window.minimized, window.visible else { return false }
        return window.identifier == mainWindowIdentifier || (window.hasToday && window.hasReviews)
    }
    switch candidates.count {
    case 1: return .selected(candidates[0])
    case 0: return .missing
    default: return .ambiguous
    }
}

private func containsForbidden(_ strings: [String], forbidden: [String]) -> Bool {
    strings.contains { value in
        forbidden.contains { sentinel in
            value.localizedCaseInsensitiveContains(sentinel)
        }
    }
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
    let main = WindowTraits(
        identifier: mainWindowIdentifier,
        minimized: false,
        visible: true,
        hasToday: true,
        hasReviews: true
    )
    let fallback = WindowTraits(
        identifier: nil,
        minimized: false,
        visible: true,
        hasToday: true,
        hasReviews: true
    )
    let auxiliary = WindowTraits(
        identifier: "agent-lifecycle",
        minimized: false,
        visible: true,
        hasToday: false,
        hasReviews: false
    )
    guard selectMainWindow(from: [main, auxiliary]) == .selected(0),
          selectMainWindow(from: [auxiliary, fallback]) == .selected(1),
          selectMainWindow(from: [main, fallback]) == .ambiguous,
          estimateCase(named: "empty")?.expectedError == "Enter an estimate in minutes.",
          estimateCase(named: "zero")?.expectedError?.contains("at least 1 minute") == true,
          estimateCase(named: "negative")?.expectedError == estimateCase(named: "zero")?.expectedError,
          estimateCase(named: "decimal")?.expectedError?.contains("whole number") == true,
          estimateCase(named: "localized-digits")?.input == "٢٥",
          estimateCase(named: "localized-decimal")?.input == "25,0",
          estimateCase(named: "too-large")?.expectedError?.contains("480 minutes or less") == true,
          estimateCase(named: "valid-padded")?.expectedMinutes == 25,
          estimateCase(named: "valid-padded")?.expectedError == nil,
          estimateCase(named: "missing") == nil,
          exactAXText("ENTER A CUSTOM ESTIMATE FOR QA INVALID ESTIMATE MATRIX", customTriggerLabel),
          !exactAXText("ENTER A CUSTOM ESTIMATE FOR QA INVALID ESTIMATE MATRIX!", customTriggerLabel),
          selectUniqueAction(from: []) == .missing,
          selectUniqueAction(from: [ActionCandidate(identity: "custom", actionable: false)]) == .missing,
          selectUniqueAction(from: [ActionCandidate(identity: "custom", actionable: true)]) == .selected(0),
          selectUniqueAction(from: [
              ActionCandidate(identity: "custom", actionable: true),
              ActionCandidate(identity: "custom", actionable: true),
          ]) == .selected(0),
          selectUniqueAction(from: [
              ActionCandidate(identity: "custom-a", actionable: true),
              ActionCandidate(identity: "custom-b", actionable: true),
          ]) == .ambiguous,
          containsForbidden(["private QA-ZC011007-private-estimate-note"], forbidden: ["qa-zc011007-private-estimate-note"]),
          !containsForbidden(["Time estimate confirmed: 25 MIN"], forbidden: ["qa-zc011007-private-estimate-note"])
    else {
        fputs("FAIL: ZC-011-007 invalid-estimate AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-011-007 invalid-estimate AX probe self-test")
    exit(0)
}

private var pid: pid_t?
private var phase: String?
private var caseName: String?
private var forbidden: [String] = []
private var argumentIndex = 1
private let arguments = CommandLine.arguments
while argumentIndex < arguments.count {
    switch arguments[argumentIndex] {
    case "--pid":
        guard argumentIndex + 1 < arguments.count,
              let value = Int32(arguments[argumentIndex + 1])
        else {
            fputs("FAIL: --pid requires a numeric process ID\n", stderr)
            exit(2)
        }
        pid = value
        argumentIndex += 2
    case "--phase":
        guard argumentIndex + 1 < arguments.count else {
            fputs("FAIL: --phase requires a value\n", stderr)
            exit(2)
        }
        phase = arguments[argumentIndex + 1]
        argumentIndex += 2
    case "--case":
        guard argumentIndex + 1 < arguments.count else {
            fputs("FAIL: --case requires a value\n", stderr)
            exit(2)
        }
        caseName = arguments[argumentIndex + 1]
        argumentIndex += 2
    case "--forbid":
        guard argumentIndex + 1 < arguments.count else {
            fputs("FAIL: --forbid requires a value\n", stderr)
            exit(2)
        }
        forbidden.append(arguments[argumentIndex + 1])
        argumentIndex += 2
    default:
        fputs("FAIL: unsupported argument \(arguments[argumentIndex])\n", stderr)
        exit(2)
    }
}

guard let pid,
      let phase,
      ["open", "submit", "persisted"].contains(phase),
      (phase == "submit") == (caseName != nil)
else {
    fputs("usage: qa-zc011007-invalid-estimate-ax-probe.swift --self-test | --pid <pid> --phase <open|submit|persisted> [--case <empty|whitespace|unicode-whitespace|zero|negative|decimal|text|localized-digits|localized-decimal|too-large|valid-padded>] [--forbid <sentinel>]...\n", stderr)
    exit(2)
}

private let selectedCase = caseName.flatMap(estimateCase(named:))
if phase == "submit", selectedCase == nil {
    fputs("FAIL: unsupported estimate case \(caseName ?? "")\n", stderr)
    exit(2)
}

private let application = AXUIElementCreateApplication(pid)

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
}

private func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute as CFString)
}

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func actionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func walk(root: AXUIElement, visit: (AXUIElement) -> Void) throws {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw ProbeError.failure("AX traversal exceeded \(maximumNodes) nodes")
        }
        visit(element)
        queue.append(contentsOf: children(element))
    }
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("Accessibility permission is required for the verifier")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeError.failure("the supplied installed-app process is not running")
    }
    let windows = ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter { role($0) == (kAXWindowRole as String) }
    let traits = try windows.map { window in
        var navigation = Set<String>()
        try walk(root: window) { element in
            guard role(element) == (kAXButtonRole as String) else { return }
            navigation.formUnion(labels(element))
        }
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            visible: bool(window, "AXVisible" as CFString) != false,
            hasToday: navigation.contains("Today"),
            hasReviews: navigation.contains("Reviews")
        )
    }
    switch selectMainWindow(from: traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}

private func snapshot(in window: AXUIElement) throws -> (elements: [AXUIElement], strings: [String]) {
    var elements: [AXUIElement] = []
    var strings: [String] = []
    try walk(root: window) { element in
        elements.append(element)
        strings.append(contentsOf: labels(element))
    }
    return (elements, strings)
}

private func element(
    in elements: [AXUIElement],
    role expectedRole: String? = nil,
    exactLabel: String
) -> AXUIElement? {
    elements.first { candidate in
        (expectedRole == nil || role(candidate) == expectedRole)
            && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
    }
}

private func uniqueAction(
    in elements: [AXUIElement],
    exactLabel: String
) throws -> AXUIElement? {
    let matches = elements.filter { candidate in
        role(candidate) == (kAXButtonRole as String)
            && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
    }
    let traits = matches.map { candidate in
        ActionCandidate(
            identity: identifier(candidate) ?? exactLabel.lowercased(),
            actionable: bool(candidate, kAXEnabledAttribute as CFString) != false
                && actionNames(candidate).contains(kAXPressAction as String)
        )
    }
    switch selectUniqueAction(from: traits) {
    case let .selected(index): return matches[index]
    case .missing: return nil
    case .ambiguous:
        throw ProbeError.failure("multiple distinct actionable Custom estimate controls are ambiguous")
    }
}

private func findUniqueActionWithBoundedScroll(
    in window: AXUIElement,
    exactLabel: String
) throws -> AXUIElement? {
    for page in 0...maximumScrollPages {
        for _ in 0..<5 {
            let current = try snapshot(in: window)
            if let match = try uniqueAction(in: current.elements, exactLabel: exactLabel) {
                return match
            }
            usleep(100_000)
        }
        guard page < maximumScrollPages else { break }
        let current = try snapshot(in: window)
        let scrollAreas = current.elements.filter {
            role($0) == (kAXScrollAreaRole as String)
                && actionNames($0).contains(scrollDownByPageAction)
        }
        guard !scrollAreas.isEmpty else { break }
        var scrolled = false
        for scrollArea in scrollAreas {
            _ = AXUIElementSetAttributeValue(
                scrollArea,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if AXUIElementPerformAction(scrollArea, scrollDownByPageAction as CFString) == .success {
                scrolled = true
            }
        }
        guard scrolled else { break }
        usleep(250_000)
    }
    return nil
}

private func findElementWithBoundedScroll(
    in window: AXUIElement,
    role expectedRole: String? = nil,
    exactLabel: String
) throws -> AXUIElement? {
    for page in 0...maximumScrollPages {
        for _ in 0..<5 {
            let current = try snapshot(in: window)
            if let match = element(
                in: current.elements,
                role: expectedRole,
                exactLabel: exactLabel
            ) {
                return match
            }
            usleep(100_000)
        }
        guard page < maximumScrollPages else { break }
        let current = try snapshot(in: window)
        let scrollAreas = current.elements.filter {
            role($0) == (kAXScrollAreaRole as String)
                && actionNames($0).contains(scrollDownByPageAction)
        }
        guard !scrollAreas.isEmpty else { break }
        var scrolled = false
        for scrollArea in scrollAreas {
            _ = AXUIElementSetAttributeValue(
                scrollArea,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if AXUIElementPerformAction(scrollArea, scrollDownByPageAction as CFString) == .success {
                scrolled = true
            }
        }
        guard scrolled else { break }
        usleep(250_000)
    }
    return nil
}

private func assertPrivacy(_ window: AXUIElement) throws {
    let exposed = try snapshot(in: window).strings
    if containsForbidden(exposed, forbidden: forbidden) {
        throw ProbeError.failure("private fixture, database, or QA-root evidence escaped into the accessibility tree")
    }
}

private func setFocused(_ element: AXUIElement) throws {
    let result = AXUIElementSetAttributeValue(
        element,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
    )
    guard result == .success else {
        throw ProbeError.failure("custom estimate field could not receive keyboard focus")
    }
}

private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else {
        throw ProbeError.failure("unable to construct keyboard event")
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
    usleep(40_000)
}

private func postUnicode(_ value: String) throws {
    guard !value.isEmpty else { return }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
        throw ProbeError.failure("unable to construct Unicode keyboard event")
    }
    let units = Array(value.utf16)
    units.withUnsafeBufferPointer { buffer in
        down.keyboardSetUnicodeString(
            stringLength: buffer.count,
            unicodeString: buffer.baseAddress
        )
    }
    down.post(tap: .cghidEventTap)
    usleep(50_000)
    up.post(tap: .cghidEventTap)
    usleep(50_000)
}

private func replaceFocusedFieldAndSubmit(_ value: String) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        throw ProbeError.failure("installed Zoid 666 app is not frontmost before keyboard submission")
    }
    guard CGPreflightPostEventAccess() else {
        throw ProbeError.failure("the verifier lacks permission to post keyboard input")
    }
    try postKey(0, flags: .maskCommand)
    try postKey(51)
    try postUnicode(value)
    try postKey(36)
}

private func waitForEditor(in window: AXUIElement) throws -> AXUIElement {
    for _ in 0..<maximumPolls {
        let current = try snapshot(in: window)
        if let field = element(
            in: current.elements,
            role: kAXTextFieldRole as String,
            exactLabel: inputLabel
        ) {
            return field
        }
        usleep(100_000)
    }
    throw ProbeError.failure("custom estimate editor did not appear")
}

private func assertInvalidResult(
    _ estimateCase: EstimateCase,
    in window: AXUIElement
) throws {
    guard let expectedError = estimateCase.expectedError else {
        throw ProbeError.failure("invalid assertion received a valid case")
    }
    for _ in 0..<maximumPolls {
        let current = try snapshot(in: window)
        guard let field = element(
            in: current.elements,
            role: kAXTextFieldRole as String,
            exactLabel: inputLabel
        ) else {
            usleep(100_000)
            continue
        }
        let hasError = current.strings.contains(where: { exactAXText($0, expectedError) })
        let value = string(field, kAXValueAttribute as CFString) ?? ""
        if hasError, value == estimateCase.input, bool(field, kAXFocusedAttribute as CFString) == true {
            guard current.strings.contains(where: { exactAXText($0, "SAVE") }),
                  current.strings.contains(where: { exactAXText($0, "CANCEL") }) else {
                throw ProbeError.failure("invalid estimate did not keep correction controls available")
            }
            guard !current.strings.contains(where: { exactAXText($0, "Time estimate confirmed: 25 MIN") }) else {
                throw ProbeError.failure("invalid estimate incorrectly exposed a confirmed value")
            }
            return
        }
        usleep(100_000)
    }
    throw ProbeError.failure("invalid estimate did not retain exact input, focus, and corrective error copy")
}

private func assertValidResult(
    _ estimateCase: EstimateCase,
    in window: AXUIElement
) throws {
    guard let minutes = estimateCase.expectedMinutes else {
        throw ProbeError.failure("valid assertion received an invalid case")
    }
    let expected = "Time estimate confirmed: \(minutes) MIN"
    for _ in 0..<maximumPolls {
        let current = try snapshot(in: window)
        let editor = element(
            in: current.elements,
            role: kAXTextFieldRole as String,
            exactLabel: inputLabel
        )
        if current.strings.contains(where: { exactAXText($0, expected) }), editor == nil {
            let knownErrors = [
                "Enter an estimate in minutes.",
                "Estimate must be at least 1 minute.",
                "Use a whole number of minutes, such as 25.",
                "Estimate must be 480 minutes or less. Split larger work into smaller tasks.",
            ]
            guard knownErrors.allSatisfy({ expectedError in
                !current.strings.contains(where: { exactAXText($0, expectedError) })
            }) else {
                throw ProbeError.failure("valid correction left stale validation copy visible")
            }
            return
        }
        usleep(100_000)
    }
    throw ProbeError.failure("valid padded correction did not close the editor and confirm 25 minutes")
}

do {
    let window = try mainWindow()
    try assertPrivacy(window)
    switch phase {
    case "open":
        guard let trigger = try findUniqueActionWithBoundedScroll(
            in: window,
            exactLabel: customTriggerLabel
        ) else {
            throw ProbeError.failure("task-specific Custom estimate action is unavailable")
        }
        guard AXUIElementPerformAction(trigger, kAXPressAction as CFString) == .success else {
            throw ProbeError.failure("task-specific Custom estimate action could not open")
        }
        let field = try waitForEditor(in: window)
        try setFocused(field)
        try assertPrivacy(window)
        print("PASS: task-specific custom estimate editor opened with accessible field and keyboard focus")
    case "submit":
        guard let selectedCase else {
            throw ProbeError.failure("estimate case is missing")
        }
        let field = try waitForEditor(in: window)
        try setFocused(field)
        try replaceFocusedFieldAndSubmit(selectedCase.input)
        if selectedCase.expectedError != nil {
            try assertInvalidResult(selectedCase, in: window)
            print("PASS: \(caseName ?? "") kept exact input, focus, correction controls, and error copy after Return")
        } else {
            try assertValidResult(selectedCase, in: window)
            print("PASS: valid padded correction submitted with Return and confirmed 25 minutes")
        }
        try assertPrivacy(window)
    case "persisted":
        guard let confirmed = try findElementWithBoundedScroll(
            in: window,
            exactLabel: "Time estimate confirmed: 25 MIN"
        ) else {
            throw ProbeError.failure("persisted 25-minute estimate is unavailable after ordinary relaunch")
        }
        guard bool(confirmed, kAXEnabledAttribute as CFString) != false else {
            throw ProbeError.failure("persisted estimate is exposed only through a disabled accessibility element")
        }
        let current = try snapshot(in: window)
        guard element(
            in: current.elements,
            role: kAXTextFieldRole as String,
            exactLabel: inputLabel
        ) == nil else {
            throw ProbeError.failure("custom editor unexpectedly remained open after relaunch")
        }
        try assertPrivacy(window)
        print("PASS: valid estimate remained confirmed after ordinary relaunch with privacy-safe accessibility")
    default:
        throw ProbeError.failure("unsupported phase")
    }
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
