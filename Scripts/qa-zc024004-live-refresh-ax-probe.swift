#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: Error { case failure(String) }
private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let hidden: Bool
    let hasToday: Bool
    let hasSettings: Bool
}
private enum WindowSelection: Equatable { case selected(Int), missing, ambiguous }
private struct TodayScrollAreaTraits {
    let containsToday: Bool
}
private enum TodayScrollAreaSelection: Equatable { case selected(Int), missing, ambiguous }
private enum TodayTargetsState: Equatable { case visible, offscreen, ambiguous }
private enum TodayScrollDecision: Equatable { case success, scroll, timeout, ambiguous, staleTree }
private enum TodayScrollStep: Equatable { case verticalScrollBar(Double), pageAction }
private struct TodayScrollMachine {
    let maximumSteps: Int
    private(set) var nextGeneration = 0

    mutating func consume(_ state: TodayTargetsState, generation: Int) -> TodayScrollDecision {
        guard generation == nextGeneration else { return .staleTree }
        switch state {
        case .visible:
            return .success
        case .ambiguous:
            return .ambiguous
        case .offscreen:
            guard generation < maximumSteps else { return .timeout }
            nextGeneration += 1
            return .scroll
        }
    }
}
private struct VisibleTodaySnapshot: Codable, Equatable {
    let workMinutes: Int
    let screenwatchState: String
    let screenwatchDetail: String
}
private struct NormalizedScreenwatch: Hashable {
    let state: String
    let detail: String
}
private struct VisibleTodayValues {
    let workMinutes: Int
    let screenwatch: NormalizedScreenwatch
}
private enum TodayTargetInspection {
    case partial(workingMinutes: Int?, screenwatch: NormalizedScreenwatch?)
    case ambiguous
}
private struct TodayCaptureAccumulator {
    private(set) var workingValues = Set<Int>()
    private(set) var screenwatchValues = Set<NormalizedScreenwatch>()

    mutating func consume(
        workingMinutes: Int?,
        screenwatch: NormalizedScreenwatch?
    ) -> TodayTargetsState {
        if let workingMinutes { workingValues.insert(workingMinutes) }
        if let screenwatch { screenwatchValues.insert(screenwatch) }
        if workingValues.count > 1 || screenwatchValues.count > 1 { return .ambiguous }
        return workingValues.count == 1 && screenwatchValues.count == 1 ? .visible : .offscreen
    }
}
private struct TodayCaptureBinding: Equatable {
    let pid: Int32
    let windowToken: CFHashCode
}
private enum TodayCaptureBindingVerdict: Equatable {
    case valid
    case pidChanged
    case windowChanged
}
private func captureBindingVerdict(
    expected: TodayCaptureBinding,
    actual: TodayCaptureBinding
) -> TodayCaptureBindingVerdict {
    if actual.pid != expected.pid { return .pidChanged }
    if actual.windowToken != expected.windowToken { return .windowChanged }
    return .valid
}
private enum SnapshotVerdict: Equatable { case changed, stable, restored, invalid }
private enum NavigationPollDecision: Equatable { case success, retry, timeout }

private func navigationPollDecision(
    isVisible: Bool,
    attempt: Int,
    maximumAttempts: Int
) -> NavigationPollDecision {
    if isVisible { return .success }
    return attempt < maximumAttempts ? .retry : .timeout
}

private func selectTodayScrollArea(_ candidates: [TodayScrollAreaTraits]) -> TodayScrollAreaSelection {
    let matches = candidates.indices.filter { candidates[$0].containsToday }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
}

private func todayScrollStep(
    currentValue: Double,
    maximumSteps: Int,
    verticalScrollBarIsWritable: Bool,
    minimumValue: Double,
    maximumValue: Double
) -> TodayScrollStep {
    guard verticalScrollBarIsWritable,
          maximumSteps > 0,
          maximumValue > minimumValue
    else { return .pageAction }
    let boundedCurrent = min(max(currentValue, minimumValue), maximumValue)
    let increment = (maximumValue - minimumValue) / Double(maximumSteps)
    let nextValue = min(maximumValue, boundedCurrent + increment)
    return nextValue > boundedCurrent ? .verticalScrollBar(nextValue) : .pageAction
}

