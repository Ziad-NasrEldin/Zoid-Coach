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
    let actionable: Bool
    let visible: Bool
}

private enum UniqueActionSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private enum FrameMovement: Equatable {
    case closer
    case unchanged
    case farther
}

private struct GeometricCandidate {
    let frame: CGRect
    let actionable: Bool
}

private let mainWindowIdentifier = "zoid-666.main-window"
private let taskTitle = "QA invalid estimate matrix"
private let inputLabel = "Custom estimate for \(taskTitle) in minutes"
private let maximumNodes = 6_000
private let maximumPolls = 80
private let maximumScrollPages = 18
private let scrollDownByPageAction = "AXScrollDownByPage"
private let keyboardBindingSettleMicroseconds: useconds_t = 200_000

private func customTriggerLabel(surfaceName: String) -> String {
    "Enter a custom estimate for \(taskTitle) in \(surfaceName == "dashboard" ? "Plan Editor" : "Today")"
}

private let planEditorModeLabel = "Show Plan Editor estimate controls"

private func exactAXText(_ actual: String, _ expected: String) -> Bool {
    actual.caseInsensitiveCompare(expected) == .orderedSame
}

private func selectUniqueAction(from candidates: [ActionCandidate]) -> UniqueActionSelection {
    let actionable = candidates.indices.filter {
        candidates[$0].actionable && candidates[$0].visible
    }
    guard !actionable.isEmpty else { return .missing }
    guard actionable.count == 1 else { return .ambiguous }
    return .selected(actionable[0])
}

private func distance(_ frame: CGRect, from viewport: CGRect) -> CGFloat {
    if frame.maxY < viewport.minY { return viewport.minY - frame.maxY }
    if frame.minY > viewport.maxY { return frame.minY - viewport.maxY }
    if frame.maxX < viewport.minX { return viewport.minX - frame.maxX }
    if frame.minX > viewport.maxX { return frame.minX - viewport.maxX }
    return 0
}

private func selectNearestAction(
    from candidates: [GeometricCandidate],
    viewport: CGRect
) -> UniqueActionSelection {
    let ranked = candidates.indices
        .filter { candidates[$0].actionable }
        .map { ($0, distance(candidates[$0].frame, from: viewport)) }
        .sorted { $0.1 < $1.1 }
    guard let nearest = ranked.first else { return .missing }
    guard ranked.count == 1 || ranked[1].1 > nearest.1 else { return .ambiguous }
    return .selected(nearest.0)
}

private func frameMovement(
    from before: CGRect,
    to after: CGRect,
    viewport: CGRect
) -> FrameMovement {
    let beforeDistance = distance(before, from: viewport)
    let afterDistance = distance(after, from: viewport)
    if afterDistance < beforeDistance { return .closer }
    if afterDistance > beforeDistance { return .farther }
    return .unchanged
}

private func selectUniqueVisibleScrollSurface(
    from frames: [CGRect],
    viewport: CGRect
) -> UniqueActionSelection {
    let visible = frames.indices.filter { frames[$0].intersects(viewport) }
    guard !visible.isEmpty else { return .missing }
    guard visible.count == 1 else { return .ambiguous }
    return .selected(visible[0])
}

