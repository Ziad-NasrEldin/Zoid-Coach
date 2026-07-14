import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case usage
    case missing(String)
    case count(prefix: String, expected: Int, actual: Int)
    case outsideViewport(identifier: String, element: CGRect, viewport: CGRect)
    case action(String, AXError)

    var description: String {
        switch self {
        case .usage:
            return "usage: ax-driver PID dump | wait ID [seconds] | click ID [seconds] | text ID [seconds] | wait-count-prefix PREFIX EXPECTED [seconds] | assert-visible-prefix PREFIX EXPECTED [seconds]"
        case let .missing(identifier):
            return "AX identifier did not become reachable: \(identifier)"
        case let .count(prefix, expected, actual):
            return "AX prefix \(prefix) expected \(expected) controls but found \(actual)"
        case let .outsideViewport(identifier, element, viewport):
            return "AX control \(identifier) frame \(NSStringFromRect(element)) is outside initial viewport \(NSStringFromRect(viewport))"
        case let .action(identifier, error):
            return "AX action failed for \(identifier): \(error.rawValue)"
        }
    }
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &result) == .success else { return nil }
    return result
}

func string(_ element: AXUIElement, _ name: CFString) -> String {
    attribute(element, name) as? String ?? ""
}

func relatedElements(_ element: AXUIElement) -> [AXUIElement] {
    let attributes: [CFString] = [
        kAXChildrenAttribute as CFString,
        kAXWindowsAttribute as CFString,
        "AXSheets" as CFString,
    ]
    return attributes.flatMap { attribute(element, $0) as? [AXUIElement] ?? [] }
}

func descendants(of root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    var seen = Set<CFHashCode>()
    while !queue.isEmpty && result.count < 4_000 {
        let next = queue.removeFirst()
        let hash = CFHash(next)
        guard seen.insert(hash).inserted else { continue }
        result.append(next)
        queue.append(contentsOf: relatedElements(next))
    }
    return result
}

func identifier(_ element: AXUIElement) -> String {
    string(element, kAXIdentifierAttribute as CFString)
}

func visibleText(_ element: AXUIElement) -> String {
    [
        string(element, kAXTitleAttribute as CFString),
        string(element, kAXDescriptionAttribute as CFString),
        string(element, kAXValueAttribute as CFString),
    ]
    .filter { !$0.isEmpty }
    .joined(separator: " | ")
}

func point(_ element: AXUIElement) -> CGPoint? {
    guard let raw = attribute(element, kAXPositionAttribute as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    var value = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &value) else { return nil }
    return value
}

func size(_ element: AXUIElement) -> CGSize? {
    guard let raw = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    var value = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &value) else { return nil }
    return value
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let origin = point(element), let bounds = size(element), bounds.width > 0, bounds.height > 0 else {
        return nil
    }
    return CGRect(origin: origin, size: bounds)
}

func visibleWindowFrame(pid: pid_t) -> CGRect? {
    let application = AXUIElementCreateApplication(pid)
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    return windows.compactMap(frame).first(where: { $0.width > 500 && $0.height > 400 })
}

func click(_ element: AXUIElement, identifier: String) throws {
    guard let bounds = frame(element) else { throw DriverError.missing("\(identifier) frame") }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    guard let down = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseDown,
        mouseCursorPosition: center,
        mouseButton: .left
    ), let up = CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: center,
        mouseButton: .left
    ) else { throw DriverError.missing("\(identifier) click event") }
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
    print("PASS: clicked \(identifier) at \(Int(center.x)),\(Int(center.y))")
}

func snapshot(pid: pid_t) -> [AXUIElement] {
    descendants(of: AXUIElementCreateApplication(pid))
}

func waitForElement(pid: pid_t, identifier expected: String, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = snapshot(pid: pid).first(where: { identifier($0) == expected }) {
            return element
        }
        usleep(100_000)
    } while Date() < deadline
    return nil
}

