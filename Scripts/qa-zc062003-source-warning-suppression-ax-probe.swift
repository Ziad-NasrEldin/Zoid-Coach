#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let promptID = "qa-zc062003-strong-gaming-drift"
private let strongWording = ["Is this gaming intentional?", "Ready for an easy return?", "Your five minutes are up"]
private let privateWording = ["qa-zc062003-private", "qa-zc062003.private.invalid"]

private func normalized(_ values: [String]) -> String {
    values.joined(separator: " ")
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func proves(_ phase: String, strings: [String], identifiers: [String]) -> Bool {
    let text = normalized(strings)
    guard text.contains("qa zc-062-003 active technical task") || text.contains("qa zc-062-003 active technical") else { return false }
    guard !privateWording.contains(where: { text.contains($0.lowercased()) }) else { return false }
    switch phase {
    case "healthy":
        return strongWording.contains(where: { text.contains($0.lowercased()) })
            && identifiers.contains("today.prompt.\(promptID).waiting")
    case "stale":
        return text.contains("limited coverage")
            && text.contains("screenwatch")
            && text.contains("stale")
            && !strongWording.contains(where: { text.contains($0.lowercased()) })
            && !identifiers.contains("today.prompt.\(promptID).waiting")
    case "missing":
        return text.contains("limited coverage")
            && text.contains("screenwatch")
            && (text.contains("missing") || text.contains("no observations"))
            && !strongWording.contains(where: { text.contains($0.lowercased()) })
            && !identifiers.contains("today.prompt.\(promptID).waiting")
    default:
        return false
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let active = "Technical task. QA ZC-062-003 active technical task. Open-ended session."
    guard proves("healthy", strings: [active, "Is this gaming intentional?"], identifiers: ["today.prompt.\(promptID).waiting"]),
          proves("stale", strings: [active, "LIMITED COVERAGE. Screenwatch is stale."], identifiers: []),
          proves("missing", strings: [active, "Limited coverage: Screenwatch has no observations today."], identifiers: []),
          !proves("stale", strings: [active, "Screenwatch is stale.", "Is this gaming intentional?"], identifiers: []),
          !proves("missing", strings: [active, "Limited coverage. Screenwatch is missing.", "qa-zc062003-private-window"], identifiers: []) else {
        fputs("FAIL: ZC-062-003 AX contract self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-062-003 AX probe self-test")
    exit(0)
}

private func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var output: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &output) == .success else { return nil }
    return output
}
private func string(_ element: AXUIElement, _ attribute: CFString) -> String? { value(element, attribute) as? String }
private func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] }
private func allElements(_ root: AXUIElement, limit: Int = 4_000) -> [AXUIElement] {
    var queue = [root], result: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while let element = queue.first, result.count < limit {
        queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        result.append(element)
        queue.append(contentsOf: children(element))
    }
    return result
}

guard AXIsProcessTrusted(), CommandLine.arguments.count == 5,
      CommandLine.arguments[1] == "--pid", let pid = Int32(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase", ["healthy", "stale", "missing"].contains(CommandLine.arguments[4]) else {
    fputs("usage: qa-zc062003-source-warning-suppression-ax-probe.swift --self-test | --pid <pid> --phase <healthy|stale|missing>\n", stderr)
    exit(2)
}

let elements = allElements(AXUIElementCreateApplication(pid))
let windows = elements.filter { string($0, kAXRoleAttribute as CFString) == (kAXWindowRole as String) }
let strings = elements.flatMap { element in
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute].compactMap { string(element, $0 as CFString) }
}
let identifiers = elements.compactMap { string($0, kAXIdentifierAttribute as CFString) }
guard windows.count == 1, proves(CommandLine.arguments[4], strings: strings, identifiers: identifiers) else {
    fputs("FAIL: ZC-062-003 \(CommandLine.arguments[4]) accessibility contract not visible\n", stderr)
    exit(1)
}
print("PASS: ZC-062-003 \(CommandLine.arguments[4]) accessibility contract")
