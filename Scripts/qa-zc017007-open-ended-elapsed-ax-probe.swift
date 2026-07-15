#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private let expectedTaskTitle = "Verify live elapsed time"
private let maximumNodes = 5_000
private let maximumScrollSteps = 4

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

private enum UniqueFrameSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private func exactAXText(_ actual: String, _ expected: String) -> Bool {
    actual.caseInsensitiveCompare(expected) == .orderedSame
}

private func selectUniqueFrame(_ frames: [CGRect]) -> UniqueFrameSelection {
    switch frames.count {
    case 1: return .selected(0)
    case 0: return .missing
    default: return .ambiguous
    }
}

private func movedTowardTop(from before: CGRect, to after: CGRect) -> Bool {
    after.minY < before.minY
}

private func mayPostPhysicalScroll(expectedPID: pid_t, frontmostPID: pid_t?) -> Bool {
    expectedPID == frontmostPID
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
    values.contains(where: { exactAXText($0, reading.display) })
        && values.contains(where: { exactAXText($0, reading.accessibilityLabel) })
}

private func exposesPrivateText(_ values: [String], rejected: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return rejected.contains { combined.localizedCaseInsensitiveContains($0) }
}

private func scenarioIsReady(allStrings: [String], elapsedCount: Int, requireElapsed: Bool) -> Bool {
    allStrings.contains(where: { $0.contains(expectedTaskTitle) })
        && (!requireElapsed || elapsedCount == 1)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let live = ElapsedReading(minutes: 2, isLive: true)
    let fallback = ElapsedReading(minutes: 9, isLive: false)
    guard reading(from: [live.display, live.accessibilityLabel]) == live,
          reading(from: [fallback.display, fallback.accessibilityLabel]) == fallback,
          reading(from: ["-1 MIN ELAPSED · LIVE"]) == nil,
          reading(from: ["2 MIN ELAPSED · STALE"]) == nil,
          readingIsAccessible(live, values: [live.display, live.accessibilityLabel]),
          readingIsAccessible(live, values: [live.display, live.accessibilityLabel.uppercased()]),
          !readingIsAccessible(live, values: [live.display]),
          live.accessibilityLabel == "Open-ended session, 2 minutes elapsed, updating while active.",
          ElapsedReading(minutes: 1, isLive: true).accessibilityLabel == "Open-ended session, 1 minute elapsed, updating while active.",
          fallback.display == "9 MIN ELAPSED · LAST REFRESH",
          fallback.accessibilityLabel == "Open-ended session, 9 minutes elapsed at the last refresh.",
          scenarioIsReady(allStrings: [expectedTaskTitle], elapsedCount: 0, requireElapsed: false),
          scenarioIsReady(allStrings: [expectedTaskTitle], elapsedCount: 1, requireElapsed: true),
          !scenarioIsReady(allStrings: ["PREPARING TODAY"], elapsedCount: 0, requireElapsed: false),
          !scenarioIsReady(allStrings: [expectedTaskTitle], elapsedCount: 0, requireElapsed: true),
          selectUniqueFrame([]) == .missing,
          selectUniqueFrame([CGRect(x: 0, y: 0, width: 10, height: 10)]) == .selected(0),
          selectUniqueFrame([
              CGRect(x: 0, y: 0, width: 10, height: 10),
              CGRect(x: 20, y: 0, width: 10, height: 10),
          ]) == .ambiguous,
          movedTowardTop(
              from: CGRect(x: 0, y: 100, width: 10, height: 10),
              to: CGRect(x: 0, y: 80, width: 10, height: 10)
          ),
          !movedTowardTop(
              from: CGRect(x: 0, y: 100, width: 10, height: 10),
              to: CGRect(x: 0, y: 100, width: 10, height: 10)
          ),
          mayPostPhysicalScroll(expectedPID: 123, frontmostPID: 123),
          !mayPostPhysicalScroll(expectedPID: 123, frontmostPID: 456),
          !mayPostPhysicalScroll(expectedPID: 123, frontmostPID: nil),
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

private func frame(_ element: AXUIElement) -> CGRect? {
    guard let raw = attribute(element, "AXFrame" as CFString),
          CFGetTypeID(raw) == AXValueGetTypeID(),
          AXValueGetType(unsafeBitCast(raw, to: AXValue.self)) == .cgRect else {
        return nil
    }
    var value = CGRect.zero
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgRect, &value) else {
        return nil
    }
    return value
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
    let scenarioAnchorElements: [AXUIElement]
    let scenarioAnchorFrames: [CGRect]
    let scrollSurfaceFrames: [CGRect]
    let windowFrame: CGRect
}

