#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private func normalized(_ value: String) -> String {
    value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func contains(_ values: [String], _ expected: String) -> Bool {
    let expected = normalized(expected)
    return values.contains { normalized($0).contains(expected) }
}

private func provesActiveTechnicalTask(_ values: [String]) -> Bool {
    contains(values, "QA ZC-061-002 technical task")
        && contains(values, "technical task")
        && contains(values, "active commitment")
}

private func provesBrowserEvidence(
    safariUncertainty: [String],
    workTotal: [String],
    researchTotal: [String]
) -> Bool {
    contains(safariUncertainty, "Safari")
        && contains(safariUncertainty, "work category uncertain")
        && contains(workTotal, "Work")
        && !contains(workTotal, "0 minutes")
        && contains(researchTotal, "Research")
        && contains(researchTotal, "0 minutes")
}

private func leaksPrivateContext(_ values: [String]) -> Bool {
    let forbidden = [
        "youtube.com",
        "swift concurrency tutorial",
        "/users/",
        "token=",
        "localhost",
        "127.0.0.1",
    ]
    return forbidden.contains { forbiddenValue in
        values.contains { normalized($0).contains(normalized(forbiddenValue)) }
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    guard provesActiveTechnicalTask([
        "QA ZC-061-002 technical task",
        "TECHNICAL TASK · ACTIVE COMMITMENT · OPEN-ENDED",
    ]),
    !provesActiveTechnicalTask([
        "QA ZC-061-002 general boundary",
        "ACTIVE COMMITMENT · OPEN-ENDED",
    ]),
    provesBrowserEvidence(
        safariUncertainty: ["Safari, 4 minutes, work category uncertain"],
        workTotal: ["Work, 4 minutes"],
        researchTotal: ["Research, 0 minutes"]
    ),
    !provesBrowserEvidence(
        safariUncertainty: ["Safari, Research"],
        workTotal: ["Work, 4 minutes"],
        researchTotal: ["Research, 4 minutes"]
    ),
    leaksPrivateContext(["https://www.youtube.com/tutorials/swift-concurrency"]),
    leaksPrivateContext(["Swift concurrency tutorial - YouTube"]),
    !leaksPrivateContext(["Safari, 4 minutes, work category uncertain"]) else {
        fputs("FAIL: AX evidence predicates accepted an unsafe or invented classification\n", stderr)
        exit(1)
    }
    print("PASS: ZC-061-002 AX predicate self-test")
    exit(0)
}

private struct Options {
    let pid: Int32
}

private func usage() -> Never {
    fputs("usage: qa-zc061002-related-tutorial-ax-probe.swift --self-test | --pid <pid> --phase active-browser-visible\n", stderr)
    exit(2)
}

private func parseOptions() -> Options {
    guard CommandLine.arguments.count == 5,
          CommandLine.arguments[1] == "--pid",
          let pid = Int32(CommandLine.arguments[2]),
          CommandLine.arguments[3] == "--phase",
          CommandLine.arguments[4] == "active-browser-visible" else { usage() }
    return Options(pid: pid)
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func string(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func identifier(_ element: AXUIElement) -> String? {
    string(element, kAXIdentifierAttribute as CFString)
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func exposedStrings(_ element: AXUIElement) -> [String] {
    [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func flattened(_ roots: [AXUIElement], limit: Int = 5_000) -> [AXUIElement] {
    var queue = roots
    var elements: [AXUIElement] = []
    var visited = Set<CFHashCode>()
    while let element = queue.first, elements.count < limit {
        queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        elements.append(element)
        queue.append(contentsOf: children(element))
    }
    return elements
}

private func applicationWindows(_ application: AXUIElement) throws -> [AXUIElement] {
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("Accessibility permission is required")
    }
    return attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
}

private func waitForUnique(
    _ description: String,
    application: AXUIElement,
    matching: (AXUIElement) -> Bool
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(8)
    repeat {
        let matches = flattened(try applicationWindows(application)).filter(matching)
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            throw ProbeError.failure("ambiguous AX target: \(description)")
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw ProbeError.failure("required AX target is unavailable: \(description)")
}

private func uniqueStrings(
    identifier expectedIdentifier: String,
    in elements: [AXUIElement]
) throws -> [String] {
    let matches = elements.filter { identifier($0) == expectedIdentifier }
    guard matches.count == 1 else {
        throw ProbeError.failure(
            matches.isEmpty
                ? "required AX evidence is unavailable: \(expectedIdentifier)"
                : "ambiguous AX evidence: \(expectedIdentifier)"
        )
    }
    return exposedStrings(matches[0])
}

private func press(_ element: AXUIElement, description: String) throws {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("could not press \(description)")
    }
}

do {
    let options = parseOptions()
    let application = AXUIElementCreateApplication(options.pid)
    let before = flattened(try applicationWindows(application)).flatMap(exposedStrings)
    guard provesActiveTechnicalTask(before) else {
        throw ProbeError.failure("active declared-technical commitment is not visible")
    }

    let openEvidence = try waitForUnique(
        "behavior evidence action",
        application: application,
        matching: { identifier($0) == "today.behavior-evidence.open" }
    )
    try press(openEvidence, description: "behavior evidence action")
    let sheet = try waitForUnique(
        "behavior evidence sheet",
        application: application,
        matching: { identifier($0) == "today.behavior-evidence.sheet" }
    )
    let sheetElements = flattened([sheet])
    let safari = try uniqueStrings(
        identifier: "today.behavior-evidence.work-uncertainty.536166617269",
        in: sheetElements
    )
    let work = try uniqueStrings(
        identifier: "today.behavior-evidence.category.work",
        in: sheetElements
    )
    let research = try uniqueStrings(
        identifier: "today.behavior-evidence.work-category.research",
        in: sheetElements
    )
    guard provesBrowserEvidence(
        safariUncertainty: safari,
        workTotal: work,
        researchTotal: research
    ) else {
        throw ProbeError.failure("Safari work evidence or the zero-minute Research boundary is missing")
    }
    guard !leaksPrivateContext(sheetElements.flatMap(exposedStrings)) else {
        throw ProbeError.failure("raw tutorial context leaked into accessibility output")
    }
    print("PASS: active technical commitment and privacy-safe Safari evidence are visible without a Research classification")
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