private func mayPostPhysicalScroll(expectedPID: pid_t, frontmostPID: pid_t?) -> Bool {
    frontmostPID == expectedPID
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
          exactAXText(
              "ENTER A CUSTOM ESTIMATE FOR QA INVALID ESTIMATE MATRIX IN PLAN EDITOR",
              customTriggerLabel(surfaceName: "dashboard")
          ),
          exactAXText(
              "ENTER A CUSTOM ESTIMATE FOR QA INVALID ESTIMATE MATRIX IN TODAY",
              customTriggerLabel(surfaceName: "today")
          ),
          !exactAXText(
              "ENTER A CUSTOM ESTIMATE FOR QA INVALID ESTIMATE MATRIX",
              customTriggerLabel(surfaceName: "dashboard")
          ),
          selectUniqueAction(from: []) == .missing,
          selectUniqueAction(from: [ActionCandidate(actionable: false, visible: true)]) == .missing,
          selectUniqueAction(from: [ActionCandidate(actionable: true, visible: false)]) == .missing,
          selectUniqueAction(from: [ActionCandidate(actionable: true, visible: true)]) == .selected(0),
          selectUniqueAction(from: [
              ActionCandidate(actionable: true, visible: false),
              ActionCandidate(actionable: true, visible: true),
          ]) == .selected(1),
          selectUniqueAction(from: [
              ActionCandidate(actionable: true, visible: true),
              ActionCandidate(actionable: true, visible: true),
          ]) == .ambiguous,
          selectNearestAction(
              from: [
                  GeometricCandidate(frame: CGRect(x: 10, y: 101, width: 10, height: 10), actionable: true),
                  GeometricCandidate(frame: CGRect(x: 10, y: 150, width: 10, height: 10), actionable: true),
              ],
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .selected(0),
          selectNearestAction(
              from: [
                  GeometricCandidate(frame: CGRect(x: 10, y: 110, width: 10, height: 10), actionable: true),
                  GeometricCandidate(frame: CGRect(x: 30, y: 110, width: 10, height: 10), actionable: true),
              ],
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .ambiguous,
          selectNearestAction(from: [], viewport: .zero) == .missing,
          frameMovement(
              from: CGRect(x: 10, y: 110, width: 10, height: 10),
              to: CGRect(x: 10, y: 105, width: 10, height: 10),
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .closer,
          frameMovement(
              from: CGRect(x: 10, y: 110, width: 10, height: 10),
              to: CGRect(x: 10, y: 110, width: 10, height: 10),
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .unchanged,
          frameMovement(
              from: CGRect(x: 10, y: 110, width: 10, height: 10),
              to: CGRect(x: 10, y: 115, width: 10, height: 10),
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .farther,
          selectUniqueVisibleScrollSurface(
              from: [CGRect(x: 0, y: 0, width: 50, height: 50)],
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .selected(0),
          selectUniqueVisibleScrollSurface(
              from: [
                  CGRect(x: 0, y: 0, width: 50, height: 50),
                  CGRect(x: 50, y: 0, width: 50, height: 50),
              ],
              viewport: CGRect(x: 0, y: 0, width: 100, height: 100)
          ) == .ambiguous,
          mayPostPhysicalScroll(expectedPID: 123, frontmostPID: 123),
          !mayPostPhysicalScroll(expectedPID: 123, frontmostPID: 456),
          !mayPostPhysicalScroll(expectedPID: 123, frontmostPID: nil),
          keyboardBindingSettleMicroseconds == 200_000,
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
private var surfaceName: String?
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
    case "--surface":
        guard argumentIndex + 1 < arguments.count else {
            fputs("FAIL: --surface requires dashboard or today\n", stderr)
            exit(2)
        }
        surfaceName = arguments[argumentIndex + 1]
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
      let surfaceName,
      ["dashboard", "today"].contains(surfaceName),
      ["open", "submit", "persisted"].contains(phase),
      (phase == "submit") == (caseName != nil)
else {
    fputs("usage: qa-zc011007-invalid-estimate-ax-probe.swift --self-test | --pid <pid> --surface <dashboard|today> --phase <open|submit|persisted> [--case <empty|whitespace|unicode-whitespace|zero|negative|decimal|text|localized-digits|localized-decimal|too-large|valid-padded>] [--forbid <sentinel>]...\n", stderr)
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

private func frame(_ element: AXUIElement) -> CGRect? {
    guard let raw = attribute(element, "AXFrame" as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID(),
          AXValueGetType(unsafeBitCast(raw, to: AXValue.self)) == .cgRect else {
        return nil
    }
    var frame = CGRect.zero
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgRect, &frame) else {
        return nil
    }
    return frame
}

private func isVisible(_ element: AXUIElement, in window: AXUIElement) -> Bool {
    guard let elementFrame = frame(element),
          let windowFrame = frame(window),
          elementFrame.width > 0,
          elementFrame.height > 0 else {
        return false
    }
    return elementFrame.intersects(windowFrame)
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

private func visibleElement(
    in elements: [AXUIElement],
    window: AXUIElement,
    role expectedRole: String? = nil,
    exactLabel: String
) -> AXUIElement? {
    elements.first { candidate in
        (expectedRole == nil || role(candidate) == expectedRole)
            && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
            && isVisible(candidate, in: window)
    }
}

private func uniqueAction(
    in elements: [AXUIElement],
    window: AXUIElement,
    exactLabel: String
) throws -> AXUIElement? {
    let matches = elements.filter { candidate in
        role(candidate) == (kAXButtonRole as String)
            && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
    }
    let traits = matches.map { candidate in
        ActionCandidate(
            actionable: bool(candidate, kAXEnabledAttribute as CFString) != false
                && actionNames(candidate).contains(kAXPressAction as String),
            visible: isVisible(candidate, in: window)
        )
    }
    switch selectUniqueAction(from: traits) {
    case let .selected(index): return matches[index]
    case .missing: return nil
    case .ambiguous:
        throw ProbeError.failure("multiple visible task-specific Custom estimate actions are ambiguous")
    }
}

private func scrollNearestExactActionToVisible(
    in elements: [AXUIElement],
    window: AXUIElement,
    exactLabel: String
) throws -> Bool {
    guard let viewport = frame(window) else { return false }
    let matches = elements.filter { candidate in
        role(candidate) == (kAXButtonRole as String)
            && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
    }
    let framed = matches.compactMap { candidate -> (AXUIElement, GeometricCandidate)? in
        guard let candidateFrame = frame(candidate) else { return nil }
        return (
            candidate,
            GeometricCandidate(
                frame: candidateFrame,
                actionable: bool(candidate, kAXEnabledAttribute as CFString) != false
                    && actionNames(candidate).contains(kAXPressAction as String)
            )
        )
    }
    switch selectNearestAction(from: framed.map(\.1), viewport: viewport) {
    case let .selected(index):
        let targetFrame = framed[index].1.frame
        let scrollFrames = elements.compactMap { candidate -> CGRect? in
            guard role(candidate) == (kAXScrollAreaRole as String),
                  let candidateFrame = frame(candidate) else { return nil }
            return candidateFrame
        }
        let scrollFrame: CGRect
        switch selectUniqueVisibleScrollSurface(from: scrollFrames, viewport: viewport) {
        case let .selected(scrollIndex):
            scrollFrame = scrollFrames[scrollIndex]
        case .missing:
            throw ProbeError.failure("a visible scroll surface is required for physical scroll")
        case .ambiguous:
            throw ProbeError.failure("multiple visible scroll surfaces are ambiguous")
        }
        let scrollPoint = CGPoint(
            x: scrollFrame.midX,
            y: scrollFrame.midY
        )

        func postWheel(_ delta: Int32) throws {
            guard mayPostPhysicalScroll(
                expectedPID: pid,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
            ) else {
                throw ProbeError.failure("installed signed QA app is not frontmost before physical scroll")
            }
            guard frame(window) == viewport else {
                throw ProbeError.failure("main window geometry changed before physical scroll")
            }
            guard let wheel = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: delta,
                wheel2: 0,
                wheel3: 0
            ) else {
                throw ProbeError.failure("unable to construct physical scroll event")
            }
            if let move = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: scrollPoint,
                mouseButton: .left
            ) {
                move.post(tap: .cghidEventTap)
            }
            wheel.location = scrollPoint
            wheel.post(tap: .cghidEventTap)
        }

        func movement(after delta: Int32) throws -> FrameMovement {
            try postWheel(delta)
            usleep(250_000)
            let next = try snapshot(in: window)
            let nextScrollFrames = next.elements.compactMap { candidate -> CGRect? in
                guard role(candidate) == (kAXScrollAreaRole as String),
                      let candidateFrame = frame(candidate) else { return nil }
                return candidateFrame
            }
            guard case let .selected(nextScrollIndex) = selectUniqueVisibleScrollSurface(
                from: nextScrollFrames,
                viewport: viewport
            ), nextScrollFrames[nextScrollIndex] == scrollFrame else {
                throw ProbeError.failure("visible scroll surface identity changed after physical scroll")
            }
            let nextMatches = next.elements.filter { candidate in
                role(candidate) == (kAXButtonRole as String)
                    && labels(candidate).contains(where: { exactAXText($0, exactLabel) })
            }
            let nextCandidates = nextMatches.compactMap { candidate -> GeometricCandidate? in
                guard let candidateFrame = frame(candidate) else { return nil }
                return GeometricCandidate(
                    frame: candidateFrame,
                    actionable: bool(candidate, kAXEnabledAttribute as CFString) != false
                        && actionNames(candidate).contains(kAXPressAction as String)
                )
            }
            switch selectNearestAction(from: nextCandidates, viewport: viewport) {
            case let .selected(nextIndex):
                return frameMovement(
                    from: targetFrame,
                    to: nextCandidates[nextIndex].frame,
                    viewport: viewport
                )
            case .missing:
                throw ProbeError.failure("exact Custom estimate action disappeared after physical scroll")
            case .ambiguous:
                throw ProbeError.failure("multiple equally near Custom estimate controls are ambiguous after physical scroll")
            }
        }

        let preferredDelta: Int32 = targetFrame.midY > viewport.midY ? -420 : 420
        let preferredMovement = try movement(after: preferredDelta)
        switch preferredMovement {
        case .closer:
            return true
        case .farther:
            try postWheel(-preferredDelta)
            usleep(250_000)
            throw ProbeError.failure("physical scroll moved the exact Custom estimate action away from the window")
        case .unchanged:
            let reverseMovement = try movement(after: -preferredDelta)
            switch reverseMovement {
            case .closer:
                return true
            case .farther:
                try postWheel(preferredDelta)
                usleep(250_000)
                throw ProbeError.failure("reverse physical scroll moved the exact Custom estimate action away from the window")
            case .unchanged:
                throw ProbeError.failure("physical scroll did not move the exact Custom estimate action in either direction")
            }
        }
    case .missing:
        return false
    case .ambiguous:
        throw ProbeError.failure("multiple equally near Custom estimate controls are ambiguous")
    }
}

private func findUniqueActionWithBoundedScroll(
    in window: AXUIElement,
    exactLabel: String
) throws -> AXUIElement? {
    for page in 0...maximumScrollPages {
        for _ in 0..<5 {
            let current = try snapshot(in: window)
            if let match = try uniqueAction(in: current.elements, window: window, exactLabel: exactLabel) {
                return match
            }
            usleep(100_000)
        }
        guard page < maximumScrollPages else { break }
        let current = try snapshot(in: window)
        if try scrollNearestExactActionToVisible(
            in: current.elements,
            window: window,
            exactLabel: exactLabel
        ) {
            usleep(250_000)
            continue
        }
        let scrollAreas = current.elements.filter {
            role($0) == (kAXScrollAreaRole as String)
                && actionNames($0).contains(scrollDownByPageAction)
        }
        guard !scrollAreas.isEmpty else {
            usleep(250_000)
            continue
        }
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
        guard scrolled else {
            usleep(250_000)
            continue
        }
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
            if let match = visibleElement(
                in: current.elements,
                window: window,
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
        guard !scrollAreas.isEmpty else {
            usleep(250_000)
            continue
        }
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
        guard scrolled else {
            usleep(250_000)
            continue
        }
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

private func waitForFocusedFieldValue(_ expected: String, field: AXUIElement) throws {
    for _ in 0..<20 {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw ProbeError.failure("installed Zoid 666 app lost frontmost status before keyboard submission")
        }
        if string(field, kAXValueAttribute as CFString) == expected,
           bool(field, kAXFocusedAttribute as CFString) == true {
            return
        }
        usleep(50_000)
    }
    throw ProbeError.failure("physical keyboard input did not reach the focused custom estimate field")
}

private func replaceFocusedFieldAndSubmit(_ value: String, field: AXUIElement) throws {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        throw ProbeError.failure("installed Zoid 666 app is not frontmost before keyboard submission")
    }
    guard CGPreflightPostEventAccess() else {
        throw ProbeError.failure("the verifier lacks permission to post keyboard input")
    }
    try postKey(0, flags: .maskCommand)
    try postKey(51)
    try waitForFocusedFieldValue("", field: field)
    if value.isEmpty {
        try postUnicode("1")
        try waitForFocusedFieldValue("1", field: field)
        try postKey(0, flags: .maskCommand)
        try postKey(51)
        try waitForFocusedFieldValue("", field: field)
    }
    try postUnicode(value)
    try waitForFocusedFieldValue(value, field: field)
    usleep(keyboardBindingSettleMicroseconds)
    try waitForFocusedFieldValue(value, field: field)
    fputs("EVIDENCE: exact focused field revalidated after fixed 200 ms key-to-submit settle\n", stderr)
    try postKey(36)
}

private func waitForEditor(in window: AXUIElement) throws -> AXUIElement {
    for _ in 0..<maximumPolls {
        let current = try snapshot(in: window)
        let fields = current.elements.filter { candidate in
            role(candidate) == kAXTextFieldRole as String
                && labels(candidate).contains(where: { exactAXText($0, inputLabel) })
                && isVisible(candidate, in: window)
        }
        guard fields.count <= 1 else {
            throw ProbeError.failure("multiple visible custom estimate editor fields found: \(fields.count)")
        }
        if let field = fields.first {
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
    var lastValue = "<field missing>"
    var lastFocused = false
    var lastHasError = false
    var lastHasSave = false
    var lastHasCancel = false
    for _ in 0..<maximumPolls {
        let current = try snapshot(in: window)
        guard let field = visibleElement(
            in: current.elements,
            window: window,
            role: kAXTextFieldRole as String,
            exactLabel: inputLabel
        ) else {
            usleep(100_000)
            continue
        }
        let hasError = current.strings.contains(where: { exactAXText($0, expectedError) })
        let value = string(field, kAXValueAttribute as CFString) ?? ""
        let focused = bool(field, kAXFocusedAttribute as CFString) == true
        let hasSave = current.strings.contains(where: { exactAXText($0, "SAVE") })
        let hasCancel = current.strings.contains(where: { exactAXText($0, "CANCEL") })
        lastValue = value
        lastFocused = focused
        lastHasError = hasError
        lastHasSave = hasSave
        lastHasCancel = hasCancel
        if hasError, value == estimateCase.input, focused {
            guard hasSave, hasCancel else {
                throw ProbeError.failure("invalid estimate did not keep correction controls available")
            }
            guard !current.strings.contains(where: { exactAXText($0, "Time estimate confirmed: 25 MIN") }) else {
                throw ProbeError.failure("invalid estimate incorrectly exposed a confirmed value")
            }
            return
        }
        usleep(100_000)
    }
    throw ProbeError.failure(
        "invalid estimate result mismatch: expectedValue=\(String(reflecting: estimateCase.input)) "
            + "observedValue=\(String(reflecting: lastValue)) focused=\(lastFocused) "
            + "error=\(lastHasError) save=\(lastHasSave) cancel=\(lastHasCancel)"
    )
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
        let editor = visibleElement(
            in: current.elements,
            window: window,
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
        if surfaceName == "dashboard" {
            let current = try snapshot(in: window)
            guard let modeButton = try uniqueAction(
                in: current.elements,
                window: window,
                exactLabel: planEditorModeLabel
            ) else {
                throw ProbeError.failure("Plan Editor mode control is unavailable")
            }
            guard AXUIElementPerformAction(modeButton, kAXPressAction as CFString) == .success else {
                throw ProbeError.failure("Plan Editor mode control could not be selected")
            }
            usleep(250_000)
            try assertPrivacy(window)
        }
        guard let trigger = try findUniqueActionWithBoundedScroll(
            in: window,
            exactLabel: customTriggerLabel(surfaceName: surfaceName)
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
        try replaceFocusedFieldAndSubmit(selectedCase.input, field: field)
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
        guard visibleElement(
            in: current.elements,
            window: window,
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
