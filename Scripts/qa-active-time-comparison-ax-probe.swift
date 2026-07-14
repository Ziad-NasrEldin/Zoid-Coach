import AppKit
import ApplicationServices
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case accessibilityPermission
    case statusItemUnavailable
    case statusItemDidNotOpen
    case missingElement(String)
    case contract(String)

    var description: String {
        switch self {
        case let .invalidArguments(message): message
        case .accessibilityPermission: "Accessibility permission is required for the verifier process."
        case .statusItemUnavailable: "The signed Zoid 666 status item is unavailable."
        case .statusItemDidNotOpen: "The compact menu-bar task card did not open."
        case let .missingElement(identifier): "Missing accessibility element: \(identifier)"
        case let .contract(message): message
        }
    }
}

struct Arguments {
    let pid: pid_t
    let minimumElapsedMinutes: Int
    let expectedAlignedMinutes: Int

    init(_ values: [String]) throws {
        var pid: pid_t?
        var minimumElapsedMinutes: Int?
        var expectedAlignedMinutes: Int?
        var index = 1
        while index < values.count {
            guard index + 1 < values.count else {
                throw ProbeError.invalidArguments("Every option requires a value.")
            }
            switch values[index] {
            case "--pid": pid = Int32(values[index + 1])
            case "--minimum-elapsed": minimumElapsedMinutes = Int(values[index + 1])
            case "--expected-aligned": expectedAlignedMinutes = Int(values[index + 1])
            default: throw ProbeError.invalidArguments("Unknown option: \(values[index])")
            }
            index += 2
        }
        guard let pid, pid > 0,
              let minimumElapsedMinutes, minimumElapsedMinutes >= 0,
              let expectedAlignedMinutes, expectedAlignedMinutes >= 0
        else {
            throw ProbeError.invalidArguments(
                "Usage: swift qa-active-time-comparison-ax-probe.swift --pid PID --minimum-elapsed MINUTES --expected-aligned MINUTES"
            )
        }
        self.pid = pid
        self.minimumElapsedMinutes = minimumElapsedMinutes
        self.expectedAlignedMinutes = expectedAlignedMinutes
    }
}

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

func identifier(of element: AXUIElement) -> String? {
    stringAttribute(element, kAXIdentifierAttribute as CFString)
}

func label(of element: AXUIElement) -> String? {
    [
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
    ].compactMap { $0 }.first { !$0.isEmpty }
}

func publicStrings(of element: AXUIElement) -> [String] {
    [
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
        stringAttribute(element, kAXHelpAttribute as CFString),
    ].compactMap { $0 }
}

func firstElement(
    from root: AXUIElement,
    matching predicate: (AXUIElement) -> Bool
) -> AXUIElement? {
    var queue = [root]
    var visited = Set<CFHashCode>()
    while !queue.isEmpty && visited.count < 4_000 {
        let element = queue.removeFirst()
        let hash = CFHash(element)
        guard visited.insert(hash).inserted else { continue }
        if predicate(element) { return element }
        queue.append(contentsOf: children(of: element))
    }
    return nil
}

func waitForElement(
    in application: AXUIElement,
    identifier expectedIdentifier: String,
    timeout: TimeInterval = 8
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = firstElement(from: application, matching: {
            identifier(of: $0) == expectedIdentifier
        }) {
            return element
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return nil
}

func openCompactCard(application: AXUIElement) throws {
    if waitForElement(in: application, identifier: "menu-bar.task.active-time-comparison", timeout: 0.2) != nil {
        return
    }
    guard let extrasValue = attribute(application, kAXExtrasMenuBarAttribute as CFString),
          CFGetTypeID(extrasValue) == AXUIElementGetTypeID()
    else { throw ProbeError.statusItemUnavailable }
    let extras = unsafeBitCast(extrasValue, to: AXUIElement.self)
    guard let statusItem = firstElement(from: extras, matching: { element in
        publicStrings(of: element).contains("A task is active")
    }) else { throw ProbeError.statusItemUnavailable }
    guard AXUIElementPerformAction(statusItem, kAXPressAction as CFString) == .success else {
        throw ProbeError.statusItemUnavailable
    }
    guard waitForElement(in: application, identifier: "menu-bar.task.active-time-comparison") != nil else {
        throw ProbeError.statusItemDidNotOpen
    }
}

func requireElement(_ identifier: String, in application: AXUIElement) throws -> AXUIElement {
    guard let element = waitForElement(in: application, identifier: identifier) else {
        throw ProbeError.missingElement(identifier)
    }
    return element
}

func minutes(from label: String, prefix: String) throws -> Int {
    guard label.hasPrefix(prefix),
          let value = label.dropFirst(prefix.count).split(separator: " ").first,
          let minutes = Int(value)
    else { throw ProbeError.contract("Unexpected time label: \(label)") }
    return minutes
}

func assertDistinct(_ elements: [AXUIElement]) throws {
    for left in elements.indices {
        for right in elements.indices where left < right {
            if CFEqual(elements[left], elements[right]) {
                throw ProbeError.contract("Elapsed, aligned, and evidence must be separate accessibility elements.")
            }
        }
    }
}

func run() throws {
    let arguments = try Arguments(CommandLine.arguments)
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityPermission }
    let application = AXUIElementCreateApplication(arguments.pid)
    try openCompactCard(application: application)

    let elapsed = try requireElement("menu-bar.task.elapsed-time", in: application)
    let aligned = try requireElement("menu-bar.task.aligned-time", in: application)
    let evidence = try requireElement("menu-bar.task.alignment-evidence", in: application)
    try assertDistinct([elapsed, aligned, evidence])

    let elapsedLabel = label(of: elapsed) ?? ""
    let alignedLabel = label(of: aligned) ?? ""
    let evidenceLabel = label(of: evidence) ?? ""
    let elapsedMinutes = try minutes(from: elapsedLabel, prefix: "Task elapsed, ")
    let alignedMinutes = try minutes(from: alignedLabel, prefix: "Observed aligned, ")

    guard elapsedMinutes >= arguments.minimumElapsedMinutes else {
        throw ProbeError.contract(
            "Elapsed time regressed: expected at least \(arguments.minimumElapsedMinutes), got \(elapsedMinutes)."
        )
    }
    guard alignedMinutes == arguments.expectedAlignedMinutes else {
        throw ProbeError.contract(
            "Observed aligned time changed: expected \(arguments.expectedAlignedMinutes), got \(alignedMinutes)."
        )
    }
    guard stringAttribute(elapsed, kAXHelpAttribute as CFString)?.contains("active task timer") == true else {
        throw ProbeError.contract("Elapsed-time help does not explain the task timer boundary.")
    }
    guard stringAttribute(aligned, kAXHelpAttribute as CFString)?.contains("signal, not proof") == true else {
        throw ProbeError.contract("Aligned-time help does not disclose the evidence boundary.")
    }
    guard evidenceLabel.contains("signal, not proof"),
          stringAttribute(evidence, kAXHelpAttribute as CFString)?.contains("differs from elapsed task time") == true
    else {
        throw ProbeError.contract("Evidence disclosure is missing or misleading.")
    }

    print("PASS: ZC-024-008 compact AX contract elapsed=\(elapsedMinutes) aligned=\(alignedMinutes)")
    print("ELAPSED_MINUTES=\(elapsedMinutes)")
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
