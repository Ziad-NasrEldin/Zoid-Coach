#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let dayStateIdentifier = "today.day-state"
private let maximumNodes = 4_000

private func matchesDayState(
    _ values: [String],
    expectedDate: String,
    expectedState: String,
    expectedCopy: String
) -> Bool {
    let expected = "\(expectedDate). Day state: \(expectedState). \(expectedCopy)"
    return values.contains(expected)
}

private func exposesPrivateSentinel(_ values: [String], rejected: [String]) -> Bool {
    let combined = values.joined(separator: " ")
    return rejected.contains { combined.localizedCaseInsensitiveContains($0) }
}

private func formattedDayStateDate(
    _ date: Date,
    locale: Locale,
    calendar: Calendar,
    timeZone: TimeZone
) -> String {
    date.formatted(
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .weekday(.wide)
            .month(.wide)
            .day()
    )
}

private enum PollSample {
    case processExited
    case ambiguous
    case unavailable
    case header([String])
}

private enum PollResult: Equatable {
    case matched(attempt: Int)
    case processExited
    case ambiguous
    case privacyLeak
    case timeout
    case wrongFinalState(String)
}

private struct DayStatePoller {
    let expectedDate: String
    let expectedState: String
    let expectedCopy: String
    let rejected: [String]
    private(set) var lastObserved: [String]?

    mutating func consume(_ sample: PollSample, attempt: Int) -> PollResult? {
        switch sample {
        case .processExited:
            return .processExited
        case .ambiguous:
            return .ambiguous
        case .unavailable:
            return nil
        case let .header(values):
            if exposesPrivateSentinel(values, rejected: rejected) {
                return .privacyLeak
            }
            if matchesDayState(
                values,
                expectedDate: expectedDate,
                expectedState: expectedState,
                expectedCopy: expectedCopy
            ) {
                return .matched(attempt: attempt)
            }
            lastObserved = values
            return nil
        }
    }

    func finish() -> PollResult {
        guard let lastObserved else { return .timeout }
        return .wrongFinalState(lastObserved.joined(separator: " | "))
    }
}

