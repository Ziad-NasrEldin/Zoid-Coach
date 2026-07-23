import ApplicationServices
import AppKit
import Darwin
import Foundation

enum VisibilityProbeError: Error, CustomStringConvertible, Equatable {
    case usage
    case foregroundDidNotRemainVisible
    case backgroundBecameHidden
    case backgroundWindowPersisted
    case backgroundWindowReappeared
    case statusItemUnavailable
    case processExited
    case accessibilityUnavailable
    case controlCenterUnavailable
    case controlCenterAccessibilityUnavailable
    case statusItemPressFailed
    case coachPopoverUnavailable

    var description: String {
        switch self {
        case .usage:
            "usage: qa-app-visibility-probe.swift <pid> <foreground-visible|background-windowless-menu-ready> <timeout-seconds> | --self-test"
        case .foregroundDidNotRemainVisible:
            "RED: foreground launch did not remain visible for the complete observation window"
        case .backgroundBecameHidden:
            "RED: --background-schedule hid the application and made its status item unusable"
        case .backgroundWindowPersisted:
            "RED: --background-schedule retained a normal application window for the complete observation window"
        case .backgroundWindowReappeared:
            "RED: --background-schedule showed a normal application window after becoming stably windowless"
        case .statusItemUnavailable:
            "RED: --background-schedule did not retain a stable status item"
        case .processExited:
            "RED: target application process exited during visibility verification"
        case .accessibilityUnavailable:
            "RED: target application window accessibility state was unavailable"
        case .controlCenterUnavailable:
            "RED: ControlCenter was unavailable while verifying the status item"
        case .controlCenterAccessibilityUnavailable:
            "RED: ControlCenter status-item accessibility state was unavailable"
        case .statusItemPressFailed:
            "RED: the matched native status item could not be pressed"
        case .coachPopoverUnavailable:
            "RED: pressing the native status item did not expose AXSystemDialog containing menu-bar.coach"
        }
    }

    var exitCode: Int32 {
        switch self {
        case .usage: 2
        case .foregroundDidNotRemainVisible: 10
        case .backgroundBecameHidden: 11
        case .backgroundWindowPersisted: 12
        case .backgroundWindowReappeared: 13
        case .statusItemUnavailable: 14
        case .processExited: 15
        case .accessibilityUnavailable: 16
        case .controlCenterUnavailable: 17
        case .controlCenterAccessibilityUnavailable: 18
        case .statusItemPressFailed: 19
        case .coachPopoverUnavailable: 21
        }
    }
}

enum WindowSample: Equatable {
    case availableEmpty
    case availableNonempty
    case unavailable
}

struct BackgroundVisibilityState {
    static let stableWindowlessInterval: TimeInterval = 0.5

    private(set) var sawWindow = false
    private(set) var becameStablyWindowless = false
    private(set) var retainedStatusItem = false
    private var emptyStartedAt: TimeInterval?

    mutating func observe(
        windows: WindowSample,
        hasStatusItem: Bool,
        elapsed: TimeInterval
    ) -> VisibilityProbeError? {
        switch windows {
        case .unavailable:
            return .accessibilityUnavailable
        case .availableNonempty:
            if becameStablyWindowless {
                return .backgroundWindowReappeared
            }
            sawWindow = true
            emptyStartedAt = nil
        case .availableEmpty:
            if becameStablyWindowless, !hasStatusItem {
                return .statusItemUnavailable
            }
            retainedStatusItem = retainedStatusItem || hasStatusItem
            if emptyStartedAt == nil {
                emptyStartedAt = elapsed
            }
            if let emptyStartedAt,
               elapsed - emptyStartedAt >= Self.stableWindowlessInterval,
               retainedStatusItem {
                becameStablyWindowless = true
            }
        }
        return nil
    }

    func finalError() -> VisibilityProbeError? {
        if becameStablyWindowless { return nil }
        if sawWindow { return .backgroundWindowPersisted }
        return .statusItemUnavailable
    }
}

