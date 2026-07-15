#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let elapsedIdentifier = "today.focus.open-ended-elapsed"
private let maximumNodes = 5_000

private enum Phase: String {
    case window
    case liveAdvance = "live-advance"
    case exactLive = "exact-live"
    case fallback
    case absent
}

private struct ElapsedReading: Equatable {
    let minutes: Int
    let isLive: Bool

    var display: String {
        "\(minutes) MIN ELAPSED · \(isLive ? "LIVE" : "LAST REFRESH")"
    }

    var accessibilityLabel: String {
        let unit = minutes == 1 ? "minute" : "minutes"
        if isLive {
            return "Open-ended session, \(minutes) \(unit) elapsed, updating while active."
        }
        return "Open-ended session, \(minutes) \(unit) elapsed at the last refresh."
    }
}

private func reading(from values: [String]) -> ElapsedReading? {
    for value in values {
        let parts = value.components(separatedBy: " MIN ELAPSED · ")
        guard parts.count == 2, let minutes = Int(parts[0]), minutes >= 0 else { continue }
        switch parts[1] {
        case "LIVE": return ElapsedReading(minutes: minutes, isLive: true)
        case "LAST REFRESH": return ElapsedReading(minutes: minutes, isLive: false)
        default: continue
        }
    }
    return nil
}

private func readingIsAccessible(_ reading: ElapsedReading, values: [String]) -> Bool {
    values.contains(reading.display) && values.contains(reading.accessibilityLabel)
}

