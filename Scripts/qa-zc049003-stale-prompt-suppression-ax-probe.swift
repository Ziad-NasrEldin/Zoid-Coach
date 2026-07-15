#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

private let initialPromptID = "qa-zc049003-initial"
private let privateValues = [
    "ZC049003_PRIVATE_APP",
    "ZC049003_PRIVATE_WINDOW",
    "https://private.invalid/zc049003",
]

private enum Phase: String {
    case initial
    case stale
    case fresh
    case preserved
}

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

private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return "" }
    return value as? String ?? ""
}

@discardableResult
private func collect(_ element: AXUIElement, nodes: inout [Node], remaining: inout Int) -> String {
    guard remaining > 0 else { return "" }
    remaining -= 1
    var pieces = [
        stringAttribute(element, kAXTitleAttribute as CFString),
        stringAttribute(element, kAXValueAttribute as CFString),
        stringAttribute(element, kAXDescriptionAttribute as CFString),
        stringAttribute(element, kAXHelpAttribute as CFString),
    ].filter { !$0.isEmpty }

    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
       let children = value as? [AXUIElement] {
        for child in children {
            let text = collect(child, nodes: &nodes, remaining: &remaining)
            if !text.isEmpty { pieces.append(text) }
        }
    }
    let text = pieces.joined(separator: " ")
    nodes.append(Node(
        identifier: stringAttribute(element, kAXIdentifierAttribute as CFString),
        text: text
    ))
    return text
}

private func snapshot(pid: pid_t) -> [Node] {
    var nodes: [Node] = []
    var remaining = 4_000
    collect(AXUIElementCreateApplication(pid), nodes: &nodes, remaining: &remaining)
    return nodes
}

private func waitingIdentifier(_ promptID: String) -> String {
    "today.prompt.\(promptID).waiting"
}

private func historyIdentifier(_ promptID: String) -> String {
    "today.prompt.\(promptID).history"
}

private func requireNode(_ identifier: String, nodes: [Node], label: String) throws -> Node {
    guard let node = nodes.first(where: { $0.identifier == identifier }) else {
        throw ProbeError.failure("\(label) is absent")
    }
    return node
}

private func rejectPrivateText(_ nodes: [Node]) throws {
    let text = nodes.map(\.text).joined(separator: " ")
    for value in privateValues where text.contains(value) {
        throw ProbeError.failure("private fixture value is visible: \(value)")
    }
}

private func validate(nodes: [Node], phase: Phase, promptID: String?) throws {
    try rejectPrivateText(nodes)
    switch phase {
    case .initial:
        let row = try requireNode(
            waitingIdentifier(initialPromptID),
            nodes: nodes,
            label: "initial visible prompt"
        )
        guard row.text.contains("Is this gaming intentional?") else {
            throw ProbeError.failure("initial prompt title is absent")
        }
        guard row.text.contains("Gaming was observed while a priority task remains unfinished.") else {
            throw ProbeError.failure("initial prompt explanation is absent")
        }
    case .stale:
        guard !nodes.contains(where: { $0.identifier == waitingIdentifier(initialPromptID) }) else {
            throw ProbeError.failure("stale prompt remains visibly actionable")
        }
        _ = try requireNode(
            historyIdentifier(initialPromptID),
            nodes: nodes,
            label: "withdrawn prompt history"
        )
    case .fresh:
        guard let promptID, !promptID.isEmpty, promptID != initialPromptID else {
            throw ProbeError.failure("fresh prompt identifier is invalid")
        }
        guard !nodes.contains(where: { $0.identifier == waitingIdentifier(initialPromptID) }) else {
            throw ProbeError.failure("withdrawn prompt returned instead of a fresh episode")
        }
        _ = try requireNode(
            waitingIdentifier(promptID),
            nodes: nodes,
            label: "fresh same-session recovery prompt"
        )
    case .preserved:
        guard let promptID, !promptID.isEmpty else {
            throw ProbeError.failure("dismissed prompt identifier is invalid")
        }
        guard !nodes.contains(where: { $0.identifier == waitingIdentifier(promptID) }) else {
            throw ProbeError.failure("user-dismissed prompt became actionable again")
        }
        _ = try requireNode(
            historyIdentifier(promptID),
            nodes: nodes,
            label: "user-dismissed prompt history"
        )
    }
}

private func expectFailure(
    containing expected: String,
    nodes: [Node],
    phase: Phase,
    promptID: String? = nil
) throws {
    do {
        try validate(nodes: nodes, phase: phase, promptID: promptID)
    } catch let error as ProbeError {
        guard error.description.contains(expected) else {
            throw ProbeError.failure("negative self-test failed for the wrong reason: \(error)")
        }
        return
    }
    throw ProbeError.failure("negative self-test false-passed: \(expected)")
}

private func selfTest() throws {
    let initial = Node(
        identifier: waitingIdentifier(initialPromptID),
        text: "Is this gaming intentional? Gaming was observed while a priority task remains unfinished."
    )
    let initialHistory = Node(identifier: historyIdentifier(initialPromptID), text: "DISMISSED")
    let freshID = "qa-zc049003-fresh"
    let fresh = Node(identifier: waitingIdentifier(freshID), text: "Is this gaming intentional?")
    let freshHistory = Node(identifier: historyIdentifier(freshID), text: "DISMISSED")

    try validate(nodes: [initial], phase: .initial, promptID: nil)
    try expectFailure(containing: "initial visible prompt is absent", nodes: [], phase: .initial)
    try expectFailure(
        containing: "private fixture value is visible",
        nodes: [initial, Node(identifier: "private", text: privateValues[0])],
        phase: .initial
    )
    try validate(nodes: [initialHistory], phase: .stale, promptID: nil)
    try expectFailure(containing: "stale prompt remains visibly actionable", nodes: [initial, initialHistory], phase: .stale)
    try validate(nodes: [initialHistory, fresh], phase: .fresh, promptID: freshID)
    try expectFailure(containing: "fresh same-session recovery prompt is absent", nodes: [initialHistory], phase: .fresh, promptID: freshID)
    try validate(nodes: [initialHistory, freshHistory], phase: .preserved, promptID: freshID)
    try expectFailure(containing: "user-dismissed prompt became actionable again", nodes: [fresh, freshHistory], phase: .preserved, promptID: freshID)
    print("PASS: ZC-049-003 AX probe self-test")
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
        return
    }
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("Accessibility permission is required")
    }

    var pid: pid_t?
    var phase: Phase?
    var promptID: String?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--pid" where index + 1 < arguments.count:
            pid = pid_t(arguments[index + 1])
            index += 2
        case "--phase" where index + 1 < arguments.count:
            phase = Phase(rawValue: arguments[index + 1])
            index += 2
        case "--prompt-id" where index + 1 < arguments.count:
            promptID = arguments[index + 1]
            index += 2
        default:
            throw ProbeError.failure("usage: --self-test | --pid PID --phase initial|stale|fresh|preserved [--prompt-id ID]")
        }
    }
    guard let pid, pid > 0, let phase else {
        throw ProbeError.failure("--pid and --phase are required")
    }
    guard kill(pid, 0) == 0 else {
        throw ProbeError.failure("the supplied process is not running")
    }

    let deadline = Date().addingTimeInterval(10)
    var lastError: Error = ProbeError.failure("AX contract was not observed")
    repeat {
        do {
            try validate(nodes: snapshot(pid: pid), phase: phase, promptID: promptID)
            print("PASS: ZC-049-003 \(phase.rawValue) AX contract")
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