private let maximumDiagnosticWindows = 24
private let diagnosticTimeLimit: TimeInterval = 0.25
private let knownWindowTitles = Set(["Zoid 666", "Zoid 666 QA", "Background Agent"])
private let controlCenterBundleIdentifier = "com.apple.controlcenter"
private let systemEventsBundleIdentifier = "com.apple.systemevents"
private let statusItemAccessibilityIdentifier = "menu-bar.status-item"
private let statusItemTitle = "Zoid 666"
private let coachPopoverAccessibilityIdentifier = "menu-bar.coach"
private let maximumStatusNodes = 4_096
private let maximumStatusDepth = 16
private let statusScanTimeLimit: TimeInterval = 2

enum StatusItemSample: Equatable {
    case present
    case missing
    case controlCenterUnavailable
    case accessibilityUnavailable
}

struct StatusItemSource {
    let sample: () -> StatusItemSample
}

struct StatusItemCandidate: Equatable {
    let identifier: String?
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let help: String?
    let stringValue: String?

    var semanticFields: [String] {
        [title, description, help, stringValue].compactMap { $0 }
    }
}

struct LocatedStatusItem {
    let source: String
    let element: AXUIElement
    let semantics: StatusItemCandidate
    let frame: CGRect?
}

func statusItemIsPresent(in candidates: [StatusItemCandidate]) -> Bool {
    if candidates.contains(where: { $0.identifier == statusItemAccessibilityIdentifier }) {
        return true
    }
    return candidates.contains { candidate in
        candidate.semanticFields.contains { field in
            field == statusItemTitle || field.hasPrefix("\(statusItemTitle),")
        }
    }
}

func statusItemObservation(
    from source: StatusItemSource
) -> (hasStatusItem: Bool, failure: VisibilityProbeError) {
    switch source.sample() {
    case .present:
        return (true, .statusItemUnavailable)
    case .missing:
        return (false, .statusItemUnavailable)
    case .controlCenterUnavailable:
        return (false, .controlCenterUnavailable)
    case .accessibilityUnavailable:
        return (false, .controlCenterAccessibilityUnavailable)
    }
}

func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
    return result
}

func isHidden(_ application: AXUIElement) -> Bool {
    (value(application, kAXHiddenAttribute as CFString) as? Bool) ?? false
}

func windowSample(_ application: AXUIElement) -> WindowSample {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        application,
        kAXWindowsAttribute as CFString,
        &result
    ) == .success,
          let windows = result as? [AXUIElement]
    else {
        return .unavailable
    }
    return windows.isEmpty ? .availableEmpty : .availableNonempty
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    if let string = value(element, attribute) as? String { return string }
    return (value(element, attribute) as? NSNumber)?.stringValue
}

