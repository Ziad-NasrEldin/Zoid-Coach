#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let expectedTitle = "Planning is available when you are ready"
private let expectedSummary = "You can review 1 suggested commitment, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
private let privateSentinels = ["qa-zc006001-private-window-title", "private.invalid"]
private let workUnplannedIdentifier = "planning.invitation.work-unplanned"
private let unplannedEyebrow = "LIMITED UNPLANNED MODE"
private let unplannedTitle = "Work without an approved plan."
private let noDriftCopy = "Tasks and behavior totals remain available, but Zoid 666 will not claim that activity violated a plan that does not exist."
private let immediateFeedback = "Planning is skipped for now. You can still start any available task or return to planning later."

private struct Node {
    let element: AXUIElement
    let identifier: String?
    let values: [String]
}

private func containsPrivateSentinel(_ values: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return privateSentinels.contains { combined.localizedCaseInsensitiveContains($0) }
}

private func invitationIsVisible(_ nodes: [Node]) -> Bool {
    let values = nodes.flatMap(\.values)
    return values.contains(expectedTitle)
        && values.contains(expectedSummary)
        && nodes.filter { $0.identifier == workUnplannedIdentifier }.count == 1
        && !containsPrivateSentinel(values)
}

private func unplannedStateIsVisible(_ nodes: [Node], requireImmediateFeedback: Bool) -> Bool {
    let values = nodes.flatMap(\.values)
    return values.contains(unplannedEyebrow)
        && values.contains(unplannedTitle)
        && values.contains(noDriftCopy)
        && (!requireImmediateFeedback || values.contains(immediateFeedback))
        && !values.contains(expectedTitle)
        && !values.contains(expectedSummary)
        && !nodes.contains { $0.identifier == workUnplannedIdentifier }
        && !containsPrivateSentinel(values)
}

private func uniqueMainWindowIndex(_ mainFlags: [Bool]) -> Int? {
    let indices = mainFlags.indices.filter { mainFlags[$0] }
    return indices.count == 1 ? indices[0] : nil
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let inert = AXUIElementCreateSystemWide()
    let invitation = [
        Node(element: inert, identifier: nil, values: [expectedTitle, expectedSummary]),
        Node(element: inert, identifier: workUnplannedIdentifier, values: ["WORK UNPLANNED"]),
    ]
    let immediate = [Node(element: inert, identifier: nil, values: [unplannedEyebrow, unplannedTitle, noDriftCopy, immediateFeedback])]
    let relaunched = [Node(element: inert, identifier: nil, values: [unplannedEyebrow, unplannedTitle, noDriftCopy])]
    guard invitationIsVisible(invitation),
          !invitationIsVisible(Array(invitation.dropLast())),
          !invitationIsVisible(invitation + [invitation.last!]),
          !invitationIsVisible(invitation + [Node(element: inert, identifier: nil, values: [privateSentinels[0]])]),
          unplannedStateIsVisible(immediate, requireImmediateFeedback: true),
          !unplannedStateIsVisible(relaunched, requireImmediateFeedback: true),
          unplannedStateIsVisible(relaunched, requireImmediateFeedback: false),
          !unplannedStateIsVisible(invitation, requireImmediateFeedback: false),
          uniqueMainWindowIndex([true]) == 0,
          uniqueMainWindowIndex([]) == nil,
          uniqueMainWindowIndex([true, true]) == nil
    else {
        fputs("FAIL: ZC-006-002 AX self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-006-002 AX self-test covers exact action, immediate feedback, relaunch state, privacy sentinels, and exact main window")
    exit(0)
}

guard CommandLine.arguments.count == 5,
      CommandLine.arguments[1] == "--pid",
      let pid = pid_t(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase",
      ["invitation", "work-unplanned", "unplanned"].contains(CommandLine.arguments[4]),
      AXIsProcessTrusted(),
      kill(pid, 0) == 0
else {
    fputs("usage: qa-zc006002-missed-invitation-ax-probe.swift --self-test | --pid PID --phase invitation|work-unplanned|unplanned\n", stderr)
    exit(2)
}
let phase = CommandLine.arguments[4]

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

private func snapshot(_ application: AXUIElement) -> [Node]? {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    let mainFlags = windows.map {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
    guard let index = uniqueMainWindowIndex(mainFlags) else { return nil }
    return nodes(from: windows[index])
}

private func waitFor(_ application: AXUIElement, predicate: ([Node]) -> Bool) -> [Node]? {
    for _ in 0..<100 {
        guard kill(pid, 0) == 0 else { return nil }
        if let current = snapshot(application), predicate(current) { return current }
        usleep(200_000)
    }
    return nil
}

let application = AXUIElementCreateApplication(pid)
if phase == "unplanned" {
    guard waitFor(application, predicate: { unplannedStateIsVisible($0, requireImmediateFeedback: false) }) != nil else {
        fputs("FAIL: durable unplanned state was not visible after ordinary relaunch\n", stderr)
        exit(1)
    }
    print("PASS: ZC-006-002 durable unplanned state is visible and sentinel-safe after ordinary relaunch")
    exit(0)
}

guard let visible = waitFor(application, predicate: invitationIsVisible) else {
    fputs("FAIL: exact recovered invitation and Work Unplanned action were not visible in the exact main window\n", stderr)
    exit(1)
}
if phase == "invitation" {
    print("PASS: ZC-006-002 recovered invitation and exact Work Unplanned action are visible and sentinel-safe")
    exit(0)
}

guard let action = visible.first(where: { $0.identifier == workUnplannedIdentifier }),
      AXUIElementPerformAction(action.element, kAXPressAction as CFString) == .success
else {
    fputs("FAIL: exact Work Unplanned action was not pressable\n", stderr)
    exit(1)
}
guard waitFor(application, predicate: { unplannedStateIsVisible($0, requireImmediateFeedback: true) }) != nil else {
    fputs("FAIL: Work Unplanned did not produce its immediate sentinel-safe UI feedback\n", stderr)
    exit(1)
}
print("PASS: ZC-006-002 Work Unplanned reached immediate LIMITED UNPLANNED MODE feedback")
