import ApplicationServices
import Foundation

func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
    return result
}

func text(_ element: AXUIElement, _ attribute: CFString) -> String {
    value(element, attribute) as? String ?? ""
}

func descendants(_ root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = [root]
    while !queue.isEmpty {
        let element = queue.removeFirst()
        result.append(element)
        if let children = value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return result
}

func frame(_ element: AXUIElement) -> String {
    guard let positionValue = value(element, kAXPositionAttribute as CFString),
          let sizeValue = value(element, kAXSizeAttribute as CFString),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return "" }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return "" }
    return "\(Int(position.x)),\(Int(position.y)),\(Int(size.width)),\(Int(size.height))"
}

guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: menu-bar-ax-driver.swift <pid> dump|press <identifier>\n", stderr)
    exit(2)
}

let application = AXUIElementCreateApplication(pid)
guard let windows = value(application, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
    fputs("no windows\n", stderr)
    exit(2)
}

switch CommandLine.arguments[2] {
case "dump":
    for (index, window) in windows.enumerated() {
        print("WINDOW|\(index)|\(text(window, kAXRoleAttribute as CFString))|\(text(window, kAXSubroleAttribute as CFString))|\(text(window, kAXTitleAttribute as CFString))|\(frame(window))")
        for element in descendants(window) {
            let role = text(element, kAXRoleAttribute as CFString)
            let identifier = text(element, kAXIdentifierAttribute as CFString)
            let title = text(element, kAXTitleAttribute as CFString)
            let label = text(element, kAXDescriptionAttribute as CFString)
            let elementValue = text(element, kAXValueAttribute as CFString)
            if !identifier.isEmpty || role == (kAXButtonRole as String) || role == (kAXStaticTextRole as String) {
                print("NODE|\(index)|\(role)|\(identifier)|\(title)|\(label)|\(elementValue)|\(frame(element))")
            }
        }
    }
case "press":
    guard CommandLine.arguments.count == 4 else { exit(2) }
    let identifier = CommandLine.arguments[3]
    guard let match = windows.lazy.flatMap({ descendants($0) }).first(where: {
        text($0, kAXIdentifierAttribute as CFString) == identifier
    }) else {
        fputs("missing identifier: \(identifier)\n", stderr)
        exit(1)
    }
    let result = AXUIElementPerformAction(match, kAXPressAction as CFString)
    print("PRESS|\(identifier)|\(result.rawValue)")
    exit(result == .success ? 0 : 1)
default:
    exit(2)
}