private func performTodayScrollStep(
    _ step: TodayScrollStep,
    setScrollbar: (Double) -> Bool,
    scrollPage: () -> Bool
) -> Bool {
    switch step {
    case let .verticalScrollBar(value): return setScrollbar(value)
    case .pageAction: return scrollPage()
    }
}

private let mainWindowID = "zoid-666.main-window"
private let privateSentinels = ["qa-zc024004", "private-url", "private-live", "private-settings", "private-background", "private-relaunch"]
private let repositoryRoot = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func isExternalEvidenceRoot(_ root: URL, repository: URL) -> Bool {
    root.path != repository.path && !root.path.hasPrefix(repository.path + "/")
}

private func selectMainWindow(_ windows: [WindowTraits]) -> WindowSelection {
    let matches = windows.indices.filter {
        let item = windows[$0]
        return !item.minimized && !item.hidden
            && (item.identifier == mainWindowID || (item.hasToday && item.hasSettings))
    }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
}

private func verdict(
    previous: VisibleTodaySnapshot,
    current: VisibleTodaySnapshot,
    requireSourceChange: Bool
) -> SnapshotVerdict {
    if current.workMinutes < previous.workMinutes { return .restored }
    let workChanged = current.workMinutes > previous.workMinutes
    let sourceChanged = current.screenwatchState != previous.screenwatchState
        || current.screenwatchDetail != previous.screenwatchDetail
    if workChanged && (!requireSourceChange || sourceChanged) { return .changed }
    if current == previous { return .stable }
    return .invalid
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let main = WindowTraits(identifier: mainWindowID, minimized: false, hidden: false, hasToday: true, hasSettings: true)
    let fallback = WindowTraits(identifier: nil, minimized: false, hidden: false, hasToday: true, hasSettings: true)
    let auxiliary = WindowTraits(identifier: "agent", minimized: false, hidden: false, hasToday: false, hasSettings: false)
    let minimized = WindowTraits(identifier: mainWindowID, minimized: true, hidden: false, hasToday: true, hasSettings: true)
    let baseline = VisibleTodaySnapshot(workMinutes: 2, screenwatchState: "LIMITED", screenwatchDetail: "Limited coverage")
    let live = VisibleTodaySnapshot(workMinutes: 7, screenwatchState: "CURRENT", screenwatchDetail: "Current coverage")
    let totalsOnly = VisibleTodaySnapshot(workMinutes: 12, screenwatchState: "CURRENT", screenwatchDetail: "Current coverage")
    let currentScreenwatch = NormalizedScreenwatch(state: "CURRENT", detail: "Current coverage")
    var separatedRows = TodayCaptureAccumulator()
    var crossGenerationAmbiguity = TodayCaptureAccumulator()
    let expectedBinding = TodayCaptureBinding(pid: 42, windowToken: 700)
    var offscreenSuccess = TodayScrollMachine(maximumSteps: 3)
    var timeout = TodayScrollMachine(maximumSteps: 1)
    var ambiguous = TodayScrollMachine(maximumSteps: 3)
    var staleTree = TodayScrollMachine(maximumSteps: 3)
    var scrollbarWrites: [Double] = []
    let scrollbarStep = performTodayScrollStep(
        todayScrollStep(
            currentValue: 0.25,
            maximumSteps: 4,
            verticalScrollBarIsWritable: true,
            minimumValue: 0,
            maximumValue: 1
        ),
        setScrollbar: { scrollbarWrites.append($0); return true },
        scrollPage: { false }
    )
    guard selectMainWindow([main, auxiliary]) == .selected(0),
          selectMainWindow([auxiliary, fallback]) == .selected(1),
          selectMainWindow([main, fallback]) == .ambiguous,
          selectMainWindow([auxiliary]) == .missing,
          selectMainWindow([minimized]) == .missing,
          verdict(previous: baseline, current: live, requireSourceChange: true) == .changed,
          verdict(previous: live, current: live, requireSourceChange: false) == .stable,
          verdict(previous: live, current: totalsOnly, requireSourceChange: false) == .changed,
          verdict(previous: live, current: totalsOnly, requireSourceChange: true) == .invalid,
          verdict(previous: live, current: baseline, requireSourceChange: false) == .restored,
          selectTodayScrollArea([.init(containsToday: false), .init(containsToday: true)]) == .selected(1),
          selectTodayScrollArea([.init(containsToday: true), .init(containsToday: true)]) == .ambiguous,
          selectTodayScrollArea([.init(containsToday: false)]) == .missing,
          offscreenSuccess.consume(.offscreen, generation: 0) == .scroll,
          offscreenSuccess.consume(.offscreen, generation: 1) == .scroll,
          offscreenSuccess.consume(.visible, generation: 2) == .success,
          timeout.consume(.offscreen, generation: 0) == .scroll,
          timeout.consume(.offscreen, generation: 1) == .timeout,
          ambiguous.consume(.ambiguous, generation: 0) == .ambiguous,
          staleTree.consume(.offscreen, generation: 0) == .scroll,
          staleTree.consume(.visible, generation: 0) == .staleTree,
          separatedRows.consume(workingMinutes: 2, screenwatch: nil) == .offscreen,
          separatedRows.consume(workingMinutes: nil, screenwatch: currentScreenwatch) == .visible,
          crossGenerationAmbiguity.consume(workingMinutes: 2, screenwatch: nil) == .offscreen,
          crossGenerationAmbiguity.consume(workingMinutes: 3, screenwatch: nil) == .ambiguous,
          captureBindingVerdict(expected: expectedBinding, actual: expectedBinding) == .valid,
          captureBindingVerdict(
              expected: expectedBinding,
              actual: TodayCaptureBinding(pid: 43, windowToken: 700)
          ) == .pidChanged,
          captureBindingVerdict(
              expected: expectedBinding,
              actual: TodayCaptureBinding(pid: 42, windowToken: 701)
          ) == .windowChanged,
          workingMinutes(from: "Working time, 2 minutes") == 2,
          workingMinutes(from: "Working time, 1 minute") == 1,
          workingMinutes(from: "Working 2m") == nil,
          workingMinutes(from: "Working time, 2 hours") == nil,
          normalizedScreenwatch(from: "Limited coverage: Screenwatch is stale.")
              == NormalizedScreenwatch(state: "LIMITED", detail: "Limited coverage: Screenwatch is stale."),
          normalizedScreenwatch(from: "Limited coverage: Screenwatch has no observations today.")
              == NormalizedScreenwatch(state: "LIMITED", detail: "Limited coverage: Screenwatch has no observations today."),
          normalizedScreenwatch(from: "Screenwatch coverage is current.")
              == NormalizedScreenwatch(state: "CURRENT", detail: "Screenwatch coverage is current."),
          normalizedScreenwatch(from: "Screenwatch is probably current") == nil,
          navigationPollDecision(isVisible: true, attempt: 0, maximumAttempts: 40) == .success,
          navigationPollDecision(isVisible: false, attempt: 0, maximumAttempts: 40) == .retry,
          navigationPollDecision(isVisible: false, attempt: 40, maximumAttempts: 40) == .timeout,
          scrollbarStep,
          scrollbarWrites == [0.5],
          isExternalEvidenceRoot(URL(fileURLWithPath: "/private/tmp/evidence"), repository: URL(fileURLWithPath: "/repo")),
          !isExternalEvidenceRoot(URL(fileURLWithPath: "/repo/evidence"), repository: URL(fileURLWithPath: "/repo")),
          privateSentinels.contains(where: { "qa-zc024004-private-live".contains($0) })
    else {
        fputs("FAIL: ZC-024-004 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-024-004 AX probe self-test")
    exit(0)
}

private struct Arguments {
    let pid: Int32
    let command: String
    let evidenceRoot: URL
    let outputName: String?
    let fromName: String?
    let requireSourceChange: Bool
}

private func parseArguments() throws -> Arguments {
    var values = Array(CommandLine.arguments.dropFirst())
    func take(_ name: String) throws -> String {
        guard let index = values.firstIndex(of: name), index + 1 < values.count else {
            throw ProbeError.failure("missing \(name)")
        }
        let value = values[index + 1]
        values.removeSubrange(index...(index + 1))
        return value
    }
    guard let pid = Int32(try take("--pid")) else { throw ProbeError.failure("PID must be numeric") }
    let command = try take("--command")
    let rawRoot = try take("--evidence-root")
    let root = URL(fileURLWithPath: rawRoot).standardizedFileURL
    let output = values.contains("--output") ? try take("--output") : nil
    let from = values.contains("--from") ? try take("--from") : nil
    let requireSource = values.contains("--require-source-change")
    values.removeAll { $0 == "--require-source-change" }
    guard values.isEmpty else { throw ProbeError.failure("unsupported AX probe arguments") }
    guard rawRoot.hasPrefix("/"), isExternalEvidenceRoot(root, repository: repositoryRoot) else {
        throw ProbeError.failure("evidence root must be an absolute path outside the repository")
    }
    guard ["capture", "expect-change", "expect-stable", "expect-restore", "navigate-settings", "navigate-today", "window"].contains(command) else {
        throw ProbeError.failure("unsupported AX probe command")
    }
    for name in [output, from].compactMap({ $0 }) {
        guard !name.isEmpty, !name.contains("/"), name.hasSuffix(".json") else {
            throw ProbeError.failure("evidence names must be simple .json filenames")
        }
    }
    return Arguments(pid: pid, command: command, evidenceRoot: root, outputName: output, fromName: from, requireSourceChange: requireSource)
}

private let args: Arguments
do { args = try parseArguments() } catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr); exit(2)
}
private let application = AXUIElementCreateApplication(args.pid)
private let maximumNodes = 5_000

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}
private func text(_ element: AXUIElement, _ name: CFString) -> String? { attribute(element, name) as? String }
private func identifier(_ element: AXUIElement) -> String? { text(element, kAXIdentifierAttribute as CFString) }
private func role(_ element: AXUIElement) -> String? { text(element, kAXRoleAttribute as CFString) }
private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? { (attribute(element, name) as? NSNumber)?.boolValue }
private func number(_ element: AXUIElement, _ name: CFString) -> Double? { (attribute(element, name) as? NSNumber)?.doubleValue }
private func element(_ element: AXUIElement, _ name: CFString) -> AXUIElement? { attribute(element, name) as! AXUIElement? }
private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { text(element, $0 as CFString) }
}
private func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] }

