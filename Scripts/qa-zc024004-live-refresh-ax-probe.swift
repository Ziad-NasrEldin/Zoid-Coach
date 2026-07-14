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
private struct VisibleTodaySnapshot: Codable, Equatable {
    let workMinutes: Int
    let screenwatchState: String
    let screenwatchDetail: String
}
private enum SnapshotVerdict: Equatable { case changed, stable, restored, invalid }

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
private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { text(element, $0 as CFString) }
}
private func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] }
private func parent(_ element: AXUIElement) -> AXUIElement? { attribute(element, kAXParentAttribute as CFString) as! AXUIElement? }

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

private func ancestorStrings(
    of anchor: AXUIElement,
    label: String,
    satisfying: ([String]) -> Bool
) throws -> [String] {
    var current: AXUIElement? = anchor
    for _ in 0..<5 {
        guard let element = current else { break }
        let snapshot = try strings(in: element)
        if satisfying(snapshot) { return snapshot }
        current = parent(element)
    }
    throw ProbeError.failure("could not resolve the visible \(label) row")
}

private func visibleTodaySnapshot(_ window: AXUIElement) throws -> VisibleTodaySnapshot {
    guard let working = try walk(window, matching: { labels($0).contains("Working") }) else {
        throw ProbeError.failure("visible Today Working metric is unavailable")
    }
    let minutePattern = try NSRegularExpression(pattern: "^([0-9]+)m$")
    let workStrings = try ancestorStrings(of: working, label: "Working") { snapshot in
        snapshot.contains("Working") && snapshot.contains(where: {
            minutePattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
        })
    }
    guard let minuteText = workStrings.first(where: {
        minutePattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
    }), let workMinutes = Int(minuteText.dropLast()) else {
        throw ProbeError.failure("visible Today Working minutes are unavailable")
    }
    guard let screenwatch = try walk(window, matching: { labels($0).contains("Screenwatch") }) else {
        throw ProbeError.failure("visible Screenwatch freshness row is unavailable")
    }
    let sourceStrings = try ancestorStrings(of: screenwatch, label: "Screenwatch") { snapshot in
        snapshot.contains("Screenwatch") && snapshot.contains(where: { ["LIMITED", "CURRENT"].contains($0.uppercased()) })
    }
    guard let state = sourceStrings.first(where: { ["LIMITED", "CURRENT"].contains($0.uppercased()) }) else {
        throw ProbeError.failure("visible Screenwatch freshness state is unavailable")
    }
    let detail = sourceStrings.first(where: {
        $0.localizedCaseInsensitiveContains("Screenwatch") && $0 != "Screenwatch"
    }) ?? sourceStrings.first(where: { $0 != "Screenwatch" && $0.uppercased() != state.uppercased() }) ?? ""
    let allStrings = try strings(in: window)
    guard privateSentinels.allSatisfy({ sentinel in
        allStrings.allSatisfy { !$0.localizedCaseInsensitiveContains(sentinel) }
    }) else { throw ProbeError.failure("private fixture evidence escaped into Accessibility output") }
    return VisibleTodaySnapshot(workMinutes: workMinutes, screenwatchState: state.uppercased(), screenwatchDetail: detail)
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
    case "Today": return try walk(window, matching: { labels($0).contains("BEHAVIOR SUMMARY") }) != nil
    default: return false
    }
}

private func navigate(_ destination: String, in window: AXUIElement) throws {
    guard let button = try walk(window, matching: {
        role($0) == (kAXButtonRole as String) && labels($0).contains(destination)
    }) else { throw ProbeError.failure("normal \(destination) navigation is unavailable") }
    _ = AXUIElementPerformAction(button, "AXScrollToVisible" as CFString)
    let visibleBefore = try destinationVisible(destination, in: window)
    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
    Thread.sleep(forTimeInterval: 0.4)
    let visibleAfter = try destinationVisible(destination, in: window)
    guard visibleBefore || visibleAfter else {
        throw ProbeError.failure("could not navigate to \(destination)")
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
        try writeSnapshot(try visibleTodaySnapshot(window), name: output)
        print("PASS: ZC-024-004 visible Today snapshot captured")
    case "expect-change", "expect-stable", "expect-restore":
        guard let from = args.fromName else { throw ProbeError.failure("comparison requires --from") }
        let previous = try readSnapshot(from)
        let current = try visibleTodaySnapshot(window)
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
