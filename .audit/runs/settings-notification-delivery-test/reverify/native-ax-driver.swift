import ApplicationServices
import Foundation

func text(_ element: AXUIElement, _ attribute: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
    return value as? String ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func walk(_ element: AXUIElement, into result: inout [AXUIElement]) {
    result.append(element)
    for child in children(element) { walk(child, into: &result) }
}

guard CommandLine.arguments.count >= 3, let pid = Int32(CommandLine.arguments[1]) else {
    fatalError("usage: native-ax-driver <pid> dump|press [identifier]")
}

let app = AXUIElementCreateApplication(pid)
var elements: [AXUIElement] = []
walk(app, into: &elements)

switch CommandLine.arguments[2] {
case "dump":
    for element in elements {
        let role = text(element, kAXRoleAttribute as CFString)
        let identifier = text(element, kAXIdentifierAttribute as CFString)
        let title = text(element, kAXTitleAttribute as CFString)
        let value = text(element, kAXValueAttribute as CFString)
        let description = text(element, kAXDescriptionAttribute as CFString)
        let help = text(element, kAXHelpAttribute as CFString)
        if !identifier.isEmpty || role == (kAXButtonRole as String) || role == (kAXStaticTextRole as String) {
            print("\(role)|\(identifier)|\(title)|\(value)|\(description)|\(help)")
        }
    }
case "press":
    guard CommandLine.arguments.count == 4 else { fatalError("press requires identifier") }
    let identifier = CommandLine.arguments[3]
    guard let target = elements.first(where: {
        text($0, kAXIdentifierAttribute as CFString) == identifier
            || text($0, kAXDescriptionAttribute as CFString) == identifier
            || text($0, kAXTitleAttribute as CFString) == identifier
            || text($0, kAXValueAttribute as CFString) == identifier
    }) else {
        fatalError("identifier not found: \(identifier)")
    }
    let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
    print("PRESS|\(identifier)|\(result.rawValue)")
default:
    fatalError("unknown command")
}
