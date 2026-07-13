import ApplicationServices
import Foundation

enum VisibilityProbeError: Error, CustomStringConvertible {
    case usage
    case foregroundDidNotRemainVisible
    case backgroundDidNotHide

    var description: String {
        switch self {
        case .usage:
            "usage: qa-app-visibility-probe.swift <pid> <foreground-visible|background-hidden> <timeout-seconds>"
        case .foregroundDidNotRemainVisible:
            "RED: foreground launch did not remain visible for the complete observation window"
        case .backgroundDidNotHide:
            "RED: --background-schedule launch did not hide within the observation window"
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
    case "background-hidden":
        repeat {
            if isHidden(application) {
                print("GREEN: --background-schedule launch hid intentionally")
                exit(0)
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw VisibilityProbeError.backgroundDidNotHide
    default:
        throw VisibilityProbeError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(error is VisibilityProbeError ? 1 : 2)
}
