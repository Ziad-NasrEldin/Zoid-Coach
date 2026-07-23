#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let taskTitle = "QA ZC-062-004 active technical task"
private let privateSentinels = ["qa-zc062004-private", "qa-zc062004.private.invalid"]

private func normalized(_ values: [String]) -> String {
    values.joined(separator: " ")
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func trackedMinutes(in text: String) -> [Int] {
    guard let expression = try? NSRegularExpression(pattern: #"([0-9]+) minutes tracked"#) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[valueRange])
    }
}

private func proves(phase: String, minimumElapsed: Int, strings: [String], identifiers: [String]) -> Bool {
    let text = normalized(strings)
    guard identifiers.contains("today.active-commitment.timing-mode"),
          text.contains(taskTitle.lowercased()),
          text.contains("open-ended session"),
          trackedMinutes(in: text).contains(where: { $0 >= minimumElapsed }),
          text.contains("pause \(taskTitle.lowercased())"),
          text.contains("complete focus \(taskTitle.lowercased())"),
          privateSentinels.allSatisfy({ !text.contains($0) }) else { return false }
    switch phase {
    case "fresh":
        return text.contains("screenwatch coverage is current") || text.contains("observed activity is current")
    case "stale":
        return text.contains("limited coverage") && text.contains("screenwatch") && text.contains("stale")
    case "missing":
        return text.contains("limited coverage") && text.contains("screenwatch")
            && (text.contains("missing") || text.contains("no observations"))
    default:
        return false
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let controls = [
        "Technical task. \(taskTitle). Open-ended session. 19 minutes tracked.",
        "Pause \(taskTitle)",
        "Complete focus \(taskTitle)",
    ]
    let identifiers = ["today.active-commitment.timing-mode"]
    guard proves(phase: "fresh", minimumElapsed: 19, strings: controls + ["Screenwatch coverage is current."], identifiers: identifiers),
          proves(phase: "stale", minimumElapsed: 19, strings: controls + ["Limited coverage: Screenwatch is stale."], identifiers: identifiers),
          proves(phase: "missing", minimumElapsed: 19, strings: controls + ["Limited coverage: Screenwatch has no observations today."], identifiers: identifiers),
          !proves(phase: "stale", minimumElapsed: 20, strings: controls + ["Limited coverage: Screenwatch is stale."], identifiers: identifiers),
          !proves(phase: "missing", minimumElapsed: 19, strings: controls + ["qa-zc062004-private-window", "Screenwatch is missing."], identifiers: identifiers) else {
        fputs("FAIL: ZC-062-004 AX contract self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-062-004 AX probe self-test")
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

guard AXIsProcessTrusted(), CommandLine.arguments.count == 7,
      CommandLine.arguments[1] == "--pid", let pid = Int32(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase", ["fresh", "stale", "missing"].contains(CommandLine.arguments[4]),
      CommandLine.arguments[5] == "--minimum-elapsed", let minimumElapsed = Int(CommandLine.arguments[6]) else {
    fputs("usage: qa-zc062004-manual-tracking-outage-ax-probe.swift --self-test | --pid <pid> --phase <fresh|stale|missing> --minimum-elapsed <minutes>\n", stderr)
    exit(2)
}

let elements = allElements(AXUIElementCreateApplication(pid))
let windows = elements.filter { string($0, kAXRoleAttribute as CFString) == (kAXWindowRole as String) }
let strings = elements.flatMap { element in
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute].compactMap { string(element, $0 as CFString) }
}
let identifiers = elements.compactMap { string($0, kAXIdentifierAttribute as CFString) }
guard windows.count == 1,
      proves(phase: CommandLine.arguments[4], minimumElapsed: minimumElapsed, strings: strings, identifiers: identifiers) else {
    fputs("FAIL: ZC-062-004 manual tracking accessibility contract not visible\n", stderr)
    exit(1)
}
print("PASS: ZC-062-004 \(CommandLine.arguments[4]) manual tracking at \(minimumElapsed)+ minutes")
