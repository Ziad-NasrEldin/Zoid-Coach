import AppKit
import SwiftUI

/// A bounded, opt-in trace for signed ZC-011-007 runtime diagnosis.
///
/// The trace is enabled only when the QA bundle exposes a ZC-011-007 runtime
/// root (or an explicitly supplied path in that namespace). Events are kept
/// in memory and flushed from event handlers, never from SwiftUI render or
/// Binding accessors.
final class CustomEstimateEditorTrace: @unchecked Sendable {
    static let shared = CustomEstimateEditorTrace()

    private let lock = NSLock()
    private var events: [String] = []
    private let maxEvents = 256

    private var traceURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        let candidate = environment["ZOID_COACH_QA_EDITOR_TRACE_PATH"]
            ?? environment["ZOID_COACH_QA_RUN_ROOT"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("editor-trace.log").path
            }
        guard let candidate,
              candidate.hasPrefix("/private/tmp/zoid-666-zc011007-") else {
            return nil
        }
        return URL(fileURLWithPath: candidate)
    }

    static func record(_ event: String) {
        shared.recordEvent(event)
    }

    static func flush() {
        shared.flushEvents()
    }

    private func recordEvent(_ event: String) {
        guard traceURL != nil else { return }
        let line = "\(Date.timeIntervalSinceReferenceDate) \(event)\n"
        lock.lock()
        events.append(line)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        lock.unlock()
        flushEvents()
    }

    private func flushEvents() {
        guard let traceURL else { return }
        lock.lock()
        let payload = events.joined()
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(
                    at: traceURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(payload.utf8).write(to: traceURL, options: .atomic)
            } catch {
                // Diagnostics must never affect the editor interaction.
            }
        }
    }
}

struct CustomEstimateEditorState: Equatable {
    private(set) var isPresented = false
    var input = ""
    private(set) var validationMessage: String?
    private(set) var focusRequest = 0
    private(set) var presentationID = UUID()

    mutating func open(initialMinutes: Int?) {
        input = initialMinutes.map(String.init) ?? ""
        validationMessage = nil
        isPresented = true
        focusRequest &+= 1
        presentationID = UUID()
    }

    mutating func cancel() {
        isPresented = false
        validationMessage = nil
    }

    @discardableResult
    mutating func submit(persist: (Int) -> Void) -> Bool {
        guard isPresented else { return false }
        switch TaskEstimateInput.parse(input) {
        case let .success(minutes):
            isPresented = false
            validationMessage = nil
            CustomEstimateEditorTrace.record(
                "state.submit parse=success normalizedMinutes=\(minutes) stateClosed=true"
            )
            persist(minutes)
            CustomEstimateEditorTrace.flush()
            return true
        case let .failure(error):
            validationMessage = error.message
            focusRequest &+= 1
            CustomEstimateEditorTrace.record(
                "state.submit parse=failure message=\(traceValue(error.message)) stateClosed=false"
            )
            return false
        }
    }