private func walk(_ root: AXUIElement, matching: (AXUIElement) -> Bool) throws -> AXUIElement? {
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { throw ProbeError.failure("AX traversal exceeded its bounded node limit") }
        if matching(element) { return element }
        queue.append(contentsOf: children(element))
    }
    return nil
}

private func strings(in root: AXUIElement) throws -> [String] {
    var result: [String] = []
    _ = try walk(root) { result.append(contentsOf: labels($0)); return false }
    return result
}

private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    guard kill(args.pid, 0) == 0 else { throw ProbeError.failure("the supplied process is not running") }
    let windows = ((attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? [])
        .filter { role($0) == (kAXWindowRole as String) }
    let traits = try windows.map { window in
        var navigation = Set<String>()
        _ = try walk(window) {
            if role($0) == (kAXButtonRole as String) { navigation.formUnion(labels($0)) }
            return false
        }
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            hidden: bool(window, "AXVisible" as CFString) == false,
            hasToday: navigation.contains("Today"),
            hasSettings: navigation.contains("Settings")
        )
    }
    switch selectMainWindow(traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main Today/Settings window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main Today/Settings windows are ambiguous")
    }
}

private func matchingElements(
    in root: AXUIElement,
    matching predicate: (AXUIElement) -> Bool
) throws -> [AXUIElement] {
    var matches: [AXUIElement] = []
    var queue = [root]
    var visited = Set<CFHashCode>()
    var count = 0
    while !queue.isEmpty {
        let element = queue.removeFirst()
        guard visited.insert(CFHash(element)).inserted else { continue }
        count += 1
        guard count <= maximumNodes else { throw ProbeError.failure("AX traversal exceeded its bounded node limit") }
        if predicate(element) { matches.append(element) }
        queue.append(contentsOf: children(element))
    }
    return matches
}

