#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private enum ProbeError: Error { case failure(String) }
private struct WindowTraits {
    let identifier: String?
    let minimized: Bool
    let labels: [String]
}
private enum WindowSelection: Equatable { case selected(Int), missing, ambiguous }
private enum SavePanelAcquisitionDecision: Equatable {
    case reuseExisting
    case acceptObservedAfterPress
    case waitForPanel
    case fail
}

private func savePanelAcquisitionDecision(
    existingPanelObserved: Bool,
    pressSucceeded: Bool,
    panelObservedAfterPress: Bool
) -> SavePanelAcquisitionDecision {
    if existingPanelObserved { return .reuseExisting }
    if panelObservedAfterPress { return .acceptObservedAfterPress }
    if pressSucceeded { return .waitForPanel }
    return .fail
}

private let mainWindowID = "zoid-666.main-window"
private let previewID = "settings.data.export.preview"
private let saveButtonID = "settings.data.export.choose-destination"
private let requiredPreviewFragments = [
    "3 files",
    "README.txt",
    "manifest.json",
    "counts.json",
    "Task and event titles",
    "Conversation text",
    "URLs and file paths",
    "Screenshots",
    "Request payloads",
    "Credentials",
]
private let maximumNodes = 6_000

private func selectMainWindow(_ windows: [WindowTraits]) -> WindowSelection {
    let matches = windows.indices.filter {
        let window = windows[$0]
        return !window.minimized && (
            window.identifier == mainWindowID
                || (window.labels.contains("Today") && window.labels.contains("Settings"))
        )
    }
    if matches.count == 1 { return .selected(matches[0]) }
    return matches.isEmpty ? .missing : .ambiguous
}