    private func traceValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct CustomEstimateEditorStateStore {
    private struct HostOwnership {
        var activePath: String?
    }

    private var states: [String: CustomEstimateEditorState] = [:]
    private var hosts: [String: HostOwnership] = [:]

    subscript(taskID: String) -> CustomEstimateEditorState {
        get { states[taskID] ?? CustomEstimateEditorState() }
        set {
            if newValue.isPresented {
                states[taskID] = newValue
            } else {
                states.removeValue(forKey: taskID)
                hosts.removeValue(forKey: taskID)
            }
        }
    }

    func contains(_ taskID: String) -> Bool {
        states[taskID] != nil
    }

    var hostOwnershipCount: Int {
        hosts.count
    }

    mutating func retain(taskIDs: Set<String>) {
        states = states.filter { taskIDs.contains($0.key) }
        hosts = hosts.filter { taskIDs.contains($0.key) }
    }

    mutating func activateHost(path: String, taskID: String) {
        hosts[taskID, default: HostOwnership()].activePath = path
    }

    func isActiveHost(path: String, taskID: String) -> Bool {
        hosts[taskID]?.activePath == path
    }
}

struct CustomEstimateEditor: View {
    @Binding var state: CustomEstimateEditorState
    let taskTitle: String
    let inputIdentifier: String
    let saveIdentifier: String
    let cancelIdentifier: String
    let errorIdentifier: String
    let errorFontSize: CGFloat
    let persist: (Int) -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            CustomEstimateInputField(
                text: $state.input,
                focusRequest: state.focusRequest,
                presentationID: state.presentationID,
                submit: { exactText in
                    state.input = exactText
                    return state.submit(persist: persist)
                }
            )
                .id(state.presentationID)
                .frame(width: 78, height: 22)
                .accessibilityLabel("Custom estimate for \(taskTitle) in minutes")
                .accessibilityIdentifier(inputIdentifier)
            Button("SAVE", action: submit)
                .buttonStyle(SumiActionButtonStyle(role: .primary, size: .compact))
                .accessibilityIdentifier(saveIdentifier)
            Button("CANCEL") {
                state.cancel()
                cancel()
            }
            .buttonStyle(SumiActionButtonStyle(role: .text, size: .compact))
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(cancelIdentifier)
            if let validationMessage = state.validationMessage {
                Text(validationMessage)
                    .font(Sumi.body(errorFontSize))
                    .foregroundStyle(Sumi.sealDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(errorIdentifier)
            }
        }
    }

    private func submit() {
        state.submit(persist: persist)
    }

}

struct CustomEstimateInputField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    var presentationID = UUID()
    let submit: (String) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CustomEstimateTextField {
        let field = CustomEstimateTextField(string: text)
        field.placeholderString = "Minutes"
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.onReturn = { [weak field] exactText in
            _ = context.coordinator.submit(exactText, refocusing: field)
        }
        return field
    }

    func updateNSView(_ field: CustomEstimateTextField, context: Context) {
        context.coordinator.parent = self
        field.onReturn = { [weak field] exactText in
            _ = context.coordinator.submit(exactText, refocusing: field)
        }
        if field.stringValue != text {
            field.stringValue = text
        }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        field.requestFocus(presentationID: presentationID, generation: focusRequest)
    }

    static func dismantleNSView(_ field: CustomEstimateTextField, coordinator: Coordinator) {
        field.cancelFocusLease()
        field.removeKeyMonitor()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomEstimateInputField
        var lastFocusRequest = -1

        init(parent: CustomEstimateInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @discardableResult
        func submit(
            _ exactText: String,
            refocusing field: CustomEstimateTextField? = nil
        ) -> Bool {
            submitCount += 1
            CustomEstimateEditorTrace.record(
                "coordinator.submit count=\(submitCount) value=\(traceValue(exactText))"
            )
            let invalidFocusGeneration = parent.focusRequest &+ 1
            parent.text = exactText
            let accepted = parent.submit(exactText)
            if !accepted {
                field?.requestFocus(
                    presentationID: parent.presentationID,
                    generation: invalidFocusGeneration
                )
            } else {
                field?.cancelFocusLease()
            }
            return accepted
        }

        private(set) var submitCount = 0

        private func traceValue(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? CustomEstimateTextField,
                  let movementValue = notification.userInfo?[NSText.movementUserInfoKey] as? Int,
                  movementValue == NSTextMovement.return.rawValue else {
                return
            }
            field.recordReturnHandling(.endEditingFallback)
            CustomEstimateEditorTrace.record(
                "endEditing movement=return currentEditor=true firstResponder=true value=\(field.stringValue)"
            )
            _ = submit(field.stringValue, refocusing: field)
        }
    }
}

final class CustomEstimateTextField: NSTextField {
    enum ReturnHandling: Equatable {
        case monitor
        case endEditingFallback
    }

