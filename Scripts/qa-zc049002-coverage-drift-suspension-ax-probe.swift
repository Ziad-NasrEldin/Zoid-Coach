#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

private let coverageIdentifier = "today.behavior-evidence.coverage"
private let suspensionSentence = "Drift detection is suspended until Screenwatch coverage is current."

private enum ProbeError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case let .failure(message): message
        }
    }
}

private struct Node {
    let identifier: String
    let text: String
}

private enum Phase: String {
    case limited
    case current
}

private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
    return value as? String ?? ""
}

private func collectNodes(_ element: AXUIElement, into nodes: inout [Node], remaining: inout Int) {
    guard remaining > 0 else { return }
    remaining -= 1
    let identifier = stringAttribute(element, kAXIdentifierAttribute as CFString)
    let pieces = [
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXHelpAttribute as CFString),
    ].filter { !$0.isEmpty }
    nodes.append(Node(identifier: identifier, text: pieces.joined(separator: " ")))

    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement] else { return }
    for child in children {
        collectNodes(child, into: &nodes, remaining: &remaining)
    }
}

private func validate(nodes: [Node], phase: Phase, forbidden: [String]) throws {
    guard let coverage = nodes.first(where: { $0.identifier == coverageIdentifier }) else {
        throw ProbeError.failure("coverage card is unavailable; open Behavior Evidence first")
    }
    let allText = nodes.map(\.text).joined(separator: " ")
    switch phase {
    case .limited:
        guard coverage.text.contains("LIMITED COVERAGE") else {
            throw ProbeError.failure("limited coverage heading is missing")
        }
        guard coverage.text.contains(suspensionSentence) else {
            throw ProbeError.failure("drift-detection suspension explanation is missing")
        }
        guard coverage.text.localizedCaseInsensitiveContains("Screenwatch") else {
            throw ProbeError.failure("limited coverage does not name Screenwatch")
        }
    case .current:
        guard coverage.text.contains("CURRENT COVERAGE") else {
            throw ProbeError.failure("current coverage heading is missing")
        }
        guard !coverage.text.contains(suspensionSentence) else {
            throw ProbeError.failure("current coverage falsely claims drift detection is suspended")
        }
    }
    for value in forbidden where !value.isEmpty {
        guard !allText.contains(value) else {
            throw ProbeError.failure("private fixture value is visible: \(value)")
        }
    }
}

private func snapshot(pid: pid_t) -> [Node] {
    var nodes: [Node] = []
    var remaining = 4_000
    collectNodes(AXUIElementCreateApplication(pid), into: &nodes, remaining: &remaining)
    return nodes
}

private func runSelfTest() throws {
    let limited = Node(
        identifier: coverageIdentifier,
        text: "LIMITED COVERAGE \(suspensionSentence) Screenwatch checkpoint is stale."
    )
    let current = Node(identifier: coverageIdentifier, text: "CURRENT COVERAGE Screenwatch coverage is current.")
    try validate(nodes: [limited], phase: .limited, forbidden: [])
    try validate(nodes: [current], phase: .current, forbidden: [])

    for (nodes, phase, expectedFailure) in [
        ([Node(identifier: coverageIdentifier, text: "LIMITED COVERAGE Screenwatch is stale.")], Phase.limited, "missing suspension"),
        ([Node(identifier: coverageIdentifier, text: "CURRENT COVERAGE \(suspensionSentence)")], Phase.current, "false suspension"),
        ([limited, Node(identifier: "private", text: "qa-private-value")], Phase.limited, "visible private value"),
    ] {
        var failedAsExpected = false
        do {
            try validate(nodes: nodes, phase: phase, forbidden: expectedFailure == "visible private value" ? ["qa-private-value"] : [])
        } catch is ProbeError {
            failedAsExpected = true
        }
        if !failedAsExpected {
            throw ProbeError.failure("self-test accepted \(expectedFailure)")
        }
    }
    print("PASS: ZC-049-002 AX probe self-test")
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try runSelfTest()
        return
    }
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }

    var pid: pid_t?
    var phase: Phase?
    var forbidden: [String] = []
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--pid" where index + 1 < arguments.count:
            pid = pid_t(arguments[index + 1])
            index += 2
        case "--phase" where index + 1 < arguments.count:
            phase = Phase(rawValue: arguments[index + 1])
            index += 2
        case "--forbid" where index + 1 < arguments.count:
            forbidden.append(arguments[index + 1])
            index += 2
        default:
            throw ProbeError.failure("usage: --self-test | --pid PID --phase limited|current [--forbid VALUE]")
        }
    }
    guard let pid, pid > 0, let phase else {
        throw ProbeError.failure("--pid and --phase are required")
    }
    guard kill(pid, 0) == 0 else { throw ProbeError.failure("the supplied process is not running") }

    let deadline = Date().addingTimeInterval(8)
    var lastError: Error = ProbeError.failure("coverage card is unavailable")
    repeat {
        do {
            try validate(nodes: snapshot(pid: pid), phase: phase, forbidden: forbidden)
            print("PASS: ZC-049-002 \(phase.rawValue) coverage AX contract")
            return
        } catch {
            lastError = error
            usleep(200_000)
        }
    } while Date() < deadline
    throw lastError
}

do {
    try run()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
