import ApplicationServices
import Foundation

enum VisibilityProbeError: Error, CustomStringConvertible {
    case usage
    case foregroundDidNotRemainVisible
    case backgroundBecameHidden
    case backgroundWindowRemainedVisible
    case statusItemUnavailable

    var description: String {
        switch self {
        case .usage:
            "usage: qa-app-visibility-probe.swift <pid> <foreground-visible|background-windowless-menu-ready> <timeout-seconds>"
        case .foregroundDidNotRemainVisible:
            "RED: foreground launch did not remain visible for the complete observation window"
        case .backgroundBecameHidden:
            "RED: --background-schedule hid the application and made its status item unusable"
        case .backgroundWindowRemainedVisible:
            "RED: --background-schedule left a normal application window visible"
        case .statusItemUnavailable:
            "RED: --background-schedule did not retain a stable status item"
        }
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

func hasWindow(_ application: AXUIElement) -> Bool {
    guard let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
        return false
    }
    return !windows.isEmpty
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

var diagnosticApplication: AXUIElement?
var diagnosticPID: Int32?

do {
    guard CommandLine.arguments.count == 4,
          let pid = Int32(CommandLine.arguments[1]),
          let timeout = TimeInterval(CommandLine.arguments[3]),
          timeout > 0 else {
        throw VisibilityProbeError.usage
    }

    let expectation = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    diagnosticApplication = application
    diagnosticPID = pid
    let deadline = Date().addingTimeInterval(timeout)

    switch expectation {
    case "foreground-visible":
        var becameVisible = false
        repeat {
            let visible = !isHidden(application) && hasWindow(application)
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
        var showedInitialWindow = false
        var becameWindowless = false
        var retainedStatusItem = false
        repeat {
            if isHidden(application) {
                throw VisibilityProbeError.backgroundBecameHidden
            }
            if hasWindow(application) {
                showedInitialWindow = true
                if becameWindowless {
                    throw VisibilityProbeError.backgroundWindowRemainedVisible
                }
            } else if showedInitialWindow {
                becameWindowless = true
                retainedStatusItem = retainedStatusItem || hasStatusItem(application)
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        guard becameWindowless else { throw VisibilityProbeError.backgroundWindowRemainedVisible }
        guard retainedStatusItem else { throw VisibilityProbeError.statusItemUnavailable }
        print("GREEN: --background-schedule stayed unhidden with no normal window and a stable status item")
    default:
        throw VisibilityProbeError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    if let visibilityError = error as? VisibilityProbeError,
       case .usage = visibilityError {
        // Usage failures do not have a target process to diagnose.
    } else if let application = diagnosticApplication, let pid = diagnosticPID {
        fputs("\(privacySafeWindowDiagnostics(application, expectedPID: pid))\n", stderr)
    }
    exit(error is VisibilityProbeError ? 1 : 2)
}