private func exposesPrivateText(_ values: [String], rejected: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return rejected.contains { combined.localizedCaseInsensitiveContains($0) }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let live = ElapsedReading(minutes: 2, isLive: true)
    let fallback = ElapsedReading(minutes: 9, isLive: false)
    guard reading(from: [live.display, live.accessibilityLabel]) == live,
          reading(from: [fallback.display, fallback.accessibilityLabel]) == fallback,
          reading(from: ["-1 MIN ELAPSED · LIVE"]) == nil,
          reading(from: ["2 MIN ELAPSED · STALE"]) == nil,
          readingIsAccessible(live, values: [live.display, live.accessibilityLabel]),
          !readingIsAccessible(live, values: [live.display]),
          live.accessibilityLabel == "Open-ended session, 2 minutes elapsed, updating while active.",
          ElapsedReading(minutes: 1, isLive: true).accessibilityLabel == "Open-ended session, 1 minute elapsed, updating while active.",
          fallback.display == "9 MIN ELAPSED · LAST REFRESH",
          fallback.accessibilityLabel == "Open-ended session, 9 minutes elapsed at the last refresh.",
          exposesPrivateText(["safe", "PRIVATE-ZC017007-DO-NOT-RENDER"], rejected: ["PRIVATE-ZC017007"]),
          !exposesPrivateText(["Verify live elapsed time"], rejected: ["PRIVATE-ZC017007"])
    else {
        fputs("FAIL: ZC-017-007 elapsed AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-017-007 elapsed AX probe self-test")
    exit(0)
}

private var pid: Int32?
private var phase: Phase?
private var expectedMinutes: Int?
private var minimumMinutes = 0
private var rejected: [String] = []
private var index = 1
while index < CommandLine.arguments.count {
    guard index + 1 < CommandLine.arguments.count else {
        fputs("FAIL: every verifier option requires a value\n", stderr)
        exit(2)
    }
    let value = CommandLine.arguments[index + 1]
    switch CommandLine.arguments[index] {
    case "--pid": pid = Int32(value)
    case "--phase": phase = Phase(rawValue: value)
    case "--expected-minutes": expectedMinutes = Int(value)
    case "--minimum-minutes": minimumMinutes = Int(value) ?? -1
    case "--reject": rejected.append(value)
    default:
        fputs("FAIL: unsupported verifier option\n", stderr)
        exit(2)
    }
    index += 2
}
guard let pid, let phase, minimumMinutes >= 0 else {
    fputs("usage: qa-zc017007-open-ended-elapsed-ax-probe.swift --self-test | --pid <pid> --phase <window|live-advance|exact-live|fallback|absent> [--expected-minutes N] [--minimum-minutes N] [--reject text]...\n", stderr)
    exit(2)
}
if [.exactLive, .fallback].contains(phase), expectedMinutes == nil {
    fputs("FAIL: exact-live and fallback require --expected-minutes\n", stderr)
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

private func mainWindows() -> [AXUIElement] {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    return windows.filter {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
}

private struct Snapshot {
    let elapsedElements: [AXUIElement]
    let allStrings: [String]
}

private func snapshot(window: AXUIElement) throws -> Snapshot {
    var queue = [window]
    var visited = Set<CFHashCode>()
    var elapsedElements: [AXUIElement] = []
    var allStrings: [String] = []
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw NSError(domain: "ZC017007AXProbe", code: 1)
        }
        allStrings.append(contentsOf: values(element))
        if string(element, kAXIdentifierAttribute as CFString) == elapsedIdentifier {
            elapsedElements.append(element)
        }
        queue.append(contentsOf: children(element))
    }
    return Snapshot(elapsedElements: elapsedElements, allStrings: allStrings)
}

private func currentSnapshot() throws -> Snapshot? {
    let windows = mainWindows()
    guard windows.count <= 1 else {
        throw NSError(domain: "ZC017007AXProbe", code: 2)
    }
    guard let window = windows.first else { return nil }
    return try snapshot(window: window)
}

private func waitForSnapshot(timeout: TimeInterval = 10) throws -> Snapshot {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        guard kill(pid, 0) == 0 else {
            throw NSError(domain: "ZC017007AXProbe", code: 3)
        }
        if let current = try currentSnapshot() { return current }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    throw NSError(domain: "ZC017007AXProbe", code: 4)
}

private func uniqueReading(_ snapshot: Snapshot) throws -> ElapsedReading? {
    guard snapshot.elapsedElements.count <= 1 else {
        throw NSError(domain: "ZC017007AXProbe", code: 5)
    }
    guard let element = snapshot.elapsedElements.first else { return nil }
    let elementValues = values(element)
    guard let parsed = reading(from: elementValues), readingIsAccessible(parsed, values: elementValues) else {
        throw NSError(domain: "ZC017007AXProbe", code: 6)
    }
    return parsed
}

do {
    let firstSnapshot = try waitForSnapshot()
    guard !exposesPrivateText(firstSnapshot.allStrings, rejected: rejected) else {
        throw NSError(domain: "ZC017007AXProbe", code: 7)
    }
    switch phase {
    case .window:
        print("PASS: one main Today window is accessible and private fixture text is absent")
    case .absent:
        guard try uniqueReading(firstSnapshot) == nil else {
            throw NSError(domain: "ZC017007AXProbe", code: 8)
        }
        print("PASS: open-ended elapsed indicator is absent")
    case .exactLive, .fallback:
        let expected = ElapsedReading(minutes: expectedMinutes!, isLive: phase == .exactLive)
        guard try uniqueReading(firstSnapshot) == expected else {
            throw NSError(domain: "ZC017007AXProbe", code: 9)
        }
        print("PASS: exact elapsed indicator is \(expected.display)")
    case .liveAdvance:
        guard let initial = try uniqueReading(firstSnapshot), initial.isLive, initial.minutes >= minimumMinutes else {
            throw NSError(domain: "ZC017007AXProbe", code: 10)
        }
        let deadline = Date().addingTimeInterval(75)
        var final = initial
        repeat {
            Thread.sleep(forTimeInterval: 0.5)
            guard let current = try currentSnapshot() else { continue }
            guard !exposesPrivateText(current.allStrings, rejected: rejected) else {
                throw NSError(domain: "ZC017007AXProbe", code: 11)
            }
            guard let next = try uniqueReading(current), next.isLive, next.minutes >= initial.minutes else {
                throw NSError(domain: "ZC017007AXProbe", code: 12)
            }
            final = next
            if final.minutes > initial.minutes { break }
        } while Date() < deadline
        guard final.minutes == initial.minutes + 1 else {
            throw NSError(domain: "ZC017007AXProbe", code: 13)
        }
        print("PASS: visible elapsed time advanced without navigation from \(initial.minutes) to \(final.minutes) minutes")
    }
} catch {
    fputs("FAIL: ZC-017-007 Today accessibility contract failed (\((error as NSError).code))\n", stderr)
    exit(1)
}