private func evaluatePoll(
    _ samples: [PollSample],
    expectedDate: String,
    expectedState: String,
    expectedCopy: String,
    rejected: [String] = []
) -> PollResult {
    var poller = DayStatePoller(
        expectedDate: expectedDate,
        expectedState: expectedState,
        expectedCopy: expectedCopy,
        rejected: rejected
    )
    for (offset, sample) in samples.enumerated() {
        if let result = poller.consume(sample, attempt: offset + 1) {
            return result
        }
    }
    return poller.finish()
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let fixtureDate = ISO8601DateFormatter().date(from: "2026-07-14T12:00:00Z")!
    let cairo = TimeZone(identifier: "Africa/Cairo")!
    let gregorian = Calendar(identifier: .gregorian)
    let currentMachineDate = formattedDayStateDate(
        fixtureDate,
        locale: .current,
        calendar: gregorian,
        timeZone: cairo
    )
    let valid = [
        "Tuesday, 14 July. Day state: ACTIVE WORK. One task is currently tracking time.",
    ]
    let stale = [
        "Tuesday, 14 July. Day state: PREPARING TODAY. Local sources are still preparing the current day.",
    ]
    guard currentMachineDate == "Tuesday, 14 July",
          formattedDayStateDate(
              fixtureDate,
              locale: Locale(identifier: "en_EG"),
              calendar: gregorian,
              timeZone: cairo
          ) == "Tuesday, 14 July",
          formattedDayStateDate(
              fixtureDate,
              locale: Locale(identifier: "en_US"),
              calendar: gregorian,
              timeZone: cairo
          ) == "Tuesday, July 14",
          formattedDayStateDate(
              fixtureDate,
              locale: Locale(identifier: "en_GB"),
              calendar: gregorian,
              timeZone: cairo
          ) == "Tuesday 14 July",
          matchesDayState(
              valid,
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ),
          !matchesDayState(
              valid,
              expectedDate: "Monday, 13 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ),
          !matchesDayState(
              valid,
              expectedDate: "Tuesday, 14 July",
              expectedState: "PLANNED DAY",
              expectedCopy: "Today's commitments are ready."
          ),
          matchesDayState(
              ["Wednesday, 15 July. Day state: PREPARING TODAY. Local sources are still preparing the current day."],
              expectedDate: "Wednesday, 15 July",
              expectedState: "PREPARING TODAY",
              expectedCopy: "Local sources are still preparing the current day."
          ),
          !exposesPrivateSentinel(valid, rejected: ["qa-zc013001-private", "private.invalid"]),
          exposesPrivateSentinel(
              valid + ["qa-zc013001-private-window-title"],
              rejected: ["qa-zc013001-private"]
          ),
          evaluatePoll(
              [.unavailable, .header(stale), .header(valid)],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ) == .matched(attempt: 3),
          evaluatePoll(
              [.unavailable, .unavailable, .unavailable],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ) == .timeout,
          evaluatePoll(
              [.header(stale), .header(stale)],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ) == .wrongFinalState(stale[0]),
          evaluatePoll(
              [.unavailable, .ambiguous, .header(valid)],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ) == .ambiguous,
          evaluatePoll(
              [.unavailable, .processExited, .header(valid)],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time."
          ) == .processExited,
          evaluatePoll(
              [.header(valid + ["qa-zc013001-private-window-title"])],
              expectedDate: "Tuesday, 14 July",
              expectedState: "ACTIVE WORK",
              expectedCopy: "One task is currently tracking time.",
              rejected: ["qa-zc013001-private"]
          ) == .privacyLeak
    else {
        fputs("FAIL: ZC-013-001 day-state AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-013-001 day-state AX probe self-test")
    exit(0)
}

var pid: Int32?
var appBundlePath: String?
var expectedState: String?
var expectedCopy: String?
var rejected: [String] = []
var index = 1
while index < CommandLine.arguments.count {
    guard index + 1 < CommandLine.arguments.count else {
        fputs("FAIL: verifier option requires a value\n", stderr)
        exit(2)
    }
    switch CommandLine.arguments[index] {
    case "--pid": pid = Int32(CommandLine.arguments[index + 1])
    case "--app-bundle": appBundlePath = CommandLine.arguments[index + 1]
    case "--expected-state": expectedState = CommandLine.arguments[index + 1]
    case "--expected-copy": expectedCopy = CommandLine.arguments[index + 1]
    case "--reject": rejected.append(CommandLine.arguments[index + 1])
    default:
        fputs("FAIL: unsupported verifier option\n", stderr)
        exit(2)
    }
    index += 2
}
guard let pid, let appBundlePath, let expectedState, let expectedCopy else {
    fputs(
        "usage: qa-zc013001-day-state-ax-probe.swift --self-test | --pid <pid> --app-bundle <path> --expected-state <state> --expected-copy <copy> [--reject <sentinel>]...\n",
        stderr
    )
    exit(2)
}

guard Bundle(path: appBundlePath) != nil else {
    fputs("FAIL: installed app bundle is unavailable\n", stderr)
    exit(1)
}
let resolvedLocale = Locale.current
let resolvedLocaleIdentifier = resolvedLocale.identifier
let expectedDate = formattedDayStateDate(
    Date(),
    locale: resolvedLocale,
    calendar: Calendar.current,
    timeZone: TimeZone.current
)

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

private func mainWindows(application: AXUIElement) -> [AXUIElement] {
    let windows = attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
    return windows.filter {
        (attribute($0, kAXMainAttribute as CFString) as? NSNumber)?.boolValue == true
    }
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
    var poller = DayStatePoller(
        expectedDate: expectedDate,
        expectedState: expectedState,
        expectedCopy: expectedCopy,
        rejected: rejected
    )
    var result: PollResult?
    for attempt in 1...40 {
        guard kill(pid, 0) == 0 else {
            result = poller.consume(.processExited, attempt: attempt)
            break
        }
        let windows = mainWindows(application: application)
        if windows.count > 1 {
            result = poller.consume(.ambiguous, attempt: attempt)
            break
        }
        guard let mainWindow = windows.first else {
            _ = poller.consume(.unavailable, attempt: attempt)
            Thread.sleep(forTimeInterval: 0.2)
            continue
        }
        let matches = try dayStateElements(root: mainWindow)
        if matches.count > 1 {
            result = poller.consume(.ambiguous, attempt: attempt)
            break
        }
        guard let dayState = matches.first else {
            _ = poller.consume(.unavailable, attempt: attempt)
            Thread.sleep(forTimeInterval: 0.2)
            continue
        }
        result = poller.consume(.header(values(dayState)), attempt: attempt)
        if result != nil { break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    switch result ?? poller.finish() {
    case .matched:
        print(
            "PASS: ZC-013-001 visible date=\(expectedDate) state=\(expectedState) locale=\(resolvedLocaleIdentifier)"
        )
    case .processExited:
        fputs("FAIL: supplied application process exited while waiting for the Today day-state header\n", stderr)
        exit(1)
    case .ambiguous:
        fputs("FAIL: expected one main window and one Today day-state header during polling\n", stderr)
        exit(1)
    case .privacyLeak:
        fputs("FAIL: private fixture evidence escaped into the Today day-state header\n", stderr)
        exit(1)
    case .timeout:
        fputs("FAIL: timed out waiting for one visible Today day-state header\n", stderr)
        exit(1)
    case let .wrongFinalState(observed):
        fputs(
            "FAIL: Today day-state header did not reach expected date=\(expectedDate) state=\(expectedState) copy=\(expectedCopy) locale=\(resolvedLocaleIdentifier); final observed=\(observed)\n",
            stderr
        )
        exit(1)
    }
} catch {
    fputs("FAIL: Today day-state accessibility traversal failed\n", stderr)
    exit(1)
}
