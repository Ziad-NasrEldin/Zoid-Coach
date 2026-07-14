import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case usage
    case missing(String)
    case count(prefix: String, expected: Int, actual: Int)
    case action(String, AXError)

    var description: String {
        switch self {
        case .usage:
            return "usage: ax-driver PID dump | wait ID [seconds] | frame ID [seconds] | scroll-visible ID [seconds] | press ID [seconds] | click ID [seconds] | text ID [seconds] | wait-count-prefix PREFIX EXPECTED [seconds]"
        case let .missing(identifier):
            return "AX identifier did not become reachable: \(identifier)"
        case let .count(prefix, expected, actual):
            return "AX prefix \(prefix) expected \(expected) controls but found \(actual)"
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
    var point = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func size(_ element: AXUIElement) -> CGSize? {
    guard let raw = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func click(_ element: AXUIElement, identifier: String) throws {
    guard let origin = point(element), let bounds = size(element), bounds.width > 0, bounds.height > 0 else {
        throw DriverError.missing("\(identifier) frame")
    }
    let center = CGPoint(x: origin.x + bounds.width / 2, y: origin.y + bounds.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
    else { throw DriverError.missing("\(identifier) click event") }
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
    print("PASS: clicked \(identifier) at \(Int(center.x)),\(Int(center.y))")
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

func scrollToVisible(pid: pid_t, identifier expected: String, timeout: TimeInterval) throws -> (CGRect, CGRect, Int) {
    let deadline = Date().addingTimeInterval(timeout)
    var attempts = 0
    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
    while Date() < deadline {
        guard let element = waitForElement(pid: pid, identifier: expected, timeout: 0.2),
              let elementFrame = frame(element),
              let windowFrame = visibleWindowFrame(pid: pid)
        else {
            usleep(100_000)
            continue
        }

        let visibleContent = windowFrame.insetBy(dx: 8, dy: 44)
        if visibleContent.contains(CGPoint(x: elementFrame.midX, y: elementFrame.midY)) {
            return (elementFrame, visibleContent, attempts)
        }

        if attempts == 0 {
            _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
            attempts += 1
            usleep(500_000)
            continue
        }

        let scrollAreas = snapshot(pid: pid).filter {
            string($0, kAXRoleAttribute as CFString) == kAXScrollAreaRole as String
                && frame($0)?.intersects(visibleContent) == true
        }
        var movedScrollbar = false
        for area in scrollAreas {
            guard let rawScrollbar = attribute(area, kAXVerticalScrollBarAttribute as CFString),
                  CFGetTypeID(rawScrollbar) == AXUIElementGetTypeID()
            else { continue }
            let scrollbar = rawScrollbar as! AXUIElement
            let current = (attribute(scrollbar, kAXValueAttribute as CFString) as? NSNumber)?.doubleValue ?? 0
            let next = elementFrame.midY > visibleContent.maxY
                ? min(1, current + 0.18)
                : max(0, current - 0.18)
            if AXUIElementSetAttributeValue(scrollbar, kAXValueAttribute as CFString, NSNumber(value: next)) == .success {
                movedScrollbar = true
                break
            }
        }
        if movedScrollbar {
            attempts += 1
            usleep(350_000)
            continue
        }

        let cursor = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cursor, mouseButton: .left)?.post(tap: .cghidEventTap)
        if attempts == 0 {
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cursor, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cursor, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        let keyCode: CGKeyCode = elementFrame.midY > visibleContent.maxY ? 121 : 116
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { throw DriverError.missing("\(expected) page-scroll event") }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        attempts += 1
        usleep(300_000)
    }
    throw DriverError.missing("\(expected) visible frame after scrolling")
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

    guard let element = waitForElement(pid: pid, identifier: target, timeout: timeout(at: 4)) else {
        throw DriverError.missing(target)
    }

    if command == "wait" {
        print("PASS: \(target) role=\(string(element, kAXRoleAttribute as CFString)) text=\(visibleText(element))")
    } else if command == "frame" {
        guard let elementFrame = frame(element), let windowFrame = visibleWindowFrame(pid: pid) else {
            throw DriverError.missing("\(target) frame")
        }
        let visibleContent = windowFrame.insetBy(dx: 8, dy: 44)
        let intersects = visibleContent.contains(CGPoint(x: elementFrame.midX, y: elementFrame.midY))
        print("FRAME: \(target) element=\(NSStringFromRect(elementFrame)) visible=\(NSStringFromRect(visibleContent)) center-visible=\(intersects)")
    } else if command == "scroll-visible" {
        let result = try scrollToVisible(pid: pid, identifier: target, timeout: timeout(at: 4))
        print("PASS: scrolled \(target) into visible content after \(result.2) wheel events; element=\(NSStringFromRect(result.0)) visible=\(NSStringFromRect(result.1)) center-visible=true")
    } else if command == "text" {
        print(visibleText(element))
    } else if command == "press" {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else { throw DriverError.action(target, error) }
        print("PASS: pressed \(target)")
    } else if command == "click" {
        try click(element, identifier: target)
    } else {
        throw DriverError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