private func previewSatisfiesContract(_ labels: [String]) -> Bool {
    requiredPreviewFragments.allSatisfy { fragment in
        labels.contains(where: { $0.localizedCaseInsensitiveContains(fragment) })
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--self-test"] {
    let main = WindowTraits(identifier: mainWindowID, minimized: false, labels: ["Today", "Settings"])
    let fallback = WindowTraits(identifier: nil, minimized: false, labels: ["Today", "Settings"])
    let auxiliary = WindowTraits(identifier: "agent", minimized: false, labels: ["Agent"])
    let minimized = WindowTraits(identifier: mainWindowID, minimized: true, labels: ["Today", "Settings"])
    let completePreview = requiredPreviewFragments.map { "Included contract: \($0)" }
    guard selectMainWindow([main, auxiliary]) == .selected(0),
          selectMainWindow([auxiliary, fallback]) == .selected(1),
          selectMainWindow([main, fallback]) == .ambiguous,
          selectMainWindow([auxiliary]) == .missing,
          selectMainWindow([minimized]) == .missing,
          previewSatisfiesContract(completePreview),
          !previewSatisfiesContract(Array(completePreview.dropLast())),
          savePanelAcquisitionDecision(
              existingPanelObserved: false,
              pressSucceeded: false,
              panelObservedAfterPress: true
          ) == .acceptObservedAfterPress,
          savePanelAcquisitionDecision(
              existingPanelObserved: true,
              pressSucceeded: false,
              panelObservedAfterPress: false
          ) == .reuseExisting,
          savePanelAcquisitionDecision(
              existingPanelObserved: false,
              pressSucceeded: false,
              panelObservedAfterPress: false
          ) == .fail,
          URL(fileURLWithPath: "/tmp/Fresh.zoiddiagnostics").pathExtension == "zoiddiagnostics"
    else {
        fputs("FAIL: ZC-048-010 AX probe self-test\n", stderr)
        exit(1)
    }
    print("PASS: ZC-048-010 AX probe self-test")
    exit(0)
}

guard CommandLine.arguments.count >= 5,
      CommandLine.arguments[1] == "--pid",
      let pid = Int32(CommandLine.arguments[2]),
      CommandLine.arguments[3] == "--phase",
      ["preview", "cancel", "save", "existing", "finder"].contains(CommandLine.arguments[4])
else {
    fputs("usage: qa-zc048010-diagnostic-package-ax-probe.swift --self-test | --pid <pid> --phase <preview|cancel|save|existing|finder> [--destination <path>]\n", stderr)
    exit(2)
}

private let phase = CommandLine.arguments[4]
private var destination: URL?
if let destinationIndex = CommandLine.arguments.firstIndex(of: "--destination"),
   CommandLine.arguments.indices.contains(destinationIndex + 1) {
    destination = URL(fileURLWithPath: CommandLine.arguments[destinationIndex + 1]).standardizedFileURL
}
if ["save", "existing", "finder"].contains(phase) {
    guard let destination, destination.pathExtension == "zoiddiagnostics" else {
        fputs("FAIL: export phases require a .zoiddiagnostics destination\n", stderr)
        exit(2)
    }
    let exists = FileManager.default.fileExists(atPath: destination.path)
    guard (phase == "save" && !exists) || (["existing", "finder"].contains(phase) && exists) else {
        fputs("FAIL: save requires a fresh destination, while existing and Finder require an existing destination\n", stderr)
        exit(2)
    }
}

private let application = AXUIElementCreateApplication(pid)

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}
private func string(_ element: AXUIElement, _ name: CFString) -> String? { attribute(element, name) as? String }
private func identifier(_ element: AXUIElement) -> String? { string(element, kAXIdentifierAttribute as CFString) }
private func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute as CFString) }
private func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { string(element, $0 as CFString) }
}
private func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}
private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? {
    (attribute(element, name) as? NSNumber)?.boolValue
}
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
private func waitFor(
    attempts: Int = 50,
    _ operation: () throws -> AXUIElement?
) throws -> AXUIElement {
    for _ in 0 ..< attempts {
        if let result = try operation() { return result }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ProbeError.failure("timed out waiting for the expected accessible element")
}
private func press(_ element: AXUIElement, name: String) throws {
    _ = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw ProbeError.failure("could not press \(name)")
    }
}
private func mainWindow() throws -> AXUIElement {
    guard AXIsProcessTrusted() else { throw ProbeError.failure("Accessibility permission is required") }
    guard kill(pid, 0) == 0 else { throw ProbeError.failure("the supplied process is not running") }
    let windows = (attribute(application, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? []
    let traits = try windows.map { window in
        var allLabels: [String] = []
        _ = try walk(window) { element in
            allLabels.append(contentsOf: labels(element))
            return false
        }
        return WindowTraits(
            identifier: identifier(window),
            minimized: bool(window, kAXMinimizedAttribute as CFString) == true,
            labels: allLabels
        )
    }
    switch selectMainWindow(traits) {
    case let .selected(index): return windows[index]
    case .missing: throw ProbeError.failure("visible main window is unavailable")
    case .ambiguous: throw ProbeError.failure("multiple visible main windows are ambiguous")
    }
}
private func navigateToRecords(_ window: AXUIElement) throws {
    if try walk(window, matching: { identifier($0) == previewID }) != nil { return }
    let settings = try waitFor {
        try walk(window, matching: {
            role($0) == (kAXButtonRole as String) && labels($0).contains("Settings")
        })
    }
    try press(settings, name: "Settings")
    let records = try waitFor {
        try walk(window, matching: {
            role($0) == (kAXButtonRole as String)
                && labels($0).contains(where: { $0.localizedCaseInsensitiveContains("Local data and audit") })
        })
    }
    try press(records, name: "Records")
}
private func assertPreview(_ window: AXUIElement) throws -> AXUIElement {
    let preview = try waitFor { try walk(window, matching: { identifier($0) == previewID }) }
    guard previewSatisfiesContract(labels(preview)) else {
        throw ProbeError.failure("preview does not expose the complete file and privacy contract")
    }
    let button = try waitFor { try walk(window, matching: { identifier($0) == saveButtonID }) }
    guard labels(button).contains("SAVE REVIEWED DIAGNOSTIC PACKAGE") else {
        throw ProbeError.failure("reviewed-package action has no useful accessible label")
    }
    return button
}
private func sendGoToFolderShortcut() throws {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 5, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 5, keyDown: false) else {
        throw ProbeError.failure("could not create Go to Folder shortcut")
    }
    down.flags = [.maskCommand, .maskShift]
    up.flags = [.maskCommand, .maskShift]
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}
private func setValue(_ value: String, on element: AXUIElement) throws {
    guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success else {
        throw ProbeError.failure("could not set save-panel value")
    }
}
private func currentSavePanel() throws -> AXUIElement? {
    try walk(application, matching: {
        let elementRole = role($0)
        return (elementRole == (kAXSheetRole as String) || elementRole == (kAXWindowRole as String))
            && labels($0).contains(where: { $0.localizedCaseInsensitiveContains("diagnostic package") })
    })
}
private func savePanel(attempts: Int = 50) throws -> AXUIElement {
    try waitFor(attempts: attempts) {
        try currentSavePanel()
    }
}
private func openOrReuseSavePanel(byPressing button: AXUIElement) throws -> AXUIElement {
    if let existing = try currentSavePanel() {
        guard savePanelAcquisitionDecision(
            existingPanelObserved: true,
            pressSucceeded: false,
            panelObservedAfterPress: false
        ) == .reuseExisting else {
            throw ProbeError.failure("could not reuse the open save panel")
        }
        return existing
    }

    _ = AXUIElementPerformAction(button, "AXScrollToVisible" as CFString)
    let actionResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
    do {
        let observed = try savePanel()
        let decision = savePanelAcquisitionDecision(
            existingPanelObserved: false,
            pressSucceeded: actionResult == .success,
            panelObservedAfterPress: true
        )
        guard decision == .acceptObservedAfterPress || decision == .waitForPanel else {
            throw ProbeError.failure("could not open the save panel")
        }
        return observed
    } catch {
        let decision = savePanelAcquisitionDecision(
            existingPanelObserved: false,
            pressSucceeded: actionResult == .success,
            panelObservedAfterPress: false
        )
        if decision == .fail {
            throw ProbeError.failure("could not press Save reviewed diagnostic package and no save panel appeared")
        }
        throw error
    }
}
private func configureSavePanel(_ panel: AXUIElement, destination: URL) throws {
    try sendGoToFolderShortcut()
    let folderField = try waitFor {
        try walk(application, matching: { role($0) == (kAXTextFieldRole as String) })
    }
    try setValue(destination.deletingLastPathComponent().path, on: folderField)
    let go = try waitFor {
        try walk(application, matching: {
            role($0) == (kAXButtonRole as String) && labels($0).contains("Go")
        })
    }
    try press(go, name: "Go")
    Thread.sleep(forTimeInterval: 0.3)
    let nameField = try waitFor {
        try walk(panel, matching: {
            role($0) == (kAXTextFieldRole as String)
                && labels($0).contains(where: { $0.localizedCaseInsensitiveContains("Zoid 666 Support") })
        })
    }
    try setValue(destination.lastPathComponent, on: nameField)
}
private func assertFinderReveal(_ destination: URL) throws {
    let finder = try waitFor(attempts: 80) {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first(where: \.isActive)
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }
    guard try walk(finder, matching: {
        labels($0).contains(where: { $0.contains(destination.lastPathComponent) })
    }) != nil else {
        throw ProbeError.failure("Finder did not reveal the exported package")
    }
}

do {
    if phase == "finder" {
        try assertFinderReveal(destination!)
        print("PASS: ZC-048-010 Finder revealed the diagnostic package")
        exit(0)
    }
    let window = try mainWindow()
    try navigateToRecords(window)
    let button = try assertPreview(window)
    if phase == "preview" {
        print("PASS: ZC-048-010 Settings preview, exclusions, action label, and VoiceOver contract")
        exit(0)
    }
    let panel = try openOrReuseSavePanel(byPressing: button)
    if phase == "cancel" {
        let cancel = try waitFor {
            try walk(panel, matching: {
                role($0) == (kAXButtonRole as String) && labels($0).contains("Cancel")
            })
        }
        try press(cancel, name: "Cancel")
        Thread.sleep(forTimeInterval: 0.3)
        guard (try? savePanel()) == nil else { throw ProbeError.failure("save panel remained after cancellation") }
        print("PASS: ZC-048-010 save cancellation left no package")
        exit(0)
    }
    try configureSavePanel(panel, destination: destination!)
    let save = try waitFor {
        try walk(panel, matching: {
            role($0) == (kAXButtonRole as String)
                && labels($0).contains(where: { $0.localizedCaseInsensitiveContains("save diagnostic package") })
        })
    }
    try press(save, name: "Save diagnostic package")
    if phase == "existing" {
        if let replace = try? waitFor(attempts: 15, {
            try walk(application, matching: {
                role($0) == (kAXButtonRole as String) && labels($0).contains("Replace")
            })
        }) {
            try press(replace, name: "Replace")
        }
        let failure = try waitFor(attempts: 100) {
            try walk(window, matching: {
                identifier($0) == "settings.data.deletion-status"
                    && labels($0).contains(where: { $0.localizedCaseInsensitiveContains("could not complete") })
            })
        }
        guard !labels(failure).isEmpty, FileManager.default.fileExists(atPath: destination!.path) else {
            throw ProbeError.failure("existing destination rejection did not preserve the destination")
        }
        print("PASS: ZC-048-010 existing destination failed safely and remained available for retry")
        exit(0)
    }
    for _ in 0 ..< 100 {
        if FileManager.default.fileExists(atPath: destination!.path) {
            print("PASS: ZC-048-010 signed UI submitted the package export through XPC")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw ProbeError.failure("signed helper did not create the selected package")
} catch ProbeError.failure(let message) {
    fputs("FAIL: ZC-048-010 \(message)\n", stderr)
    exit(1)
} catch {
    fputs("FAIL: ZC-048-010 unexpected AX failure: \(error)\n", stderr)
    exit(1)
}