    var onReturn: ((String) -> Void)?
    var onMonitorRemoved: (() -> Void)?
    private var keyMonitor: Any?
    private(set) var keyMonitorInstallCount = 0
    private(set) var lastReturnHandling: ReturnHandling?
    private(set) var returnHandlingCount = 0
    private(set) var requestedPresentationID: UUID?
    private(set) var requestedFocusGeneration: Int?
    private(set) var appliedFocusGeneration: Int?
    private(set) var isFocusLeaseActive = false
    private var focusLeaseTask: Task<Void, Never>?
    var hasInstalledKeyMonitor: Bool { keyMonitor != nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitorIfNeeded()
            applyRequestedFocus()
        }
    }

    func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitorInstallCount += 1
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.filteredEvent(
                event,
                editor: self.currentEditor(),
                firstResponder: self.window?.firstResponder
            )
        }
    }

    func filteredEvent(
        _ event: NSEvent,
        editor: NSText?,
        firstResponder: NSResponder?
    ) -> NSEvent? {
        guard let editor else {
            CustomEstimateEditorTrace.record(
                "monitor keyCode=\(event.keyCode) currentEditor=false firstResponder=\(firstResponder != nil) value=<none>"
            )
            return event
        }
        guard firstResponder === editor else {
            CustomEstimateEditorTrace.record(
                "monitor keyCode=\(event.keyCode) currentEditor=true firstResponder=false value=\(editor.string)"
            )
            return event
        }
        return handleReturn(event, exactText: editor.string) ? nil : event
    }

    @discardableResult
    func handleReturn(_ event: NSEvent, exactText: String) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        recordReturnHandling(.monitor)
        CustomEstimateEditorTrace.record(
            "monitor keyCode=\(event.keyCode) currentEditor=true firstResponder=true value=\(exactText)"
        )
        onReturn?(exactText)
        return true
    }

    func recordReturnHandling(_ handling: ReturnHandling) {
        lastReturnHandling = handling
        returnHandlingCount += 1
    }

    func requestFocus(presentationID: UUID, generation: Int) {
        cancelFocusLease()
        requestedPresentationID = presentationID
        requestedFocusGeneration = generation
        isFocusLeaseActive = true
        applyRequestedFocus()
        focusLeaseTask = Task { @MainActor [weak self] in
            await Task.yield()
            for attempt in 0..<4 {
                guard let self,
                      self.isFocusLeaseActive,
                      self.requestedPresentationID == presentationID,
                      self.requestedFocusGeneration == generation else {
                    return
                }
                self.applyRequestedFocus()
                if attempt < 3 {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard let self,
                  self.requestedPresentationID == presentationID,
                  self.requestedFocusGeneration == generation else {
                return
            }
            self.isFocusLeaseActive = false
            self.requestedPresentationID = nil
            self.requestedFocusGeneration = nil
            self.focusLeaseTask = nil
        }
    }

    func cancelFocusLease() {
        focusLeaseTask?.cancel()
        focusLeaseTask = nil
        isFocusLeaseActive = false
        requestedPresentationID = nil
        requestedFocusGeneration = nil
    }

    var hasInputFocus: Bool {
        guard let window, let editor = currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private func applyRequestedFocus() {
        guard let requestedFocusGeneration,
              let window else {
            return
        }
        if !hasInputFocus {
            _ = window.makeFirstResponder(nil)
            _ = window.makeFirstResponder(self)
            selectText(nil)
            if let editor = currentEditor() {
                editor.selectedRange = NSRange(
                    location: (editor.string as NSString).length,
                    length: 0
                )
                _ = window.makeFirstResponder(editor)
            }
        }
        if hasInputFocus {
            appliedFocusGeneration = requestedFocusGeneration
        }
    }

    isolated deinit {
        removeKeyMonitor()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textField
    }

    func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
            onMonitorRemoved?()
        }
    }
}
