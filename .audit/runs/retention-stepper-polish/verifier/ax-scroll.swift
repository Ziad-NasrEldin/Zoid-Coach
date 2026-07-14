import ApplicationServices
import Foundation

func value(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
    return result
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

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[1]),
      let position = Double(CommandLine.arguments[2]) else {
    fputs("usage: ax-scroll.swift <pid> <0...1>\n", stderr)
    exit(2)
}

let application = AXUIElementCreateApplication(pid)
for area in descendants(application) {
    guard let scrollbar = value(area, kAXVerticalScrollBarAttribute as CFString) else { continue }
    let result = AXUIElementSetAttributeValue(
        scrollbar as! AXUIElement,
        kAXValueAttribute as CFString,
        NSNumber(value: min(1, max(0, position)))
    )
    if result == .success {
        print("PASS: vertical scroll set to \(position)")
        exit(0)
    }
}
fputs("vertical scrollbar not found\n", stderr)
exit(1)
