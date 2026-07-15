#!/usr/bin/env swift

import ApplicationServices
import CoreGraphics
import Foundation

private enum ProbeError: Error {
    case failure(String)
}

private enum Phase: String, CaseIterable {
    case before
    case applyCombined = "apply-combined"
    case persistedCombined = "persisted-combined"
    case applyRemove = "apply-remove"
    case applyAttach = "apply-attach"
    case applyUnchangedAlignment = "apply-unchanged-alignment"
    case persistedFinal = "persisted-final"
}

private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let hidden: Bool
    let hasToday: Bool
    let hasReviews: Bool
}

private enum WindowSelection: Equatable {
    case selected(Int)
    case missing
    case ambiguous
}

private let mainWindowID = "zoid-666.main-window"
private let reviewRootID = "reviews.daily"
private let impactID = "reviews.correction-impact"
private let privateApp = "qa-zc026006-private-app"
private let privateTask = "qa-zc026006-private-task"
private let forbiddenRawEvidence = ["qa-zc026006-private-window-title", "qa-zc026006-private-url"]
private let forbiddenImpactContent = [
    privateApp,
    privateTask,
    "Observed gaming and distracting time exceeded observed work time",
    "Observed work time was the largest covered category",
]
private let maximumNodes = 5_000
private let maximumScrollPages = 24

private func selectMainWindow(_ windows: [WindowTraits]) -> WindowSelection {
    let matches = windows.indices.filter {
        let window = windows[$0]
        return !window.minimized && !window.hidden
            && (window.identifier == mainWindowID || (window.hasToday && window.hasReviews))
    }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
}

private func expectedImpact(for phase: Phase) -> String? {
    switch phase {
    case .applyCombined:
        return "Review updated. Moved 25 min from Gaming to Work. Task alignment attached for 25 min. The review statement changed after recalculation."
    case .applyRemove:
        return "Review updated. Task alignment removed from 25 min. The review statement did not change."
    case .applyAttach:
        return "Review updated. Task alignment attached for 25 min. The review statement did not change."
    case .applyUnchangedAlignment:
        return "Review updated. Moved 25 min from Work to Gaming. Task alignment unchanged at 25 min. The review statement changed after recalculation."
    case .before, .persistedCombined, .persistedFinal:
        return nil
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let main = WindowTraits(identifier: mainWindowID, minimized: false, hidden: false, hasToday: true, hasReviews: true)
    let fallback = WindowTraits(identifier: nil, minimized: false, hidden: false, hasToday: true, hasReviews: true)
    let auxiliary = WindowTraits(identifier: "agent", minimized: false, hidden: false, hasToday: false, hasReviews: false)
    let hidden = WindowTraits(identifier: mainWindowID, minimized: false, hidden: true, hasToday: true, hasReviews: true)
    guard selectMainWindow([main, auxiliary]) == .selected(0),
          selectMainWindow([auxiliary, fallback]) == .selected(1),
          selectMainWindow([main, fallback]) == .ambiguous,
          selectMainWindow([auxiliary]) == .missing,
          selectMainWindow([hidden]) == .missing,
          expectedImpact(for: .applyCombined)?.contains("Moved 25 min from Gaming to Work") == true,
          expectedImpact(for: .applyRemove)?.contains("removed from 25 min") == true,
          expectedImpact(for: .applyAttach)?.contains("attached for 25 min") == true,
          expectedImpact(for: .applyUnchangedAlignment)?.contains("unchanged at 25 min") == true,
          expectedImpact(for: .persistedCombined) == nil,
          expectedImpact(for: .persistedFinal) == nil,
          Set(forbiddenImpactContent).count == forbiddenImpactContent.count
    else {
        fputs("FAIL: ZC-026-006 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-026-006 AX probe self-test")
    exit(0)
}

private func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
}

guard let pidText = argument("--pid"),
      let pid = Int32(pidText),
      let sourceDay = argument("--day"),
      let baseEpoch = argument("--base-epoch"),
      Int64(baseEpoch) != nil,
      let phaseText = argument("--phase"),
      let phase = Phase(rawValue: phaseText)
else {
    fputs("usage: qa-zc026006-correction-impact-ax-probe.swift --self-test | --pid <pid> --day <yyyy-mm-dd> --base-epoch <epoch> --phase <before|apply-combined|persisted-combined|apply-remove|apply-attach|apply-unchanged-alignment|persisted-final>\n", stderr)
    exit(2)
}

private let application = AXUIElementCreateApplication(pid)
private let sessionPrefix = "reviews.session.\(sourceDay):\(baseEpoch)"
private let classificationID = "\(sessionPrefix).classification"
private let taskID = "\(sessionPrefix).task"
private let applyID = "\(sessionPrefix).apply"

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

private func role(_ element: AXUIElement) -> String? {
    string(element, kAXRoleAttribute as CFString)
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}

private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}