private func snapshot(window: AXUIElement) throws -> Snapshot {
    guard let windowFrame = frame(window) else {
        throw NSError(domain: "ZC017007AXProbe", code: 15)
    }
    var queue = [window]
    var visited = Set<CFHashCode>()
    var elapsedElements: [AXUIElement] = []
    var allStrings: [String] = []
    var scenarioAnchorElements: [AXUIElement] = []
    var scenarioAnchorFrames: [CGRect] = []
    var scrollSurfaceFrames: [CGRect] = []
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else {
            throw NSError(domain: "ZC017007AXProbe", code: 1)
        }
        let elementValues = values(element)
        let elementFrame = frame(element)
        allStrings.append(contentsOf: elementValues)
        if let elapsed = reading(from: elementValues),
           readingIsAccessible(elapsed, values: elementValues) {
            elapsedElements.append(element)
        }
        if elementValues.contains(where: { exactAXText($0, expectedTaskTitle) }),
           let elementFrame,
           elementFrame.intersects(windowFrame) {
            scenarioAnchorElements.append(element)
            scenarioAnchorFrames.append(elementFrame)
        }
        if string(element, kAXRoleAttribute as CFString) == kAXScrollAreaRole as String,
           let elementFrame,
           elementFrame.intersects(windowFrame) {
            scrollSurfaceFrames.append(elementFrame)
        }
        queue.append(contentsOf: children(element))
    }
    return Snapshot(
        elapsedElements: elapsedElements,
        allStrings: allStrings,
        scenarioAnchorElements: scenarioAnchorElements,
        scenarioAnchorFrames: scenarioAnchorFrames,
        scrollSurfaceFrames: scrollSurfaceFrames,
        windowFrame: windowFrame
    )
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

private func postBoundedScroll(from snapshot: Snapshot) throws -> (AXUIElement, CGRect) {
    let anchorIndex: Int
    switch selectUniqueFrame(snapshot.scenarioAnchorFrames) {
    case let .selected(index): anchorIndex = index
    case .missing: throw NSError(domain: "ZC017007AXProbe", code: 16)
    case .ambiguous: throw NSError(domain: "ZC017007AXProbe", code: 17)
    }
    let surfaceFrame: CGRect
    switch selectUniqueFrame(snapshot.scrollSurfaceFrames) {
    case let .selected(index): surfaceFrame = snapshot.scrollSurfaceFrames[index]
    case .missing: throw NSError(domain: "ZC017007AXProbe", code: 18)
    case .ambiguous: throw NSError(domain: "ZC017007AXProbe", code: 19)
    }
    guard mayPostPhysicalScroll(
        expectedPID: pid,
        frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
    ) else {
        throw NSError(domain: "ZC017007AXProbe", code: 20)
    }
    guard CGPreflightPostEventAccess(),
          let move = CGEvent(
              mouseEventSource: nil,
              mouseType: .mouseMoved,
              mouseCursorPosition: CGPoint(x: surfaceFrame.midX, y: surfaceFrame.midY),
              mouseButton: .left
          ),
          let wheel = CGEvent(
              scrollWheelEvent2Source: nil,
              units: .pixel,
              wheelCount: 1,
              wheel1: -420,
              wheel2: 0,
              wheel3: 0
          ) else {
        throw NSError(domain: "ZC017007AXProbe", code: 21)
    }
    let scrollPoint = CGPoint(x: surfaceFrame.midX, y: surfaceFrame.midY)
    move.post(tap: .cghidEventTap)
    wheel.location = scrollPoint
    wheel.post(tap: .cghidEventTap)
    return (snapshot.scenarioAnchorElements[anchorIndex], snapshot.scenarioAnchorFrames[anchorIndex])
}

private func waitForScenarioSnapshot(requireElapsed: Bool, timeout: TimeInterval = 30) throws -> Snapshot {
    let deadline = Date().addingTimeInterval(timeout)
    var scrollSteps = 0
    repeat {
        guard kill(pid, 0) == 0 else {
            throw NSError(domain: "ZC017007AXProbe", code: 3)
        }
        if let current = try currentSnapshot() {
            if scenarioIsReady(
                allStrings: current.allStrings,
                elapsedCount: current.elapsedElements.count,
                requireElapsed: requireElapsed
            ) {
                return current
            }
            if requireElapsed,
               current.elapsedElements.isEmpty,
               current.allStrings.contains(where: { exactAXText($0, expectedTaskTitle) }),
               scrollSteps < maximumScrollSteps {
                let (anchor, beforeFrame) = try postBoundedScroll(from: current)
                Thread.sleep(forTimeInterval: 0.35)
                guard let afterFrame = frame(anchor),
                      movedTowardTop(from: beforeFrame, to: afterFrame) else {
                    throw NSError(domain: "ZC017007AXProbe", code: 22)
                }
                scrollSteps += 1
                continue
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    throw NSError(domain: "ZC017007AXProbe", code: 14)
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
    let firstSnapshot: Snapshot
    switch phase {
    case .window:
        firstSnapshot = try waitForSnapshot()
    case .absent:
        firstSnapshot = try waitForScenarioSnapshot(requireElapsed: false)
    case .liveAdvance, .exactLive, .fallback:
        firstSnapshot = try waitForScenarioSnapshot(requireElapsed: true)
    }
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
