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
private let statusItemAccessibilityIdentifier = "menu-bar.status-item"
private let statusItemTitle = "Zoid 666"
private let maximumStatusNodes = 64
private let maximumStatusDepth = 2
private let statusScanTimeLimit: TimeInterval = 0.2

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
    let labels: [String]
}

func statusItemIsPresent(in candidates: [StatusItemCandidate]) -> Bool {
    if candidates.contains(where: { $0.identifier == statusItemAccessibilityIdentifier }) {
        return true
    }
    return candidates.contains { candidate in
        candidate.labels.contains(statusItemTitle)
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

func statusCandidateRole(_ element: AXUIElement) -> String? {
    value(element, kAXRoleAttribute as CFString) as? String
}

func isStatusCandidateRole(_ role: String?) -> Bool {
    guard let role else { return false }
    return role == (kAXMenuBarRole as String)
        || role == (kAXMenuBarItemRole as String)
        || role == (kAXGroupRole as String)
        || role == "AXStatusItem"
}

func statusItemCandidates(in controlCenter: AXUIElement) -> [StatusItemCandidate]? {
    var menuBarValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        controlCenter,
        kAXExtrasMenuBarAttribute as CFString,
        &menuBarValue
    ) == .success,
          let menuBar = menuBarValue as! AXUIElement?
    else {
        return nil
    }

    let deadline = Date().addingTimeInterval(statusScanTimeLimit)
    var queue: [(AXUIElement, Int)] = [(menuBar, 0)]
    var index = 0
    var candidates: [StatusItemCandidate] = []
    while index < queue.count,
          index < maximumStatusNodes,
          Date() < deadline {
        let (element, depth) = queue[index]
        index += 1
        guard isStatusCandidateRole(statusCandidateRole(element)) else { continue }

        let identifier = value(element, kAXIdentifierAttribute as CFString) as? String
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { value(element, $0 as CFString) as? String }
        candidates.append(StatusItemCandidate(identifier: identifier, labels: labels))

        guard depth < maximumStatusDepth,
              let children = value(element, kAXChildrenAttribute as CFString) as? [AXUIElement]
        else { continue }
        for child in children where queue.count < maximumStatusNodes {
            if isStatusCandidateRole(statusCandidateRole(child)) {
                queue.append((child, depth + 1))
            }
        }
    }
    return candidates
}

func liveStatusItemSource() -> StatusItemSource {
    StatusItemSource {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: controlCenterBundleIdentifier)
            .first(where: { !$0.isTerminated })
        else {
            return .controlCenterUnavailable
        }
        let controlCenter = AXUIElementCreateApplication(application.processIdentifier)
        guard let candidates = statusItemCandidates(in: controlCenter) else {
            return .accessibilityUnavailable
        }
        return statusItemIsPresent(in: candidates) ? .present : .missing
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
    let identifierMatch = StatusItemCandidate(
        identifier: statusItemAccessibilityIdentifier,
        labels: ["unrelated"]
    )
    require(statusItemIsPresent(in: [identifierMatch]), "status identifier match")
    require(statusItemIsPresent(in: [StatusItemCandidate(
        identifier: nil,
        labels: ["Zoid 666"]
    )]), "exact status title fallback")
    require(!statusItemIsPresent(in: [StatusItemCandidate(
        identifier: nil,
        labels: ["Zoid 666, A task is active", "another item"]
    )]), "non-exact status title rejected")

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
        let statusSource = liveStatusItemSource()
        var lastStatusFailure = VisibilityProbeError.statusItemUnavailable
        repeat {
            guard processIsAlive(pid) else { throw VisibilityProbeError.processExited }
            if isHidden(application) { throw VisibilityProbeError.backgroundBecameHidden }
            let status = statusItemObservation(from: statusSource)
            lastStatusFailure = status.failure
            let failure = state.observe(
                windows: windowSample(application),
                hasStatusItem: status.hasStatusItem,
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