func frameAttribute(_ element: AXUIElement) -> CGRect? {
    guard let raw = value(element, "AXFrame" as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID(),
          AXValueGetType(raw as! AXValue) == .cgRect
    else { return nil }
    var frame = CGRect.zero
    guard AXValueGetValue(raw as! AXValue, .cgRect, &frame) else { return nil }
    return frame
}

func statusSemantics(_ element: AXUIElement) -> StatusItemCandidate {
    StatusItemCandidate(
        identifier: stringAttribute(element, kAXIdentifierAttribute as CFString),
        role: stringAttribute(element, kAXRoleAttribute as CFString),
        subrole: stringAttribute(element, kAXSubroleAttribute as CFString),
        title: stringAttribute(element, kAXTitleAttribute as CFString),
        description: stringAttribute(element, kAXDescriptionAttribute as CFString),
        help: stringAttribute(element, kAXHelpAttribute as CFString),
        stringValue: stringAttribute(element, kAXValueAttribute as CFString)
    )
}

func boundedHierarchy(
    root: AXUIElement,
    source: String,
    initialDepth: Int = 0
) -> [LocatedStatusItem] {
    let deadline = Date().addingTimeInterval(statusScanTimeLimit)
    var queue: [(AXUIElement, Int)] = [(root, initialDepth)]
    var index = 0
    var result: [LocatedStatusItem] = []
    while index < queue.count,
          index < maximumStatusNodes,
          Date() < deadline {
        let (element, depth) = queue[index]
        index += 1
        result.append(LocatedStatusItem(
            source: source,
            element: element,
            semantics: statusSemantics(element),
            frame: frameAttribute(element)
        ))
        guard depth < maximumStatusDepth,
              let children = value(element, kAXChildrenAttribute as CFString) as? [AXUIElement]
        else { continue }
        for child in children where queue.count < maximumStatusNodes {
            queue.append((child, depth + 1))
        }
    }
    return result
}

func statusItemCandidates(in application: AXUIElement, source: String) -> [LocatedStatusItem]? {
    var menuBarValue: CFTypeRef?
    let extrasResult = AXUIElementCopyAttributeValue(
        application,
        kAXExtrasMenuBarAttribute as CFString,
        &menuBarValue
    )
    if extrasResult == .success, let menuBar = menuBarValue as! AXUIElement? {
        return boundedHierarchy(root: menuBar, source: "\(source).AXExtrasMenuBar")
    }
    let fallback = boundedHierarchy(root: application, source: "\(source).hierarchy")
    return fallback.isEmpty ? nil : fallback
}

func liveStatusItem(pid: Int32) -> (item: LocatedStatusItem?, failure: VisibilityProbeError) {
    var sources: [(String, AXUIElement)] = [("target-pid-\(pid)", AXUIElementCreateApplication(pid))]
    for (name, bundleIdentifier) in [
        ("ControlCenter", controlCenterBundleIdentifier),
        ("System Events", systemEventsBundleIdentifier),
    ] {
        if let process = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            sources.append((name, AXUIElementCreateApplication(process.processIdentifier)))
        }
    }

    var scannedAny = false
    for (source, application) in sources {
        guard let located = statusItemCandidates(in: application, source: source) else { continue }
        scannedAny = true
        if let match = located.first(where: { statusItemIsPresent(in: [$0.semantics]) }) {
            return (match, .statusItemUnavailable)
        }
    }
    if !scannedAny { return (nil, .controlCenterAccessibilityUnavailable) }
    if sources.count == 1 { return (nil, .controlCenterUnavailable) }
    return (nil, .statusItemUnavailable)
}

func diagnosticString(for item: LocatedStatusItem) -> String {
    let semantic = item.semantics
    let frame = item.frame.map {
        "x=\(Int($0.origin.x)) y=\(Int($0.origin.y)) w=\(Int($0.width)) h=\(Int($0.height))"
    } ?? "unknown"
    return "DIAGNOSTIC: status-item source=\(item.source) role=\(semantic.role ?? "unknown") "
        + "subrole=\(semantic.subrole ?? "unknown") identifier=\(semantic.identifier ?? "unknown") "
        + "title=\(semantic.title ?? "unknown") description=\(semantic.description ?? "unknown") "
        + "help=\(semantic.help ?? "unknown") value=\(semantic.stringValue ?? "unknown") frame=\(frame)"
}

func pressStatusItem(_ item: LocatedStatusItem) -> Bool {
    if AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success { return true }
    guard let frame = item.frame, frame.width > 0, frame.height > 0 else { return false }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    guard let down = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: point,
        mouseButton: .left
    ),
          let up = CGEvent(
              mouseEventSource: nil,
              mouseType: .leftMouseUp,
              mouseCursorPosition: point,
              mouseButton: .left
          )
    else { return false }
    down.post(tap: CGEventTapLocation.cghidEventTap)
    up.post(tap: CGEventTapLocation.cghidEventTap)
    return true
}