private func number(_ element: AXUIElement, _ name: CFString) -> Double? {
    (attribute(element, name) as? NSNumber)?.doubleValue
}

private func element(_ element: AXUIElement, _ name: CFString) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func exposedStrings(_ element: AXUIElement) -> [String] {
    [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}

private func walk(
    _ roots: [AXUIElement],
    matching predicate: (AXUIElement) -> Bool
) throws -> [AXUIElement] {
    var queue = roots
    var visited = Set<CFHashCode>()
    var matches: [AXUIElement] = []
    var count = 0
    while !queue.isEmpty {
        let candidate = queue.removeFirst()
        guard visited.insert(CFHash(candidate)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { throw ProbeError.failure("AX traversal exceeded \(maximumNodes) nodes") }
        if predicate(candidate) { matches.append(candidate) }
        queue.append(contentsOf: children(candidate))
    }
    return matches
}

private func single(
    _ roots: [AXUIElement],
    name: String,
    matching predicate: (AXUIElement) -> Bool
) throws -> AXUIElement {
    let matches = try walk(roots, matching: predicate)
    guard matches.count == 1, let match = matches.first else {
        throw ProbeError.failure(matches.isEmpty ? "missing \(name)" : "ambiguous \(name)")
    }
    return match
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw ProbeError.failure("supplied app PID is not running") }
    let windows = ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter { role($0) == (kAXWindowRole as String) }
    let traits = try windows.map { window in
        let buttonLabels = try walk([window], matching: { role($0) == (kAXButtonRole as String) })
            .flatMap(labels)
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            hidden: bool(window, "AXVisible" as CFString) == false,
            hasToday: buttonLabels.contains("Today"),
            hasReviews: buttonLabels.contains("Reviews")
        )
    }
    switch selectMainWindow(traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main Today/Reviews window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Reviews windows are ambiguous")
    }
}

private func press(_ target: AXUIElement, name: String) throws {
    _ = AXUIElementPerformAction(target, "AXScrollToVisible" as CFString)
    guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("could not press \(name)")
    }
    Thread.sleep(forTimeInterval: 0.3)
}

private func openReviews(_ window: AXUIElement) throws {
    if try walk([window], matching: { identifier($0) == reviewRootID }).count == 1 { return }
    let reviews = try single([window], name: "Reviews navigation") {
        role($0) == (kAXButtonRole as String) && labels($0).contains("Reviews")
    }
    try press(reviews, name: "Reviews navigation")
    for _ in 0..<40 {
        if try walk([window], matching: { identifier($0) == reviewRootID }).count == 1 { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
    throw ProbeError.failure("Reviews destination did not become visible")
}

private func reviewsScrollArea(_ window: AXUIElement) throws -> AXUIElement {
    let scrollAreas = try walk([window], matching: { role($0) == (kAXScrollAreaRole as String) })
    let matches = try scrollAreas.filter {
        try walk([$0], matching: { identifier($0) == reviewRootID }).count == 1
    }
    guard matches.count == 1, let match = matches.first else {
        throw ProbeError.failure(matches.isEmpty ? "Reviews scroll area is unavailable" : "Reviews scroll area is ambiguous")
    }
    return match
}

private func setScrollFraction(_ scrollArea: AXUIElement, _ fraction: Double) -> Bool {
    guard let bar = element(scrollArea, kAXVerticalScrollBarAttribute as CFString) else {
        return AXUIElementPerformAction(scrollArea, "AXScrollDownByPage" as CFString) == .success
    }
    var settable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(bar, kAXValueAttribute as CFString, &settable)
    guard settable.boolValue else {
        return AXUIElementPerformAction(scrollArea, "AXScrollDownByPage" as CFString) == .success
    }
    let minimum = number(bar, kAXMinValueAttribute as CFString) ?? 0
    let maximum = number(bar, kAXMaxValueAttribute as CFString) ?? 1
    let value = minimum + ((maximum - minimum) * min(max(fraction, 0), 1))
    return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: value)) == .success
}

