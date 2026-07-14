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
          matchesDayState(valid, expectedDate: "Tuesday, 14 July", expectedState: "Active work"),
          !matchesDayState(valid, expectedDate: "Monday, 13 July", expectedState: "Active work"),
          !matchesDayState(valid, expectedDate: "Tuesday, 14 July", expectedState: "Planned day"),
          matchesDayState(
              ["Wednesday, 15 July", "Day state", "Preparing today"],
              expectedDate: "Wednesday, 15 July",
              expectedState: "Preparing today"
          ),
          !exposesPrivateSentinel(valid, rejected: ["qa-zc013001-private", "private.invalid"]),
          exposesPrivateSentinel(
              valid + ["qa-zc013001-private-window-title"],
              rejected: ["qa-zc013001-private"]
          )
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
    case "--reject": rejected.append(CommandLine.arguments[index + 1])
    default:
        fputs("FAIL: unsupported verifier option\n", stderr)
        exit(2)
    }
    index += 2
}
guard let pid, let appBundlePath, let expectedState else {
    fputs(
        "usage: qa-zc013001-day-state-ax-probe.swift --self-test | --pid <pid> --app-bundle <path> --expected-state <state> [--reject <sentinel>]...\n",
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
        let observed = values(dayState).joined(separator: " | ")
        fputs(
            "FAIL: Today day-state header mismatch; expected date=\(expectedDate) state=\(expectedState) locale=\(resolvedLocaleIdentifier); observed=\(observed)\n",
            stderr
        )
        exit(1)
    }
    guard !exposesPrivateSentinel(values(dayState), rejected: rejected) else {
        fputs("FAIL: private fixture evidence escaped into the Today day-state header\n", stderr)
        exit(1)
    }
    print(
        "PASS: ZC-013-001 visible date=\(expectedDate) state=\(expectedState) locale=\(resolvedLocaleIdentifier)"
    )
} catch {
    fputs("FAIL: Today day-state accessibility traversal failed\n", stderr)
    exit(1)
}
