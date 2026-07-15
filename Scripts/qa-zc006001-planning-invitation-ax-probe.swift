#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let expectedTitle = "Planning is available when you are ready"
private let privateSentinels = ["qa-zc006001-private-window-title", "private.invalid"]
private let actionIdentifiers = [
    "planning.invitation.snooze",
    "planning.invitation.dismiss",
    "planning.invitation.work-unplanned"
]

private struct Node {
    let element: AXUIElement
    let identifier: String?
    let values: [String]
}

private func expectedSummary(_ count: Int) -> String? {
    switch count {
    case 0:
        "You can make a small plan, or start without one. You can snooze or dismiss this invitation for now. Nothing is blocked."
    case 1:
        "You can review 1 suggested commitment, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
    case 3:
        "You can review 3 suggested commitments, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
    default:
        nil
    }
}

private func hasOrderedActions(_ identifiers: [String]) -> Bool {
    var cursor = identifiers.startIndex
    for expected in actionIdentifiers {
        guard let found = identifiers[cursor...].firstIndex(of: expected) else { return false }
        cursor = identifiers.index(after: found)
    }
    return true
}

private func containsPrivateSentinel(_ values: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return privateSentinels.contains { combined.localizedCaseInsensitiveContains($0) }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard expectedSummary(0)?.contains("start without one") == true,
          expectedSummary(1)?.contains("1 suggested commitment") == true,
          expectedSummary(3)?.contains("3 suggested commitments") == true,
          expectedSummary(2) == nil,
          hasOrderedActions(actionIdentifiers),
          !hasOrderedActions([actionIdentifiers[1], actionIdentifiers[0], actionIdentifiers[2]]),
          !containsPrivateSentinel([expectedTitle, expectedSummary(3)!]),
          containsPrivateSentinel([expectedTitle, "qa-zc006001-private-window-title"])
    else {
        fputs("FAIL: ZC-006-001 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-006-001 AX probe self-test")
    exit(0)
}

var pid: pid_t?
var phase: String?
var count: Int?
var index = 1
while index < CommandLine.arguments.count {
    guard index + 1 < CommandLine.arguments.count else {
        fputs("FAIL: option requires a value\n", stderr)
        exit(2)
    }
    switch CommandLine.arguments[index] {
    case "--pid": pid = pid_t(CommandLine.arguments[index + 1])
    case "--phase": phase = CommandLine.arguments[index + 1]
    case "--count": count = Int(CommandLine.arguments[index + 1])
    default:
        fputs("FAIL: unsupported option\n", stderr)
        exit(2)
    }
    index += 2
}

guard let pid, let phase, let count, expectedSummary(count) != nil,
      ["before", "inspect", "snooze", "dismiss", "work-unplanned", "persisted"].contains(phase)
else {
    fputs("usage: qa-zc006001-planning-invitation-ax-probe.swift --self-test | --pid PID --phase before|inspect|snooze|dismiss|work-unplanned|persisted --count 0|1|3\n", stderr)
    exit(2)
}
guard AXIsProcessTrusted(), kill(pid, 0) == 0 else {
    fputs("FAIL: Accessibility permission or exact app process is unavailable\n", stderr)
    exit(1)
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func nodes(from root: AXUIElement, limit: Int = 5_000) -> [Node] {
    var queue = [root]
    var result: [Node] = []
    while !queue.isEmpty, result.count < limit {
        let element = queue.removeFirst()
        let values = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { string(element, $0 as CFString) }
            .filter { !$0.isEmpty }
        result.append(Node(
            element: element,
            identifier: string(element, "AXIdentifier" as CFString),
            values: values
        ))
        queue.append(contentsOf: children(element))
    }
    return result
}

private func mainWindow(_ application: AXUIElement) -> AXUIElement? {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    let mains = windows.filter {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
    return mains.count == 1 ? mains[0] : nil
}

private func snapshot(_ application: AXUIElement) -> [Node]? {
    guard let window = mainWindow(application) else { return nil }
    return nodes(from: window)
}

private func waitFor(
    application: AXUIElement,
    attempts: Int = 40,
    predicate: ([Node]) -> Bool
) -> [Node]? {
    for _ in 0..<attempts {
        guard kill(pid, 0) == 0 else { return nil }
        if let current = snapshot(application), predicate(current) { return current }
        usleep(200_000)
    }
    return nil
}

private func flattenedValues(_ nodes: [Node]) -> [String] {
    nodes.flatMap(\.values)
}

let application = AXUIElementCreateApplication(pid)
let summary = expectedSummary(count)!

if phase == "before" {
    guard let current = waitFor(application: application, predicate: { nodes in
        let values = flattenedValues(nodes)
        return !values.contains(expectedTitle)
            && !values.contains(summary)
            && nodes.allSatisfy { !actionIdentifiers.contains($0.identifier ?? "") }
            && !containsPrivateSentinel(values)
    }) else {
        fputs("FAIL: planning invitation appeared before the configured boundary or private evidence leaked\n", stderr)
        exit(1)
    }
    print("PASS: ZC-006-001 invitation absent before configured planning time (\(current.count) AX nodes)")
    exit(0)
}

guard let visible = waitFor(application: application, predicate: { nodes in
    let values = flattenedValues(nodes)
    return values.contains(expectedTitle)
        && values.contains(summary)
        && hasOrderedActions(nodes.compactMap(\.identifier))
        && !containsPrivateSentinel(values)
}) else {
    fputs("FAIL: exact optional invitation, stable action order, or privacy boundary was not visible\n", stderr)
    exit(1)
}

if phase == "inspect" || phase == "persisted" {
    print("PASS: ZC-006-001 \(count)-suggestion invitation is visible, optional, ordered, and privacy-safe")
    exit(0)
}

let targetIdentifier: String
let expectedAfter: String
switch phase {
case "snooze":
    targetIdentifier = "planning.invitation.snooze"
    expectedAfter = "PLANNING SNOOZED"
case "dismiss":
    targetIdentifier = "planning.invitation.dismiss"
    expectedAfter = "PLANNING DISMISSED"
case "work-unplanned":
    targetIdentifier = "planning.invitation.work-unplanned"
    expectedAfter = "LIMITED UNPLANNED MODE"
default:
    fatalError("validated phase")
}

guard let target = visible.first(where: { $0.identifier == targetIdentifier }),
      AXUIElementPerformAction(target.element, kAXPressAction as CFString) == .success
else {
    fputs("FAIL: exact invitation action was not pressable\n", stderr)
    exit(1)
}
guard waitFor(application: application, predicate: { nodes in
    let values = flattenedValues(nodes)
    return values.contains(where: { $0.localizedCaseInsensitiveContains(expectedAfter) })
        && !containsPrivateSentinel(values)
}) != nil else {
    fputs("FAIL: invitation action did not reach its expected user-visible state\n", stderr)
    exit(1)
}
print("PASS: ZC-006-001 \(phase) reached \(expectedAfter)")
