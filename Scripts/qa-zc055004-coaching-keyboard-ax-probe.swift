#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

private let primaryID = "qa-zc055004-primary"
private let secondaryID = "qa-zc055004-secondary"
private let privateValue = "ZC055004_PRIVATE_PROMPT_PAYLOAD"

private enum Phase: String { case ready, blockedSheet = "blocked-sheet", dismissed }
private enum ProbeError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { if case let .failure(message) = self { message } else { "failure" } }
}
private struct Node { let identifier: String; let text: String }

private func attribute(_ element: AXUIElement, _ name: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return "" }
    return value as? String ?? ""
}

@discardableResult
private func collect(_ element: AXUIElement, nodes: inout [Node], remaining: inout Int) -> String {
    guard remaining > 0 else { return "" }
    remaining -= 1
    var pieces = [
        attribute(element, kAXTitleAttribute as CFString),
        attribute(element, kAXValueAttribute as CFString),
        attribute(element, kAXDescriptionAttribute as CFString),
        attribute(element, kAXHelpAttribute as CFString),
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
    nodes.append(Node(identifier: attribute(element, kAXIdentifierAttribute as CFString), text: text))
    return text
}

private func snapshot(pid: pid_t) -> [Node] {
    var nodes: [Node] = []
    var remaining = 4_000
    collect(AXUIElementCreateApplication(pid), nodes: &nodes, remaining: &remaining)
    return nodes
}

private func requireNode(_ id: String, _ nodes: [Node], _ label: String) throws -> Node {
    guard let node = nodes.first(where: { $0.identifier == id }) else {
        throw ProbeError.failure("\(label) is absent")
    }
    return node
}

private func validate(_ nodes: [Node], phase: Phase) throws {
    let allText = nodes.map(\.text).joined(separator: " ")
    guard !allText.contains(privateValue) else {
        throw ProbeError.failure("private prompt payload is visible")
    }
    switch phase {
    case .ready:
        let primary = try requireNode("today.prompt.\(primaryID).waiting", nodes, "primary coaching prompt")
        for label in ["⌥⌘R", "⌥⌘K", "⌥⌘D"] where !primary.text.contains(label) {
            throw ProbeError.failure("primary shortcut label \(label) is absent")
        }
        let secondary = try requireNode("today.prompt.\(secondaryID).waiting", nodes, "secondary coaching prompt")
        guard !secondary.text.contains("⌥⌘R"), !secondary.text.contains("⌥⌘D") else {
            throw ProbeError.failure("secondary prompt owns duplicate global shortcuts")
        }
    case .blockedSheet:
        _ = try requireNode("today.prompt.block.sheet", nodes, "keyboard-opened blocked reason sheet")
        guard nodes.contains(where: { $0.identifier == "today.prompt.block.reason" }) else {
            throw ProbeError.failure("blocked reason input is absent")
        }
    case .dismissed:
        _ = try requireNode("today.prompt.\(primaryID).history", nodes, "primary dismissed history")
        guard !nodes.contains(where: { $0.identifier == "today.prompt.\(primaryID).waiting" }) else {
            throw ProbeError.failure("dismissed primary prompt remains actionable")
        }
        _ = try requireNode("today.prompt.\(secondaryID).waiting", nodes, "untouched secondary prompt")
    }
}

private func expectFailure(_ message: String, nodes: [Node], phase: Phase) throws {
    do { try validate(nodes, phase: phase) }
    catch let error as ProbeError {
        guard error.description.contains(message) else {
            throw ProbeError.failure("negative self-test failed for the wrong reason: \(error)")
        }
        return
    }
    throw ProbeError.failure("negative self-test false-passed: \(message)")
}

private func selfTest() throws {
    let primary = Node(identifier: "today.prompt.\(primaryID).waiting", text: "⌥⌘R ⌥⌘K ⌥⌘D")
    let secondary = Node(identifier: "today.prompt.\(secondaryID).waiting", text: "Second coaching decision")
    let history = Node(identifier: "today.prompt.\(primaryID).history", text: "DISMISSED")
    try validate([primary, secondary], phase: .ready)
    try expectFailure("primary coaching prompt is absent", nodes: [secondary], phase: .ready)
    try expectFailure("secondary prompt owns duplicate", nodes: [primary, Node(identifier: secondary.identifier, text: "⌥⌘R")], phase: .ready)
    try expectFailure("private prompt payload is visible", nodes: [primary, secondary, Node(identifier: "private", text: privateValue)], phase: .ready)
    try validate([Node(identifier: "today.prompt.block.sheet", text: "Mark blocked"), Node(identifier: "today.prompt.block.reason", text: "")], phase: .blockedSheet)
    try expectFailure("keyboard-opened blocked reason sheet is absent", nodes: [], phase: .blockedSheet)
    try validate([history, secondary], phase: .dismissed)
    try expectFailure("dismissed primary prompt remains actionable", nodes: [history, primary, secondary], phase: .dismissed)
    print("PASS: ZC-055-004 AX probe self-test")
}

private func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--self-test"] { try selfTest(); return }
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    var pid: pid_t?
    var phase: Phase?
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--pid" where index + 1 < args.count: pid = pid_t(args[index + 1]); index += 2
        case "--phase" where index + 1 < args.count: phase = Phase(rawValue: args[index + 1]); index += 2
        default: throw ProbeError.failure("usage: --self-test | --pid PID --phase ready|blocked-sheet|dismissed")
        }
    }
    guard let pid, pid > 0, let phase, kill(pid, 0) == 0 else {
        throw ProbeError.failure("a running --pid and valid --phase are required")
    }
    let deadline = Date().addingTimeInterval(10)
    var last: Error = ProbeError.failure("AX state was not observed")
    repeat {
        do { try validate(snapshot(pid: pid), phase: phase); print("PASS: ZC-055-004 \(phase.rawValue) AX contract"); return }
        catch { last = error; usleep(200_000) }
    } while Date() < deadline
    throw last
}

do { try run() }
catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