private func workingMinutes(from value: String) -> Int? {
    guard let workingAccessibilityPattern = try? NSRegularExpression(
        pattern: "^Working time, ([0-9]+) minute(?:s)?$"
    ) else { return nil }
    let range = NSRange(value.startIndex..., in: value)
    guard let match = workingAccessibilityPattern.firstMatch(in: value, range: range),
          let minuteRange = Range(match.range(at: 1), in: value)
    else { return nil }
    return Int(value[minuteRange])
}

private func normalizedScreenwatch(from value: String) -> NormalizedScreenwatch? {
    switch value {
    case "Limited coverage: Screenwatch is stale.",
         "Limited coverage: Screenwatch has no observations today.":
        return NormalizedScreenwatch(state: "LIMITED", detail: value)
    case "Screenwatch coverage is current.":
        return NormalizedScreenwatch(state: "CURRENT", detail: value)
    default:
        return nil
    }
}

private func inspectTodayTargets(in window: AXUIElement) throws -> TodayTargetInspection {
    let allStrings = try strings(in: window)
    guard privateSentinels.allSatisfy({ sentinel in
        allStrings.allSatisfy { !$0.localizedCaseInsensitiveContains(sentinel) }
    }) else { throw ProbeError.failure("private fixture evidence escaped into Accessibility output") }

    let workingLabels = allStrings.filter { $0.hasPrefix("Working time,") }
    guard workingLabels.allSatisfy({ workingMinutes(from: $0) != nil }) else {
        throw ProbeError.failure("visible Today Working accessibility label uses an unsupported unit or format")
    }
    let workingElements = try matchingElements(in: window, matching: { element in
        labels(element).contains(where: { workingMinutes(from: $0) != nil })
    })
    guard workingElements.count <= 1 else { return .ambiguous }
    let workingValues = Set(workingLabels.compactMap(workingMinutes(from:)))
    guard workingValues.count <= 1 else { return .ambiguous }

    let screenwatchTitles = try matchingElements(in: window, matching: {
        labels($0).contains("Screenwatch")
    })
    guard screenwatchTitles.count <= 1 else { return .ambiguous }
    let freshnessCandidates = allStrings.filter {
        $0.localizedCaseInsensitiveContains("Screenwatch")
            && ($0.hasPrefix("Limited coverage:") || $0.hasSuffix("coverage is current."))
    }
    guard freshnessCandidates.allSatisfy({ normalizedScreenwatch(from: $0) != nil }) else {
        throw ProbeError.failure("visible Screenwatch freshness copy conflicts with the supported accessibility contract")
    }
    let screenwatchValues = Set(freshnessCandidates.compactMap(normalizedScreenwatch(from:)))
    guard screenwatchValues.count <= 1 else { return .ambiguous }
    let screenwatch = screenwatchTitles.count == 1 ? screenwatchValues.first : nil
    return .partial(workingMinutes: workingValues.first, screenwatch: screenwatch)
}

