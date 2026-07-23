#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message): return message
        }
    }
}

struct Node {
    let element: AXUIElement
    let identifier: String
    let role: String
    let title: String
    let label: String
    let value: String
    let enabled: Bool?

    var searchableText: String {
        [identifier, role, title, label, value].joined(separator: " ")
    }
}

func attribute(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String {
    attribute(element, name) as? String ?? ""
}

func node(_ element: AXUIElement) -> Node {
    Node(
        element: element,
        identifier: stringAttribute(element, kAXIdentifierAttribute as CFString),
        role: stringAttribute(element, kAXRoleAttribute as CFString),
        title: stringAttribute(element, kAXTitleAttribute as CFString),
        label: stringAttribute(element, kAXDescriptionAttribute as CFString),
        value: stringAttribute(element, kAXValueAttribute as CFString),
        enabled: attribute(element, kAXEnabledAttribute as CFString) as? Bool
    )
}

func snapshot(_ application: AXUIElement, maximumNodes: Int = 8_000) throws -> [Node] {
    var queue = [application]
    var cursor = 0
    var result: [Node] = []
    while cursor < queue.count {
        guard result.count < maximumNodes else {
            throw ProbeError.failure("AX traversal exceeded \(maximumNodes) nodes")
        }
        let element = queue[cursor]
        cursor += 1
        result.append(node(element))
        if let children = attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            queue.append(contentsOf: children)
        }
    }
    return result
}

func waitForNodes(_ application: AXUIElement, timeout: TimeInterval = 8, predicate: ([Node]) -> Bool) throws -> [Node] {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let nodes = try snapshot(application)
        if predicate(nodes) { return nodes }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    } while Date() < deadline
    let nodes = try snapshot(application)
    throw ProbeError.failure("expected accessibility state did not appear; visible text: \(nodes.map(\.searchableText).joined(separator: " | ").prefix(1200))")
}

func boundedPostconditionAfterAdvisoryAction<Value>(
    _ actionResult: AXError,
    maximumAttempts: Int,
    pause: () -> Void,
    observe: () throws -> Value?
) rethrows -> Value? {
    _ = actionResult
    precondition(maximumAttempts > 0)
    for attempt in 1...maximumAttempts {
        if let value = try observe() {
            return value
        }
        if attempt < maximumAttempts {
            pause()
        }
    }
    return nil
}

func dailyReviewSurfaceIsReady(_ nodes: [Node]) -> Bool {
    nodes.contains { $0.identifier == "reviews.daily" }
        && nodes.contains { $0.searchableText.localizedCaseInsensitiveContains("DAILY REVIEW") }
}

func waitForDailyReviewAfterAdvisoryPress(
    _ actionResult: AXError,
    application: AXUIElement,
    maximumAttempts: Int = 54
) throws -> [Node] {
    let reviews = try boundedPostconditionAfterAdvisoryAction(
        actionResult,
        maximumAttempts: maximumAttempts,
        pause: { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
    ) {
        let nodes = try snapshot(application)
        return dailyReviewSurfaceIsReady(nodes) ? nodes : nil
    }
    guard let reviews else {
        throw ProbeError.failure("OPEN REVIEW did not reach the required Daily Review surface; AX result: \(actionResult.rawValue)")
    }
    return reviews
}

func runAdvisoryPressSelfTest() throws {
    var observations = [false, true]
    let recovered = boundedPostconditionAfterAdvisoryAction(.cannotComplete, maximumAttempts: 2, pause: {}) {
        observations.removeFirst() ? "reviews.daily" : nil
    }
    guard recovered == "reviews.daily" else {
        throw ProbeError.failure("advisory AX failure rejected a successful bounded postcondition")
    }
    let rejected: String? = boundedPostconditionAfterAdvisoryAction(.success, maximumAttempts: 2, pause: {}) { nil }
    guard rejected == nil else {
        throw ProbeError.failure("missing Daily Review postcondition was accepted")
    }
    print("PASS: ZC-010-007 advisory AX press self-test")
}

func requireIdentifier(_ identifier: String, in nodes: [Node]) throws -> Node {
    guard let match = nodes.first(where: { $0.identifier == identifier }) else {
        throw ProbeError.failure("missing accessibility identifier: \(identifier)")
    }
    return match
}

func requireText(_ fragment: String, in nodes: [Node]) throws {
    guard nodes.contains(where: { $0.searchableText.localizedCaseInsensitiveContains(fragment) }) else {
        throw ProbeError.failure("missing visible/accessibility text: \(fragment)")
    }
}

func requireAbsent(_ identifier: String, in nodes: [Node]) throws {
    guard !nodes.contains(where: { $0.identifier == identifier }) else {
        throw ProbeError.failure("unexpected accessibility identifier: \(identifier)")
    }
}

private let renderedReadyIdentifier = "today.snapshot.ready"
private let privacySentinels = ["qa-zc010007-private-window-title", "qa-zc010007-private.invalid"]

func renderedSnapshotIsReady(_ identifiers: [String]) -> Bool {
    identifiers.contains(renderedReadyIdentifier)
}

func privacyLeak(in searchableText: [String]) -> String? {
    let text = searchableText.joined(separator: " ")
    return privacySentinels.first { text.contains($0) }
}

func assertPrivacy(_ nodes: [Node]) throws {
    if let sentinel = privacyLeak(in: nodes.map(\.searchableText)) {
        throw ProbeError.failure("private fixture sentinel leaked through accessibility: \(sentinel)")
    }
}

func selfTest() throws {
    guard !renderedSnapshotIsReady([]) else {
        throw ProbeError.failure("absence boundary accepted before rendered snapshot readiness")
    }
    guard renderedSnapshotIsReady([renderedReadyIdentifier]) else {
        throw ProbeError.failure("rendered snapshot readiness was rejected")
    }
    guard privacyLeak(in: ["safe Today content"]) == nil else {
        throw ProbeError.failure("safe accessibility text was rejected")
    }
    for sentinel in privacySentinels {
        guard privacyLeak(in: ["prefix \(sentinel) suffix"]) == sentinel else {
            throw ProbeError.failure("privacy leak was not detected: \(sentinel)")
        }
    }
}

func press(_ node: Node) throws {
    guard node.enabled != false else { throw ProbeError.failure("control is disabled: \(node.identifier)") }
    guard AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("AX press failed: \(node.identifier.isEmpty ? node.title : node.identifier)")
    }
}