func coachPopoverIsPresent(in application: AXUIElement) -> Bool {
    let nodes = boundedHierarchy(root: application, source: "target-popover")
    for dialog in nodes where dialog.semantics.role == "AXSystemDialog" {
        let descendants = boundedHierarchy(root: dialog.element, source: "target-popover.AXSystemDialog")
        if descendants.contains(where: {
            $0.semantics.identifier == coachPopoverAccessibilityIdentifier
        }) {
            return true
        }
    }
    return false
}

func processIsAlive(_ pid: Int32) -> Bool {
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

func attributeDescription(_ element: AXUIElement, _ attribute: CFString) -> String {
    guard let result = value(element, attribute) else { return "unknown" }
    if let flag = result as? Bool { return flag ? "true" : "false" }
    if let number = result as? NSNumber { return number.stringValue }
    return "unknown"
}

func privacySafeWindowDiagnostics(_ application: AXUIElement, expectedPID: Int32) -> String {
    guard let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        return "DIAGNOSTIC: candidate-windows pid=\(expectedPID) unavailable"
    }

    let deadline = Date().addingTimeInterval(diagnosticTimeLimit)
    var lines = ["DIAGNOSTIC: candidate-windows pid=\(expectedPID) count=\(windows.count)"]
    var emitted = 0
    for (index, window) in windows.prefix(maximumDiagnosticWindows).enumerated() {
        guard Date() < deadline else { break }
        var windowPID: pid_t = 0
        let pidResult = AXUIElementGetPid(window, &windowPID)
        let reportedPID = pidResult == .success ? String(windowPID) : "unknown"
        let role = (value(window, kAXRoleAttribute as CFString) as? String) ?? "unknown"
        let rawTitle = (value(window, kAXTitleAttribute as CFString) as? String) ?? ""
        let title = knownWindowTitles.contains(rawTitle) ? rawTitle : "<redacted>"
        let level = attributeDescription(window, "AXWindowLevel" as CFString)
        let visible = attributeDescription(window, "AXVisible" as CFString)
        let key = attributeDescription(window, kAXFocusedAttribute as CFString)
        let main = attributeDescription(window, kAXMainAttribute as CFString)
        let minimized = attributeDescription(window, kAXMinimizedAttribute as CFString)
        lines.append(
            "DIAGNOSTIC: window[\(index)] role=\(role) title=\(title) level=\(level) "
                + "visible=\(visible) key=\(key) main=\(main) minimized=\(minimized) pid=\(reportedPID)"
        )
        emitted += 1
    }
    if emitted < windows.count {
        lines.append("DIAGNOSTIC: omitted=\(windows.count - emitted) bounded=true")
    }
    return lines.joined(separator: "\n")
}

func require(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else {
        fputs("SELF-TEST FAIL: \(label)\n", stderr)
        exit(20)
    }
}