private func todayScrollArea(in window: AXUIElement) throws -> AXUIElement {
    let scrollAreas = try matchingElements(in: window, matching: {
        role($0) == (kAXScrollAreaRole as String)
    })
    let traits = try scrollAreas.map { scrollArea in
        TodayScrollAreaTraits(
            containsToday: try walk(scrollArea, matching: {
                identifier($0) == "today.day-state" || labels($0).contains("TODAY / INBOX")
            }) != nil
        )
    }
    switch selectTodayScrollArea(traits) {
    case let .selected(index): return scrollAreas[index]
    case .missing: throw ProbeError.failure("Today content scroll area is unavailable")
    case .ambiguous: throw ProbeError.failure("Today content scroll area is ambiguous")
    }
}

private let maximumTodayScrollSteps = 12
private func resetTodayScroll(_ scrollArea: AXUIElement) -> Bool {
    if let verticalScrollBar = element(scrollArea, kAXVerticalScrollBarAttribute as CFString) {
        var isWritable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(
            verticalScrollBar,
            kAXValueAttribute as CFString,
            &isWritable
        )
        if isWritable.boolValue {
            let minimumValue = number(verticalScrollBar, kAXMinValueAttribute as CFString) ?? 0
            if AXUIElementSetAttributeValue(
                verticalScrollBar,
                kAXValueAttribute as CFString,
                NSNumber(value: minimumValue)
            ) == .success {
                return true
            }
        }
    }
    return AXUIElementPerformAction(scrollArea, "AXScrollToTop" as CFString) == .success
}

