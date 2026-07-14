import ApplicationServices
import Foundation

enum ProbeFailure: Error, CustomStringConvertible {
    case usage
    case accessibilityUnavailable
    case dismissControlMissing
    case pressFailed(AXError)

    var description: String {
        switch self {
        case .usage:
            "usage: qa-dismiss-prompt-probe.swift <pid>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable for the signed QA dismissal probe."
        case .dismissControlMissing:
            "The visible signed QA prompt did not expose its direct DISMISS control."
        case let .pressFailed(error):
            "The visible signed QA prompt DISMISS control refused AXPress: \(error.rawValue)."
        }
    }
}

func attribute<T>(_ name: CFString, from element: AXUIElement, as _: T.Type) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? T
}

func descendants(of root: AXUIElement, maximum: Int = 4_000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    var index = 0
    while index < queue.count, result.count < maximum {
        let element = queue[index]
        index += 1
        result.append(element)
        if let children = attribute(kAXChildrenAttribute, from: element, as: [AXUIElement].self) {
            queue.append(contentsOf: children)
        }
    }
    return result
}

do {
    guard CommandLine.arguments.count == 2,
          let pid = Int32(CommandLine.arguments[1]) else {
        throw ProbeFailure.usage
    }
    guard AXIsProcessTrusted() else { throw ProbeFailure.accessibilityUnavailable }
    let application = AXUIElementCreateApplication(pid)
    let dismiss = descendants(of: application).first { element in
        let identifier = attribute(kAXIdentifierAttribute, from: element, as: String.self) ?? ""
        let title = attribute(kAXTitleAttribute, from: element, as: String.self) ?? ""
        let enabled = attribute(kAXEnabledAttribute, from: element, as: Bool.self) ?? false
        return enabled && identifier.hasPrefix("today.prompt.") && identifier.hasSuffix(".dismiss")
            && title == "DISMISS"
    }
    guard let dismiss else { throw ProbeFailure.dismissControlMissing }
    let result = AXUIElementPerformAction(dismiss, kAXPressAction)
    guard result == .success else { throw ProbeFailure.pressFailed(result) }
    print("PASS: pressed the visible signed QA prompt DISMISS control")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
