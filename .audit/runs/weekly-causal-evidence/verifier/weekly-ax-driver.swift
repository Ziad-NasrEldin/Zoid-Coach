import AppKit
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func text(_ element: AXUIElement, _ name: CFString) -> String {
    attribute(element, name) as? String ?? ""
}

func descendants(_ root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue: [AXUIElement] = [root]
    while !queue.isEmpty {
        let element = queue.removeFirst()
        result.append(element)
        queue.append(contentsOf: attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [])
    }
    return result
}

guard CommandLine.arguments.count == 4,
      let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: weekly-ax-driver.swift <pid> <focus-space|focus-return> <identifier>\n", stderr)
    exit(2)
}

let app = AXUIElementCreateApplication(pid)
let identifier = CommandLine.arguments[3]
guard let target = descendants(app).first(where: {
    text($0, kAXIdentifierAttribute as CFString) == identifier
}) else {
    fputs("element not found: \(identifier)\n", stderr)
    exit(1)
}

_ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
_ = AXUIElementPerformAction(target, "AXScrollToVisible" as CFString)
guard AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
    fputs("could not focus: \(identifier)\n", stderr)
    exit(1)
}

let keyCode: CGKeyCode = CommandLine.arguments[2] == "focus-return" ? 36 : 49
CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.5)
print("PASS: keyboard activated \(identifier)")