func runSelfTests() {
    let identifierMatch = StatusItemCandidate(
        identifier: statusItemAccessibilityIdentifier,
        role: "AXStatusItem",
        subrole: nil,
        title: "unrelated",
        description: nil,
        help: nil,
        stringValue: nil
    )
    require(statusItemIsPresent(in: [identifierMatch]), "status identifier match")
    require(statusItemIsPresent(in: [StatusItemCandidate(
        identifier: nil,
        role: "AXMenuBarItem",
        subrole: nil,
        title: "Zoid 666",
        description: nil,
        help: nil,
        stringValue: nil
    )]), "exact status title fallback")
    require(statusItemIsPresent(in: [StatusItemCandidate(
        identifier: nil,
        role: "AXMenuBarItem",
        subrole: nil,
        title: nil,
        description: "Zoid 666, A task is active",
        help: nil,
        stringValue: nil
    )]), "semantic status description fallback")
    require(!statusItemIsPresent(in: [StatusItemCandidate(
        identifier: nil,
        role: "AXMenuBarItem",
        subrole: nil,
        title: "Unrelated Zoid 666 item",
        description: nil,
        help: nil,
        stringValue: nil
    )]), "embedded unrelated status title rejected")

    let injectedPresent = StatusItemSource { .present }
    let injectedMissing = StatusItemSource { .missing }
    let injectedControlCenterUnavailable = StatusItemSource { .controlCenterUnavailable }
    let injectedAccessibilityUnavailable = StatusItemSource { .accessibilityUnavailable }
    require(statusItemObservation(from: injectedPresent).hasStatusItem, "injected status present")
    require(statusItemObservation(from: injectedMissing).failure == .statusItemUnavailable,
            "injected status missing")
    require(statusItemObservation(from: injectedControlCenterUnavailable).failure == .controlCenterUnavailable,
            "injected ControlCenter unavailable")
    require(statusItemObservation(from: injectedAccessibilityUnavailable).failure
            == .controlCenterAccessibilityUnavailable,
            "injected ControlCenter accessibility unavailable")

    var initiallyWindowless = BackgroundVisibilityState()
    require(initiallyWindowless.observe(
        windows: .availableEmpty,
        hasStatusItem: true,
        elapsed: 0
    ) == nil, "initial empty sample")
    require(initiallyWindowless.observe(
        windows: .availableEmpty,
        hasStatusItem: true,
        elapsed: 0.5
    ) == nil, "stable empty sample")
    require(initiallyWindowless.finalError() == nil, "initially windowless pass")

    var oldTransition = BackgroundVisibilityState()
    require(oldTransition.observe(
        windows: .availableNonempty,
        hasStatusItem: false,
        elapsed: 0
    ) == nil, "old initial window")
    require(oldTransition.observe(
        windows: .availableEmpty,
        hasStatusItem: true,
        elapsed: 0.1
    ) == nil, "old first empty")
    require(oldTransition.observe(
        windows: .availableEmpty,
        hasStatusItem: true,
        elapsed: 0.6
    ) == nil, "old stable empty")
    require(oldTransition.finalError() == nil, "old window-to-windowless compatibility")

    var persistent = BackgroundVisibilityState()
    _ = persistent.observe(windows: .availableNonempty, hasStatusItem: true, elapsed: 0)
    require(persistent.finalError() == .backgroundWindowPersisted, "persistent window error")

    var reappearing = BackgroundVisibilityState()
    _ = reappearing.observe(windows: .availableEmpty, hasStatusItem: true, elapsed: 0)
    _ = reappearing.observe(windows: .availableEmpty, hasStatusItem: true, elapsed: 0.5)
    require(reappearing.observe(
        windows: .availableNonempty,
        hasStatusItem: true,
        elapsed: 0.6
    ) == .backgroundWindowReappeared, "reappearing window error")

    var unavailable = BackgroundVisibilityState()
    require(unavailable.observe(
        windows: .unavailable,
        hasStatusItem: false,
        elapsed: 0
    ) == .accessibilityUnavailable, "accessibility unavailable error")

    var missingStatus = BackgroundVisibilityState()
    _ = missingStatus.observe(windows: .availableEmpty, hasStatusItem: false, elapsed: 0)
    _ = missingStatus.observe(windows: .availableEmpty, hasStatusItem: false, elapsed: 1)
    require(missingStatus.finalError() == .statusItemUnavailable, "missing status item error")

    var lostStatus = BackgroundVisibilityState()
    _ = lostStatus.observe(windows: .availableEmpty, hasStatusItem: true, elapsed: 0)
    _ = lostStatus.observe(windows: .availableEmpty, hasStatusItem: true, elapsed: 0.5)
    require(lostStatus.observe(
        windows: .availableEmpty,
        hasStatusItem: false,
        elapsed: 0.6
    ) == .statusItemUnavailable, "lost status item error")

    require(VisibilityProbeError.processExited.exitCode != VisibilityProbeError.accessibilityUnavailable.exitCode,
            "process and accessibility exit codes differ")
    require(VisibilityProbeError.controlCenterUnavailable.exitCode
            != VisibilityProbeError.controlCenterAccessibilityUnavailable.exitCode,
            "ControlCenter failure exit codes differ")
    print("PASS: visibility probe state-machine self-tests")
}

