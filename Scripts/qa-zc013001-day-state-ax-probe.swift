#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let dayStateIdentifier = "today.day-state"
private let maximumNodes = 4_000

private func matchesDayState(
    _ values: [String],
    expectedDate: String,
    expectedState: String
) -> Bool {
    let combined = values.joined(separator: " ")
    return combined.localizedCaseInsensitiveContains(expectedDate)
        && combined.localizedCaseInsensitiveContains("Day state")
        && combined.localizedCaseInsensitiveContains(expectedState)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let valid = [
        "Tuesday, July 14. Day state: ACTIVE WORK. One task is currently tracking time.",
    ]
    guard matchesDayState(valid, expectedDate: "Tuesday, July 14", expectedState: "Active work"),
          !matchesDayState(valid, expectedDate: "Monday, July 13", expectedState: "Active work"),
          !matchesDayState(valid, expectedDate: "Tuesday, July 14", expectedState: "Planned day"),
          matchesDayState(
              ["Wednesday, July 15", "Day state", "Preparing today"],
              expectedDate: "Wednesday, July 15",
              expectedState: "Preparing today"
          )
    else {
        fputs("FAIL: ZC-013-001 day-state AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-013-001 day-state AX probe self-test")
    exit(0)
}

let arguments = CommandLine.arguments
guard arguments.count == 7,
      arguments[1] == "--pid",
      let pid = Int32(arguments[2]),
      arguments[3] == "--expected-date",
      arguments[5] == "--expected-state"
else {
    fputs(
        "usage: qa-zc013001-day-state-ax-probe.swift --self-test | --pid <pid> --expected-date <date> --expected-state <state>\n",
        stderr
    )
    exit(2)
}

guard AXIsProcessTrusted() else {
    fputs("FAIL: Accessibility permission is required\n", stderr)
    exit(1)
}
guard kill(pid, 0) == 0 else {
    fputs("FAIL: supplied application process is not running\n", stderr)
    exit(1)
}

let expectedDate = arguments[4]
let expectedState = arguments[6]
let application = AXUIElementCreateApplication(pid)

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

private func values(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func dayStateElements(root: AXUIElement) throws -> [AXUIElement] {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var matches: [AXUIElement] = []
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw NSError(domain: "ZC013001AXProbe", code: 1)
        }
        if string(element, kAXIdentifierAttribute as CFString) == dayStateIdentifier {
            matches.append(element)
        }
        queue.append(contentsOf: children(element))
    }
    return matches
}

do {
    var matches: [AXUIElement] = []
    for _ in 0..<40 {
        matches = try dayStateElements(root: application)
        if !matches.isEmpty { break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard matches.count == 1, let dayState = matches.first else {
        fputs("FAIL: expected exactly one visible Today day-state header\n", stderr)
        exit(1)
    }
    guard matchesDayState(
        values(dayState),
        expectedDate: expectedDate,
        expectedState: expectedState
    ) else {
        fputs("FAIL: Today day-state header did not expose the expected date and state\n", stderr)
        exit(1)
    }
    print("PASS: ZC-013-001 visible date and day state")
} catch {
    fputs("FAIL: Today day-state accessibility traversal failed\n", stderr)
    exit(1)
}
