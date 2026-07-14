import ApplicationServices
import Foundation

func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
    return result
}

func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
    value(element, attribute) as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

func descendants(_ root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = children(root)
    while let element = queue.first {
        queue.removeFirst()
        result.append(element)
        queue.append(contentsOf: children(element))
    }
    return result
}

guard (4...5).contains(CommandLine.arguments.count),
      let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: ax-action.swift <pid> <press|increment|decrement> <identifier> [count]\n", stderr)
    exit(2)
}

let application = AXUIElementCreateApplication(pid)
let actionName = CommandLine.arguments[2]
let locator = CommandLine.arguments[3]
let expectedDescription = locator.hasPrefix("description:") ? String(locator.dropFirst("description:".count)) : nil
guard let element = descendants(application).first(where: {
    if let expectedDescription {
        return string($0, kAXRoleAttribute as CFString) == kAXButtonRole as String
            && string($0, kAXDescriptionAttribute as CFString) == expectedDescription
    }
    return string($0, kAXIdentifierAttribute as CFString) == locator
}) else {
    fputs("element not found: \(locator)\n", stderr)
    exit(1)
}

let action: CFString
switch actionName {
case "press": action = kAXPressAction as CFString
case "increment": action = kAXIncrementAction as CFString
case "decrement": action = kAXDecrementAction as CFString
default:
    fputs("unknown action: \(actionName)\n", stderr)
    exit(2)
}

let count = CommandLine.arguments.count == 5 ? Int(CommandLine.arguments[4]) ?? 0 : 1
guard count > 0 else {
    fputs("count must be positive\n", stderr)
    exit(2)
}
for _ in 0..<count {
    let result = AXUIElementPerformAction(element, action)
    guard result == .success else {
        fputs("AX action failed: \(result.rawValue)\n", stderr)
        exit(1)
    }
}
print("PASS: \(actionName) \(locator) x\(count)")