var diagnosticApplication: AXUIElement?
var diagnosticPID: Int32?

do {
    if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--self-test" {
        runSelfTests()
        exit(0)
    }

    guard CommandLine.arguments.count == 4,
          let pid = Int32(CommandLine.arguments[1]),
          let timeout = TimeInterval(CommandLine.arguments[3]),
          timeout >= BackgroundVisibilityState.stableWindowlessInterval else {
        throw VisibilityProbeError.usage
    }

    let expectation = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    diagnosticApplication = application
    diagnosticPID = pid
    let startedAt = Date()
    let deadline = startedAt.addingTimeInterval(timeout)

    switch expectation {
    case "foreground-visible":
        var becameVisible = false
        repeat {
            guard processIsAlive(pid) else { throw VisibilityProbeError.processExited }
            let windows = windowSample(application)
            guard windows != .unavailable else { throw VisibilityProbeError.accessibilityUnavailable }
            let visible = !isHidden(application) && windows == .availableNonempty
            if visible {
                becameVisible = true
            } else if becameVisible {
                throw VisibilityProbeError.foregroundDidNotRemainVisible
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        guard becameVisible else { throw VisibilityProbeError.foregroundDidNotRemainVisible }
        print("GREEN: foreground launch remained visible for \(timeout) seconds")
    case "background-windowless-menu-ready":
        var state = BackgroundVisibilityState()
        var lastStatusFailure = VisibilityProbeError.statusItemUnavailable
        var matchedStatusItem: LocatedStatusItem?
        repeat {
            guard processIsAlive(pid) else { throw VisibilityProbeError.processExited }
            if isHidden(application) { throw VisibilityProbeError.backgroundBecameHidden }
            let status = liveStatusItem(pid: pid)
            lastStatusFailure = status.failure
            matchedStatusItem = status.item ?? matchedStatusItem
            let failure = state.observe(
                windows: windowSample(application),
                hasStatusItem: status.item != nil,
                elapsed: Date().timeIntervalSince(startedAt)
            )
            if let failure {
                throw failure == .statusItemUnavailable ? lastStatusFailure : failure
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        if let failure = state.finalError() {
            throw failure == .statusItemUnavailable ? lastStatusFailure : failure
        }
        guard let matchedStatusItem else { throw lastStatusFailure }
        print(diagnosticString(for: matchedStatusItem))
        guard pressStatusItem(matchedStatusItem) else {
            throw VisibilityProbeError.statusItemPressFailed
        }
        let popoverDeadline = Date().addingTimeInterval(min(5, timeout))
        var popoverPresent = false
        repeat {
            guard processIsAlive(pid) else { throw VisibilityProbeError.processExited }
            popoverPresent = coachPopoverIsPresent(in: application)
            if !popoverPresent { Thread.sleep(forTimeInterval: 0.1) }
        } while !popoverPresent && Date() < popoverDeadline
        guard popoverPresent else { throw VisibilityProbeError.coachPopoverUnavailable }
        print("GREEN: --background-schedule stayed unhidden and windowless; native status item opened AXSystemDialog containing menu-bar.coach")
    default:
        throw VisibilityProbeError.usage
    }
} catch let error as VisibilityProbeError {
    fputs("\(error)\n", stderr)
    if error != .usage, let application = diagnosticApplication, let pid = diagnosticPID {
        fputs("\(privacySafeWindowDiagnostics(application, expectedPID: pid))\n", stderr)
    }
    exit(error.exitCode)
} catch {
    fputs("\(error)\n", stderr)
    if let application = diagnosticApplication, let pid = diagnosticPID {
        fputs("\(privacySafeWindowDiagnostics(application, expectedPID: pid))\n", stderr)
    }
    exit(3)
}
