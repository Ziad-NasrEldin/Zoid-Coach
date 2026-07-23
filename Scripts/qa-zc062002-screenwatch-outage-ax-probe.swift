#!/usr/bin/env swift

import ApplicationServices
import Foundation

private func normalized(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func verifiesActiveTask(_ values: [String]) -> Bool {
    let text = normalized(values.joined(separator: " "))
    return text.contains("active work")
        && text.contains("qa zc-062-002 active technical task")
        && text.contains("technical")
        && !text.contains("qa-zc062002-private")
        && !text.contains("private.invalid")
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard verifiesActiveTask(["ACTIVE WORK", "QA ZC-062-002 active technical task", "Technical task. Active timer."]),
          !verifiesActiveTask(["ACTIVE WORK", "Different task", "Technical"]),
          !verifiesActiveTask(["ACTIVE WORK", "QA ZC-062-002 active technical task", "qa-zc062002-private-window"]) else {
        fputs("FAIL: active-task AX contract self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-062-002 active-task AX probe self-test")
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
      CommandLine.arguments[3] == "--phase",
      ["fresh", "stale", "missing"].contains(CommandLine.arguments[4]) else {
    fputs("usage: qa-zc062002-screenwatch-outage-ax-probe.swift --self-test | --pid <pid> --phase <fresh|stale|missing>\n", stderr)
    exit(2)
}

let elements = allElements(AXUIElementCreateApplication(pid))
let windows = elements.filter { string($0, kAXRoleAttribute as CFString) == (kAXWindowRole as String) }
guard windows.count == 1 else {
    fputs("FAIL: expected exactly one foreground window\n", stderr)
    exit(1)
}

let dayState = elements.first { string($0, kAXIdentifierAttribute as CFString) == "today.day-state" }
let activeTiming = elements.first { string($0, kAXIdentifierAttribute as CFString) == "today.active-commitment.timing-mode" }
guard let dayState, let activeTiming,
      verifiesActiveTask(exposed(dayState) + exposed(activeTiming)) else {
    fputs("FAIL: active technical task did not persist in the Today accessibility surface\n", stderr)
    exit(1)
}

print("PASS: ZC-062-002 \(CommandLine.arguments[4]) stream state keeps the active task visible")
