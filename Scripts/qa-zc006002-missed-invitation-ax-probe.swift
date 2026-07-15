#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let expectedTitle = "Planning is available when you are ready"
private let privateSentinel = "qa-zc006001-private-window-title"

private func isPrivacySafeInvitation(_ values: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return values.contains(expectedTitle)
        && combined.localizedCaseInsensitiveContains("review")
        && combined.localizedCaseInsensitiveContains("nothing is blocked")
        && !combined.localizedCaseInsensitiveContains(privateSentinel)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard isPrivacySafeInvitation([
        expectedTitle,
        "You can review 1 suggested commitment. Nothing is blocked.",
    ]),
    !isPrivacySafeInvitation([expectedTitle, privateSentinel]),
    !isPrivacySafeInvitation(["Plan ready", "Review"])
    else {
        fputs("FAIL: ZC-006-002 AX self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-006-002 AX self-test rejects missing copy and private evidence")
    exit(0)
}

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--pid",
      let pid = pid_t(CommandLine.arguments[2]),
      AXIsProcessTrusted(),
      kill(pid, 0) == 0
else {
    fputs("usage: qa-zc006002-missed-invitation-ax-probe.swift --self-test | --pid PID\n", stderr)
    exit(2)
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func textValues(_ root: AXUIElement, limit: Int = 5_000) -> [String] {
    var queue = [root]
    var values: [String] = []
    var visited = 0
    while !queue.isEmpty, visited < limit {
        let element = queue.removeFirst()
        visited += 1
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            if let value = attribute(element, name as CFString) as? String, !value.isEmpty {
                values.append(value)
            }
        }
        queue.append(contentsOf: attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [])
    }
    return values
}

let application = AXUIElementCreateApplication(pid)
for _ in 0..<100 {
    guard kill(pid, 0) == 0 else { break }
    let values = textValues(application)
    if isPrivacySafeInvitation(values) {
        print("PASS: ZC-006-002 recovered invitation is visible and privacy-safe")
        exit(0)
    }
    usleep(200_000)
}
fputs("FAIL: recovered planning invitation was not visible in the exact app process\n", stderr)
exit(1)
