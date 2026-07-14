import ApplicationServices
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

func hasStatusItem(_ application: AXUIElement) -> Bool {
    guard let menuBar = value(application, kAXExtrasMenuBarAttribute as CFString) as! AXUIElement?,
          let children = value(menuBar, kAXChildrenAttribute as CFString) as? [AXUIElement]
    else {
        return false
    }
    return children.contains { element in
        (value(element, kAXRoleAttribute as CFString) as? String) == (kAXMenuBarItemRole as String)
    }
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
        repeat {
            guard processIsAlive(pid) else { throw VisibilityProbeError.processExited }
            if isHidden(application) { throw VisibilityProbeError.backgroundBecameHidden }
            let failure = state.observe(
                windows: windowSample(application),
                hasStatusItem: hasStatusItem(application),
                elapsed: Date().timeIntervalSince(startedAt)
            )
            if let failure { throw failure }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        if let failure = state.finalError() { throw failure }
        print("GREEN: --background-schedule stayed unhidden, stably windowless, and menu ready")
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