private func findInReviews(
    _ window: AXUIElement,
    name: String,
    matching predicate: (AXUIElement) -> Bool
) throws -> AXUIElement {
    let scrollArea = try reviewsScrollArea(window)
    _ = setScrollFraction(scrollArea, 0)
    Thread.sleep(forTimeInterval: 0.1)
    for page in 0..<maximumScrollPages {
        let matches = try walk([window], matching: predicate)
        if matches.count == 1, let match = matches.first { return match }
        if matches.count > 1 { throw ProbeError.failure("ambiguous \(name)") }
        _ = setScrollFraction(scrollArea, Double(page + 1) / Double(maximumScrollPages))
        Thread.sleep(forTimeInterval: 0.12)
    }
    throw ProbeError.failure("missing \(name) after bounded Reviews scrolling")
}

private func findIdentifier(_ expected: String, in window: AXUIElement) throws -> AXUIElement {
    try findInReviews(window, name: expected) { identifier($0) == expected }
}

private func identifierExists(_ expected: String, in window: AXUIElement) -> Bool {
    (try? findIdentifier(expected, in: window)) != nil
}

private func requireContains(_ expected: String, element: AXUIElement, name: String) throws {
    guard labels(element).contains(where: { $0.localizedCaseInsensitiveContains(expected) }) else {
        throw ProbeError.failure("\(name) does not contain '\(expected)': \(labels(element))")
    }
}

private func setText(_ target: AXUIElement, value: String, name: String) throws {
    var settable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &settable)
    guard settable.boolValue,
          AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, value as CFString) == .success
    else { throw ProbeError.failure("\(name) is not writable through Accessibility") }
    Thread.sleep(forTimeInterval: 0.15)
    guard string(target, kAXValueAttribute as CFString) == value else {
        throw ProbeError.failure("\(name) did not retain its requested value")
    }
}

private func pickerHasValue(_ picker: AXUIElement, _ value: String) -> Bool {
    labels(picker).contains { $0.localizedCaseInsensitiveContains(value) }
}