private func scrollToday(_ scrollArea: AXUIElement) -> Bool {
    let verticalScrollBar = element(scrollArea, kAXVerticalScrollBarAttribute as CFString)
    var scrollBarIsWritable = DarwinBoolean(false)
    if let verticalScrollBar {
        _ = AXUIElementIsAttributeSettable(
            verticalScrollBar,
            kAXValueAttribute as CFString,
            &scrollBarIsWritable
        )
    }
    let minimumValue = verticalScrollBar.flatMap { number($0, kAXMinValueAttribute as CFString) } ?? 0
    let maximumValue = verticalScrollBar.flatMap { number($0, kAXMaxValueAttribute as CFString) } ?? 1
    let currentValue = verticalScrollBar.flatMap { number($0, kAXValueAttribute as CFString) } ?? minimumValue
    let step = todayScrollStep(
        currentValue: currentValue,
        maximumSteps: maximumTodayScrollSteps,
        verticalScrollBarIsWritable: scrollBarIsWritable.boolValue,
        minimumValue: minimumValue,
        maximumValue: maximumValue
    )
    return performTodayScrollStep(
        step,
        setScrollbar: { value in
            guard let verticalScrollBar else { return false }
            return AXUIElementSetAttributeValue(
                verticalScrollBar,
                kAXValueAttribute as CFString,
                NSNumber(value: value)
            ) == .success
        },
        scrollPage: {
            AXUIElementPerformAction(scrollArea, "AXScrollDownByPage" as CFString) == .success
        }
    )
}

private func visibleTodayValues() throws -> VisibleTodayValues {
    let bindingWindow = try mainWindow()
    let expectedBinding = TodayCaptureBinding(pid: args.pid, windowToken: CFHash(bindingWindow))
    guard resetTodayScroll(try todayScrollArea(in: bindingWindow)) else {
        throw ProbeError.failure("could not reset the visible Today window before bounded scrolling")
    }
    Thread.sleep(forTimeInterval: 0.15)

    var accumulator = TodayCaptureAccumulator()
    var machine = TodayScrollMachine(maximumSteps: maximumTodayScrollSteps)
    for generation in 0...maximumTodayScrollSteps {
        let freshWindow = try mainWindow()
        let actualBinding = TodayCaptureBinding(pid: args.pid, windowToken: CFHash(freshWindow))
        switch captureBindingVerdict(expected: expectedBinding, actual: actualBinding) {
        case .valid:
            break
        case .pidChanged:
            throw ProbeError.failure("installed Today process changed during one capture sequence")
        case .windowChanged:
            throw ProbeError.failure("visible Today main window changed during one capture sequence")
        }

        let state: TodayTargetsState
        switch try inspectTodayTargets(in: freshWindow) {
        case let .partial(workingMinutes, screenwatch):
            let hadWorking = !accumulator.workingValues.isEmpty
            state = accumulator.consume(
                workingMinutes: workingMinutes,
                screenwatch: hadWorking ? screenwatch : nil
            )
        case .ambiguous:
            state = .ambiguous
        }
        switch machine.consume(state, generation: generation) {
        case .success:
            guard let workMinutes = accumulator.workingValues.first,
                  let screenwatch = accumulator.screenwatchValues.first
            else { throw ProbeError.failure("Today target state changed before capture") }
            return VisibleTodayValues(workMinutes: workMinutes, screenwatch: screenwatch)
        case .scroll:
            guard scrollToday(try todayScrollArea(in: freshWindow)) else {
                throw ProbeError.failure("could not scroll the visible Today window toward Working and Screenwatch")
            }
            Thread.sleep(forTimeInterval: 0.15)
        case .timeout:
            let states = accumulator.screenwatchValues.map(\.state).sorted().joined(separator: ",")
            throw ProbeError.failure(
                "Working and Screenwatch are unavailable after bounded Today scrolling; "
                    + "normalized_work_count=\(accumulator.workingValues.count); "
                    + "normalized_screenwatch_count=\(accumulator.screenwatchValues.count); "
                    + "normalized_screenwatch_states=\(states)"
            )
        case .ambiguous:
            throw ProbeError.failure("visible Today Working or Screenwatch values changed or are ambiguous across the capture sequence")
        case .staleTree:
            throw ProbeError.failure("stale Today Accessibility tree was reused during bounded scrolling")
        }
    }
    let states = accumulator.screenwatchValues.map(\.state).sorted().joined(separator: ",")
    throw ProbeError.failure(
        "Working and Screenwatch are unavailable after bounded Today scrolling; "
            + "normalized_work_count=\(accumulator.workingValues.count); "
            + "normalized_screenwatch_count=\(accumulator.screenwatchValues.count); "
            + "normalized_screenwatch_states=\(states)"
    )
}

