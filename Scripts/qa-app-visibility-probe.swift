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

do {
    guard CommandLine.arguments.count == 4,
          let pid = Int32(CommandLine.arguments[1]),
          let timeout = TimeInterval(CommandLine.arguments[3]),
          timeout > 0 else {
        throw VisibilityProbeError.usage
    }

    let expectation = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
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
    exit(error is VisibilityProbeError ? 1 : 2)
}