func waitForCount(pid: pid_t, prefix: String, expected: Int, timeout: TimeInterval) -> Int {
    let deadline = Date().addingTimeInterval(timeout)
    var count = 0
    repeat {
        count = snapshot(pid: pid).filter {
            identifier($0).hasPrefix(prefix) && string($0, kAXRoleAttribute as CFString) == kAXButtonRole as String
        }.count
        if count == expected { return count }
        usleep(100_000)
    } while Date() < deadline
    return count
}

func assertVisibleControls(pid: pid_t, prefix: String, expected: Int, timeout: TimeInterval) throws {
    let actual = waitForCount(pid: pid, prefix: prefix, expected: expected, timeout: timeout)
    guard actual == expected else { throw DriverError.count(prefix: prefix, expected: expected, actual: actual) }
    guard let window = visibleWindowFrame(pid: pid) else { throw DriverError.missing("main window frame") }
    let viewport = window.insetBy(dx: 8, dy: 44)
    let controls = snapshot(pid: pid)
        .filter {
            identifier($0).hasPrefix(prefix)
                && string($0, kAXRoleAttribute as CFString) == kAXButtonRole as String
        }
        .sorted { identifier($0) < identifier($1) }
    for control in controls {
        let controlID = identifier(control)
        guard let controlFrame = frame(control) else { throw DriverError.missing("\(controlID) frame") }
        guard viewport.contains(controlFrame) else {
            throw DriverError.outsideViewport(identifier: controlID, element: controlFrame, viewport: viewport)
        }
        print("FRAME: \(controlID) element=\(NSStringFromRect(controlFrame)) viewport=\(NSStringFromRect(viewport)) fully-visible=true")
    }
    print("PASS: all \(expected) native AXButton frames match \(prefix) and are fully inside the initial viewport")
}

func timeout(at index: Int, default fallback: TimeInterval = 12) -> TimeInterval {
    guard CommandLine.arguments.count > index else { return fallback }
    return TimeInterval(CommandLine.arguments[index]) ?? fallback
}

do {
    guard CommandLine.arguments.count >= 3,
          let pid = pid_t(CommandLine.arguments[1]) else { throw DriverError.usage }
    let command = CommandLine.arguments[2]

    if command == "dump" {
        for element in snapshot(pid: pid) {
            let id = identifier(element)
            let role = string(element, kAXRoleAttribute as CFString)
            let text = visibleText(element)
            if !id.isEmpty || role == kAXButtonRole as String || role == kAXTextAreaRole as String {
                print("id=\(id) role=\(role) text=\(text)")
            }
        }
        exit(0)
    }

    guard CommandLine.arguments.count >= 4 else { throw DriverError.usage }
    let target = CommandLine.arguments[3]

    if command == "wait-count-prefix" {
        guard CommandLine.arguments.count >= 5,
              let expected = Int(CommandLine.arguments[4]) else { throw DriverError.usage }
        let actual = waitForCount(pid: pid, prefix: target, expected: expected, timeout: timeout(at: 5))
        guard actual == expected else { throw DriverError.count(prefix: target, expected: expected, actual: actual) }
        print("PASS: \(actual) native AXButton controls match \(target)")
        exit(0)
    }

    if command == "assert-visible-prefix" {
        guard CommandLine.arguments.count >= 5,
              let expected = Int(CommandLine.arguments[4]) else { throw DriverError.usage }
        try assertVisibleControls(
            pid: pid,
            prefix: target,
            expected: expected,
            timeout: timeout(at: 5)
        )
        exit(0)
    }

    guard let element = waitForElement(pid: pid, identifier: target, timeout: timeout(at: 4)) else {
        throw DriverError.missing(target)
    }

    if command == "wait" {
        print("PASS: \(target) role=\(string(element, kAXRoleAttribute as CFString)) text=\(visibleText(element))")
    } else if command == "text" {
        print(visibleText(element))
    } else if command == "click" {
        try click(element, identifier: target)
    } else {
        throw DriverError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
