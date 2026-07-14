import ApplicationServices
import Foundation

enum DriverError: Error, CustomStringConvertible {
    case usage
    case missing(String)
    case count(prefix: String, expected: Int, actual: Int)
    case action(String, AXError)

    var description: String {
        switch self {
        case .usage:
            return "usage: ax-driver PID dump | wait ID [seconds] | press ID [seconds] | text ID [seconds] | wait-count-prefix PREFIX EXPECTED [seconds]"
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

func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
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
        queue.append(contentsOf: children(next))
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
    } else if command == "text" {
        print(visibleText(element))
    } else if command == "press" {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else { throw DriverError.action(target, error) }
        print("PASS: pressed \(target)")
    } else {
        throw DriverError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
