#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let expectedTitle = "Planning is available when you are ready"
private let expectedSummary = "You can review 1 suggested commitment, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked."
private let privateSentinels = ["qa-zc006001-private-window-title", "private.invalid"]
private let workUnplannedPrefix = "today.prompt."
private let workUnplannedSuffix = ".action.work_unplanned"
private let workUnplannedTitle = "WORK UNPLANNED"
private let unplannedEyebrow = "LIMITED UNPLANNED MODE"
private let unplannedTitle = "Work without an approved plan."
private let noDriftCopy = "Tasks and behavior totals remain available, but Zoid 666 will not claim that activity violated a plan that does not exist."

private struct Node {
    let element: AXUIElement
    let identifier: String?
    let values: [String]
}

private func containsPrivateSentinel(_ values: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return privateSentinels.contains { combined.localizedCaseInsensitiveContains($0) }
}

private func workUnplannedPromptID(_ identifier: String?) -> String? {
    guard let identifier,
          identifier.hasPrefix(workUnplannedPrefix),
          identifier.hasSuffix(workUnplannedSuffix)
    else { return nil }
    let start = identifier.index(identifier.startIndex, offsetBy: workUnplannedPrefix.count)
    let end = identifier.index(identifier.endIndex, offsetBy: -workUnplannedSuffix.count)
    let raw = String(identifier[start..<end])
    return UUID(uuidString: raw) == nil ? nil : raw
}

private func invitationIsVisible(_ nodes: [Node]) -> Bool {
    let values = nodes.flatMap(\.values)
    return values.contains(expectedTitle)
        && values.contains(expectedSummary)
        && nodes.filter {
            workUnplannedPromptID($0.identifier) != nil && $0.values.contains(workUnplannedTitle)
        }.count == 1
        && !containsPrivateSentinel(values)
}

private func unplannedStateIsVisible(_ nodes: [Node], promptID: String) -> Bool {
    let values = nodes.flatMap(\.values)
    return values.contains(unplannedEyebrow)
        && values.contains(unplannedTitle)
        && values.contains(noDriftCopy)
        && values.contains { $0.hasPrefix("CHOICE · WORK UNPLANNED ·") }
        && nodes.contains { $0.identifier == "today.prompt.\(promptID).history" }
        && !nodes.contains { workUnplannedPromptID($0.identifier) != nil }
        && !containsPrivateSentinel(values)
}

private func uniqueMainWindowIndex(_ mainFlags: [Bool]) -> Int? {
    let indices = mainFlags.indices.filter { mainFlags[$0] }
    return indices.count == 1 ? indices[0] : nil
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let inert = AXUIElementCreateSystemWide()
    let promptID = "7014B7D1-975E-469C-ABAC-60F9FC3C1766"
    let actionIdentifier = "\(workUnplannedPrefix)\(promptID)\(workUnplannedSuffix)"
    let invitation = [
        Node(element: inert, identifier: nil, values: [expectedTitle, expectedSummary]),
        Node(element: inert, identifier: actionIdentifier, values: [workUnplannedTitle]),
    ]
    let relaunched = [
        Node(element: inert, identifier: nil, values: [unplannedEyebrow, unplannedTitle, noDriftCopy]),
        Node(element: inert, identifier: "today.prompt.\(promptID).history", values: [expectedTitle, expectedSummary, "CHOICE · WORK UNPLANNED · 15 JUL 2026 AT 10:48 AM"]),
    ]
    guard invitationIsVisible(invitation),
          workUnplannedPromptID(actionIdentifier) == promptID,
          workUnplannedPromptID("today.prompt.not-a-uuid.action.work_unplanned") == nil,
          workUnplannedPromptID("planning.invitation.work-unplanned") == nil,
          !invitationIsVisible(Array(invitation.dropLast())),
          !invitationIsVisible(invitation + [invitation.last!]),
          !invitationIsVisible(invitation + [Node(element: inert, identifier: nil, values: [privateSentinels[0]])]),
          unplannedStateIsVisible(relaunched, promptID: promptID),
          !unplannedStateIsVisible(invitation, promptID: promptID),
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

guard [5, 7].contains(CommandLine.arguments.count),
      CommandLine.arguments[1] == "--pid",
      let pid = pid_t(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase",
      ["invitation", "work-unplanned", "unplanned"].contains(CommandLine.arguments[4]),
      AXIsProcessTrusted(),
      kill(pid, 0) == 0
else {
    fputs("usage: qa-zc006002-missed-invitation-ax-probe.swift --self-test | --pid PID --phase invitation|work-unplanned | --pid PID --phase unplanned --prompt-id UUID\n", stderr)
    exit(2)
}
let phase = CommandLine.arguments[4]
let expectedPromptID: String? = CommandLine.arguments.count == 7
    && CommandLine.arguments[5] == "--prompt-id"
    && UUID(uuidString: CommandLine.arguments[6]) != nil
    ? CommandLine.arguments[6]
    : nil
guard (phase == "unplanned") == (expectedPromptID != nil) else {
    fputs("FAIL: unplanned phase requires one valid --prompt-id and other phases reject it\n", stderr)
    exit(2)
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
    guard let expectedPromptID,
          waitFor(application, predicate: { unplannedStateIsVisible($0, promptID: expectedPromptID) }) != nil else {
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
    guard let promptID = visible.compactMap({ workUnplannedPromptID($0.identifier) }).first else {
        fputs("FAIL: exact Work Unplanned prompt identity disappeared\n", stderr)
        exit(1)
    }
    print("PROMPT_ID=\(promptID)")
    print("PASS: ZC-006-002 recovered invitation and exact Work Unplanned prompt action are visible and sentinel-safe")
    exit(0)
}

guard let action = visible.first(where: {
          workUnplannedPromptID($0.identifier) != nil && $0.values.contains(workUnplannedTitle)
      }),
      let promptID = workUnplannedPromptID(action.identifier),
      AXUIElementPerformAction(action.element, kAXPressAction as CFString) == .success
else {
    fputs("FAIL: exact Work Unplanned action was not pressable\n", stderr)
    exit(1)
}
guard waitFor(application, predicate: { unplannedStateIsVisible($0, promptID: promptID) }) != nil else {
    fputs("FAIL: Work Unplanned did not produce its immediate sentinel-safe unplanned and no-drift UI\n", stderr)
    exit(1)
}
print("PROMPT_ID=\(promptID)")
print("PASS: ZC-006-002 Work Unplanned reached immediate LIMITED UNPLANNED MODE and no-drift feedback")