private func selectClassification(_ value: String, picker: AXUIElement) throws {
    if pickerHasValue(picker, value) { return }
    for candidate in [value, value.uppercased(), value.capitalized] {
        if AXUIElementSetAttributeValue(picker, kAXValueAttribute as CFString, candidate as CFString) == .success {
            Thread.sleep(forTimeInterval: 0.2)
            if pickerHasValue(picker, value) { return }
        }
    }
    try press(picker, name: "classification picker")
    for _ in 0..<20 {
        let items = try walk([application], matching: {
            role($0) == (kAXMenuItemRole as String)
                && labels($0).contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
        })
        if items.count == 1, let item = items.first {
            try press(item, name: "\(value) classification")
            if pickerHasValue(picker, value) { return }
        }
        if items.count > 1 { throw ProbeError.failure("classification menu item is ambiguous") }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ProbeError.failure("classification picker did not select \(value)")
}

private func requireImpact(_ expected: String, in window: AXUIElement) throws {
    var impact: AXUIElement?
    for _ in 0..<40 {
        impact = try? findIdentifier(impactID, in: window)
        if impact != nil { break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    let resolved = try impact ?? findIdentifier(impactID, in: window)
    let values = exposedStrings(resolved)
    guard values.contains(expected) else {
        throw ProbeError.failure("correction impact label mismatch: \(values)")
    }
    for forbidden in forbiddenImpactContent where values.contains(where: { $0.contains(forbidden) }) {
        throw ProbeError.failure("private correction content leaked into the impact card")
    }
}

private func requireNoImpact(in window: AXUIElement) throws {
    guard !identifierExists(impactID, in: window) else {
        throw ProbeError.failure("transient correction impact remained visible after reload or no-op")
    }
}

private func requireRawEvidencePrivacy(_ window: AXUIElement) throws {
    let values = try walk([window], matching: { _ in true }).flatMap(exposedStrings)
    for forbidden in forbiddenRawEvidence where values.contains(where: { $0.contains(forbidden) }) {
        throw ProbeError.failure("raw window title or URL leaked through Reviews Accessibility")
    }
}

private func requireApplyEnabled(_ expected: Bool, in window: AXUIElement) throws -> AXUIElement {
    let button = try findIdentifier(applyID, in: window)
    guard bool(button, kAXEnabledAttribute as CFString) == expected else {
        throw ProbeError.failure("Apply correction enabled state did not equal \(expected)")
    }
    return button
}

private func verifyPersisted(
    classification: String,
    task: String,
    hypothesisFragment: String,
    in window: AXUIElement
) throws {
    let total = try findIdentifier("reviews.total.\(classification)", in: window)
    try requireContains("25 MIN", element: total, name: "\(classification) total")
    let taskField = try findIdentifier(taskID, in: window)
    guard string(taskField, kAXValueAttribute as CFString) == task else {
        throw ProbeError.failure("persisted task alignment value mismatch")
    }
    let hypothesis = try findIdentifier("reviews.hypothesis", in: window)
    try requireContains(hypothesisFragment, element: hypothesis, name: "review statement")
    try requireNoImpact(in: window)
    _ = try requireApplyEnabled(false, in: window)
    try requireRawEvidencePrivacy(window)
}

private func applyCorrection(
    classification: String,
    task: String,
    phase: Phase,
    in window: AXUIElement
) throws {
    let picker = try findIdentifier(classificationID, in: window)
    try selectClassification(classification, picker: picker)
    let taskField = try findIdentifier(taskID, in: window)
    try setText(taskField, value: task, name: "task alignment field")
    let apply = try requireApplyEnabled(true, in: window)
    try press(apply, name: "Apply correction")
    guard let expected = expectedImpact(for: phase) else {
        throw ProbeError.failure("phase has no impact expectation")
    }
    try requireImpact(expected, in: window)
    try requireRawEvidencePrivacy(window)
}

do {
    let window = try mainWindow()
    try openReviews(window)
    switch phase {
    case .before:
        try verifyPersisted(
            classification: "gaming",
            task: "",
            hypothesisFragment: "Observed gaming and distracting time exceeded observed work time",
            in: window
        )
    case .applyCombined:
        try applyCorrection(classification: "work", task: privateTask, phase: phase, in: window)
    case .persistedCombined:
        try verifyPersisted(
            classification: "work",
            task: privateTask,
            hypothesisFragment: "Observed work time was the largest covered category",
            in: window
        )
    case .applyRemove:
        try applyCorrection(classification: "work", task: "", phase: phase, in: window)
    case .applyAttach:
        try applyCorrection(classification: "work", task: privateTask, phase: phase, in: window)
    case .applyUnchangedAlignment:
        try applyCorrection(classification: "gaming", task: privateTask, phase: phase, in: window)
    case .persistedFinal:
        try verifyPersisted(
            classification: "gaming",
            task: privateTask,
            hypothesisFragment: "Observed gaming and distracting time exceeded observed work time",
            in: window
        )
    }
    print("PASS: ZC-026-006 \(phase.rawValue) Accessibility acceptance")
} catch ProbeError.failure(let message) {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
