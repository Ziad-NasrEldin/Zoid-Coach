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

func dumpTree(_ element: AXUIElement, depth: Int = 0) {
    guard depth < 16 else { return }
    let role = string(element, kAXRoleAttribute as CFString) ?? "?"
    let identifier = string(element, kAXIdentifierAttribute as CFString) ?? ""
    let title = string(element, kAXTitleAttribute as CFString) ?? ""
    let description = string(element, kAXDescriptionAttribute as CFString) ?? ""
    let rawValue = string(element, kAXValueAttribute as CFString) ?? ""
    if !identifier.isEmpty || !title.isEmpty || !description.isEmpty || !rawValue.isEmpty {
        print("\(depth)|\(role)|id=\(identifier)|title=\(title)|description=\(description)|value=\(rawValue)")
    }
    for child in children(element) {
        dumpTree(child, depth: depth + 1)
    }
}

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    fputs("usage: ax-dump.swift <pid>\n", stderr)
    exit(2)
}

let application = AXUIElementCreateApplication(pid)
Thread.sleep(forTimeInterval: 0.5)
dumpTree(application)
