#!/usr/bin/env swift

import ApplicationServices
import Foundation

private func normalized(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func matches(_ exposed: [String], expected: String) -> Bool {
    let expected = normalized(expected)
    return exposed.contains { normalized($0).contains(expected) }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard matches(["TECHNICAL TASK"], expected: "technical task"),
          matches(["Technical task. QA task."], expected: "technical task"),
          !matches(["General task"], expected: "technical task") else {
        fputs("FAIL: AX normalization self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-061-001 technical-task AX probe self-test")
    exit(0)
}

private func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var output: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &output) == .success else { return nil }
    return output
}

private func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
    value(element, attribute) as? String
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func exposed(_ element: AXUIElement) -> [String] {
    [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func allElements(_ root: AXUIElement, limit: Int = 4_000) -> [AXUIElement] {
    var queue = [root]
    var result: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while let element = queue.first, result.count < limit {
        queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        result.append(element)
        queue.append(contentsOf: children(element))
    }
    return result
}

guard AXIsProcessTrusted(),
      CommandLine.arguments.count == 5,
      CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase" else {
    fputs("usage: qa-zc061001-technical-task-ax-probe.swift --self-test | --pid <pid> --phase <creation-visible|active-visible>\n", stderr)
    exit(2)
}

let elements = allElements(AXUIElementCreateApplication(pid))
switch CommandLine.arguments[4] {
case "creation-visible":
    guard elements.contains(where: { string($0, kAXIdentifierAttribute as CFString) == "local-task-technical-context" }),
          elements.contains(where: { string($0, kAXIdentifierAttribute as CFString) == "local-task-save" }),
          elements.contains(where: { matches(exposed($0), expected: "technical task") }) else {
        fputs("FAIL: technical creation control is not exposed\n", stderr)
        exit(1)
    }
case "active-visible":
    guard elements.contains(where: { matches(exposed($0), expected: "technical task") }),
          elements.contains(where: { matches(exposed($0), expected: "active commitment") }) else {
        fputs("FAIL: active technical context is not exposed\n", stderr)
        exit(1)
    }
default:
    fputs("FAIL: unsupported phase\n", stderr)
    exit(2)
}
print("PASS: ZC-061-001 \(CommandLine.arguments[4]) AX boundary")