func parseArguments() throws -> (pid: pid_t, phase: String) {
    var pid: pid_t?
    var phase: String?
    var index = 1
    while index < CommandLine.arguments.count {
        switch CommandLine.arguments[index] {
        case "--pid":
            index += 1
            guard index < CommandLine.arguments.count, let parsed = Int32(CommandLine.arguments[index]) else {
                throw ProbeError.failure("--pid requires a numeric process ID")
            }
            pid = parsed
        case "--phase":
            index += 1
            guard index < CommandLine.arguments.count else { throw ProbeError.failure("--phase requires a value") }
            phase = CommandLine.arguments[index]
        default:
            throw ProbeError.failure("unsupported argument: \(CommandLine.arguments[index])")
        }
        index += 1
    }
    guard let pid, let phase else {
        throw ProbeError.failure("usage: qa-zc010007-unplanned-review-ax-probe.swift --pid PID --phase {unplanned|open-confirmation|confirm-reviews|absent|active-precedence}")
    }
    return (pid, phase)
}

do {
    if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
        try selfTest()
        try runAdvisoryPressSelfTest()
        print("PASS: ZC-010-007 AX probe self-test")
        exit(0)
    }
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    let arguments = try parseArguments()
    guard NSRunningApplication(processIdentifier: arguments.pid) != nil else {
        throw ProbeError.failure("the supplied process is not running")
    }
    let application = AXUIElementCreateApplication(arguments.pid)
    switch arguments.phase {
    case "unplanned":
        let nodes = try waitForNodes(application) { nodes in
            nodes.contains { $0.identifier == "today.unplanned-day-review" }
        }
        let command = try requireIdentifier("today.end-workday", in: nodes)
        guard command.enabled == true else { throw ProbeError.failure("unplanned review command is not enabled") }
        try requireText("End and review this unplanned day", in: nodes)
        try requireText("observed behavior", in: nodes)
        try requireText("tracked task outcomes", in: nodes)
        try requireText("without inventing planned commitments", in: nodes)
        try assertPrivacy(nodes)
    case "open-confirmation":
        let initial = try waitForNodes(application) { nodes in
            nodes.contains { $0.identifier == "today.unplanned-day-review" }
        }
        try press(requireIdentifier("today.end-workday", in: initial))
        let confirmation = try waitForNodes(application) { nodes in
            nodes.contains { $0.searchableText.localizedCaseInsensitiveContains("OPEN REVIEW") }
        }
        try requireText("Open today's factual review?", in: confirmation)
        try requireText("observed behavior", in: confirmation)
        try requireText("without inventing planned commitments", in: confirmation)
        try assertPrivacy(confirmation)
    case "confirm-reviews":
        let confirmation = try waitForNodes(application) { nodes in
            nodes.contains { $0.searchableText.localizedCaseInsensitiveContains("OPEN REVIEW") }
        }
        guard let button = confirmation.first(where: {
            $0.role == kAXButtonRole as String && $0.searchableText.localizedCaseInsensitiveContains("OPEN REVIEW")
        }) else { throw ProbeError.failure("enabled OPEN REVIEW confirmation button is unavailable") }
        guard button.enabled != false else { throw ProbeError.failure("OPEN REVIEW confirmation button is disabled") }
        let actionResult = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        let reviews = try waitForDailyReviewAfterAdvisoryPress(actionResult, application: application)
        _ = try requireIdentifier("reviews.daily", in: reviews)
        try requireText("DAILY REVIEW", in: reviews)
        try assertPrivacy(reviews)
    case "absent":
        let nodes = try waitForNodes(application) { nodes in
            renderedSnapshotIsReady(nodes.map(\.identifier))
        }
        try requireAbsent("today.unplanned-day-review", in: nodes)
        try requireAbsent("today.end-workday", in: nodes)
        try assertPrivacy(nodes)
    case "active-precedence":
        let nodes = try waitForNodes(application) { nodes in
            nodes.contains { $0.identifier == "today.end-workday" }
        }
        try requireAbsent("today.unplanned-day-review", in: nodes)
        let command = try requireIdentifier("today.end-workday", in: nodes)
        guard command.enabled == true else { throw ProbeError.failure("existing active end-workday command is disabled") }
        try assertPrivacy(nodes)
    default:
        throw ProbeError.failure("unsupported phase: \(arguments.phase)")
    }
    print("PASS: ZC-010-007 accessibility phase \(arguments.phase)")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
