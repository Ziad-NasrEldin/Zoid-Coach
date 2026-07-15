#!/usr/bin/env swift
import ApplicationServices
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { if case let .failure(message) = self { message } else { "probe failure" } }
}

struct PhaseContract {
    let required: [String]
    let forbidden: [String]

    static func named(_ phase: String) throws -> Self {
        let observationBoundary = "Task tracking and activity observation continue"
        switch phase {
        case "observation":
            return Self(required: ["OBSERVATION ONLY", "without behavior coaching prompts", observationBoundary], forbidden: ["Resume coaching in Settings", "COACHING ACTIVE", "private fixture"])
        case "gentle":
            return Self(required: ["COACHING ACTIVE - GENTLE", "gentle prompts", observationBoundary], forbidden: ["Resume coaching in Settings", "COACHING PAUSED", "private fixture"])
        case "accountability":
            return Self(required: ["COACHING ACTIVE - ACCOUNTABILITY", "more frequent prompts", observationBoundary], forbidden: ["Resume coaching in Settings", "COACHING PAUSED", "private fixture"])
        case "paused-indefinite":
            return Self(required: ["COACHING PAUSED", "Paused until you resume coaching", observationBoundary, "Resume coaching in Settings"], forbidden: ["COACHING ACTIVE", "observation stopped", "private fixture"])
        case "paused-timed":
            return Self(required: ["COACHING PAUSED", "Paused until", observationBoundary, "Resume coaching in Settings"], forbidden: ["COACHING ACTIVE", "observation stopped", "private fixture"])
        case "unavailable":
            return Self(required: ["COACHING STATUS UNAVAILABLE", "could not be verified", "activity observation"], forbidden: ["Resume coaching in Settings", "COACHING ACTIVE", "private fixture"])
        default:
            throw ProbeError.failure("unknown phase: \(phase)")
        }
    }

    func validate(_ text: String) throws {
        for value in required where !text.localizedCaseInsensitiveContains(value) {
            throw ProbeError.failure("missing required accessible copy: \(value)")
        }
        for value in forbidden where text.localizedCaseInsensitiveContains(value) {
            throw ProbeError.failure("forbidden or private copy is accessible: \(value)")
        }
    }
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func findCard(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 40 else { return nil }
    if stringAttribute(element, "AXIdentifier" as CFString) == "today.coaching.status" { return element }
    for child in children(element) {
        if let match = findCard(child, depth: depth + 1) { return match }
    }
    return nil
}

func accessibleText(_ element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { stringAttribute(element, $0 as CFString) }
        .joined(separator: " ")
}

func selfTest() throws {
    for phase in ["observation", "gentle", "accountability", "paused-indefinite", "paused-timed", "unavailable"] {
        let contract = try PhaseContract.named(phase)
        try contract.validate(contract.required.joined(separator: " | "))
        do {
            try contract.validate((contract.required + contract.forbidden.prefix(1)).joined(separator: " | "))
            throw ProbeError.failure("negative privacy contract was accepted for \(phase)")
        } catch let error as ProbeError where error.description.contains("forbidden") {
        }
    }
    print("PASS: ZC-013-002 AX state, copy, recovery, contradiction, and privacy self-test")
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments == ["--self-test"] {
        try selfTest()
        exit(0)
    }
    guard let pidIndex = arguments.firstIndex(of: "--pid"), pidIndex + 1 < arguments.count,
          let pid = pid_t(arguments[pidIndex + 1]),
          let phaseIndex = arguments.firstIndex(of: "--phase"), phaseIndex + 1 < arguments.count else {
        throw ProbeError.failure("usage: --pid PID --phase PHASE")
    }
    let contract = try PhaseContract.named(arguments[phaseIndex + 1])
    let application = AXUIElementCreateApplication(pid)
    guard let card = findCard(application) else { throw ProbeError.failure("Today coaching status card is unavailable") }
    let text = accessibleText(card)
    try contract.validate(text)
    print("PASS: ZC-013-002 accessible Today coaching card matches \(arguments[phaseIndex + 1])")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