private func visibleTodaySnapshot() throws -> VisibleTodaySnapshot {
    let values = try visibleTodayValues()
    return VisibleTodaySnapshot(
        workMinutes: values.workMinutes,
        screenwatchState: values.screenwatch.state,
        screenwatchDetail: values.screenwatch.detail
    )
}

private func evidenceURL(_ name: String) -> URL { args.evidenceRoot.appendingPathComponent(name) }
private func writeSnapshot(_ snapshot: VisibleTodaySnapshot, name: String) throws {
    try FileManager.default.createDirectory(at: args.evidenceRoot, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: evidenceURL(name), options: .atomic)
}
private func readSnapshot(_ name: String) throws -> VisibleTodaySnapshot {
    try JSONDecoder().decode(VisibleTodaySnapshot.self, from: Data(contentsOf: evidenceURL(name)))
}

private func destinationVisible(_ destination: String, in window: AXUIElement) throws -> Bool {
    switch destination {
    case "Settings": return try walk(window, matching: { identifier($0) == "settings.policyStatus" }) != nil
    case "Today": return try walk(window, matching: {
        identifier($0) == "today.day-state" || labels($0).contains("TODAY / INBOX")
    }) != nil
    default: return false
    }
}

private func navigate(_ destination: String, in window: AXUIElement) throws {
    guard let button = try walk(window, matching: {
        role($0) == (kAXButtonRole as String) && labels($0).contains(destination)
    }) else { throw ProbeError.failure("normal \(destination) navigation is unavailable") }
    _ = AXUIElementPerformAction(button, "AXScrollToVisible" as CFString)
    let visibleBefore = try destinationVisible(destination, in: window)
    let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
    guard visibleBefore || pressResult == .success else {
        throw ProbeError.failure("normal \(destination) navigation press failed")
    }
    let maximumAttempts = 40
    for attempt in 0...maximumAttempts {
        let visible: Bool
        if visibleBefore {
            visible = true
        } else {
            visible = try destinationVisible(destination, in: mainWindow())
        }
        switch navigationPollDecision(
            isVisible: visible,
            attempt: attempt,
            maximumAttempts: maximumAttempts
        ) {
        case .success:
            return
        case .retry:
            Thread.sleep(forTimeInterval: 0.2)
        case .timeout:
            throw ProbeError.failure("could not navigate to \(destination) before the bounded timeout")
        }
    }
}

do {
    let window = try mainWindow()
    switch args.command {
    case "window": print("PASS: ZC-024-004 exactly one visible main window")
    case "navigate-settings": try navigate("Settings", in: window); print("PASS: ZC-024-004 Settings visible")
    case "navigate-today": try navigate("Today", in: window); print("PASS: ZC-024-004 Today visible")
    case "capture":
        guard let output = args.outputName else { throw ProbeError.failure("capture requires --output") }
        try writeSnapshot(try visibleTodaySnapshot(), name: output)
        print("PASS: ZC-024-004 visible Today snapshot captured")
    case "expect-change", "expect-stable", "expect-restore":
        guard let from = args.fromName else { throw ProbeError.failure("comparison requires --from") }
        let previous = try readSnapshot(from)
        let current = try visibleTodaySnapshot()
        let result = verdict(previous: previous, current: current, requireSourceChange: args.requireSourceChange)
        if args.command == "expect-change" {
            guard result == .changed else { throw ProbeError.failure("visible Today snapshot did not change as required") }
        } else if args.command == "expect-stable" {
            guard result == .stable else { throw ProbeError.failure("visible Today snapshot changed while refresh should be paused") }
        } else {
            guard result == .restored else { throw ProbeError.failure("visible Today snapshot did not restore after fixture cleanup") }
        }
        if let output = args.outputName { try writeSnapshot(current, name: output) }
        let resultLabel = args.command == "expect-change" ? "changed" : args.command == "expect-stable" ? "stayed stable" : "restored"
        print("PASS: ZC-024-004 visible Today snapshot \(resultLabel)")
    default: break
    }
} catch let ProbeError.failure(message) {
    fputs("FAIL: \(message)\n", stderr); exit(1)
} catch {
    fputs("FAIL: unexpected ZC-024-004 AX probe failure: \(error)\n", stderr); exit(1)
}
