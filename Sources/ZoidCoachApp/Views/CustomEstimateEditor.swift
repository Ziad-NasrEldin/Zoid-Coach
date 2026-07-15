import AppKit
import SwiftUI

enum ZC011007Trace {
    static let path = "/private/tmp/zoid-zc011007-structured-trace.jsonl"
    private static let lock = NSLock()

    static func emit(_ event: String, _ fields: [String: String] = [:]) {
        guard Bundle.main.bundleIdentifier == "qa.ziadnasreldin.ZoidCoach" else { return }
        var payload = fields
        payload["event"] = event
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let newline = "\n".data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: newline)
    }

    static func identity(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return "\(type(of: object))@\(ObjectIdentifier(object))"
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
        ZC011007Trace.emit("state.submit.begin", ["input": input])
        switch TaskEstimateInput.parse(input) {
        case let .success(minutes):
            isPresented = false
            validationMessage = nil
            ZC011007Trace.emit("state.submit.valid.parsed", [
                "input": input,
                "normalizedMinutes": String(minutes),
                "presented": String(isPresented),
            ])
            persist(minutes)
            ZC011007Trace.emit("state.submit.valid.persistReturned", [
                "normalizedMinutes": String(minutes),
                "presented": String(isPresented),
            ])
            return true
        case let .failure(error):
            validationMessage = error.message
            focusRequest &+= 1
            ZC011007Trace.emit("state.submit.invalid", [
                "input": input,
                "validation": error.message,
                "focusGeneration": String(focusRequest),
            ])
            return false
        }
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
        var submitCount = 0

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
            ZC011007Trace.emit("coordinator.submit.begin", field?.traceFields(extra: [
                "submitCount": String(submitCount),
                "input": exactText,
            ]) ?? ["submitCount": String(submitCount), "input": exactText])
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
            ZC011007Trace.emit("coordinator.submit.end", field?.traceFields(extra: [
                "submitCount": String(submitCount),
                "accepted": String(accepted),
            ]) ?? ["submitCount": String(submitCount), "accepted": String(accepted)])
            return accepted
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            let movement = notification.userInfo?[NSText.movementUserInfoKey] as? Int
            let traceField = notification.object as? CustomEstimateTextField
            ZC011007Trace.emit("coordinator.endEditing", traceField?.traceFields(extra: [
                "movement": movement.map(String.init) ?? "nil",
            ]) ?? ["movement": movement.map(String.init) ?? "nil"])
            guard let field = notification.object as? CustomEstimateTextField,
                  let movementValue = movement,
                  movementValue == NSTextMovement.return.rawValue else {
                return
            }
            field.recordReturnHandling(.endEditingFallback)
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
        if event.keyCode == 36 || event.keyCode == 76 {
            ZC011007Trace.emit("monitor.return.received", traceFields(extra: [
                "keyCode": String(event.keyCode),
                "passedEditor": ZC011007Trace.identity(editor),
                "passedFirstResponder": ZC011007Trace.identity(firstResponder),
            ]))
        }
        guard let editor, firstResponder === editor else { return event }
        let consumed = handleReturn(event, exactText: editor.string)
        if event.keyCode == 36 || event.keyCode == 76 {
            ZC011007Trace.emit("monitor.return.result", traceFields(extra: [
                "consumed": String(consumed),
                "input": editor.string,
            ]))
        }
        return consumed ? nil : event
    }

    @discardableResult
    func handleReturn(_ event: NSEvent, exactText: String) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        recordReturnHandling(.monitor)
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

    func traceFields(extra: [String: String] = [:]) -> [String: String] {
        var fields = extra
        fields["field"] = ZC011007Trace.identity(self)
        fields["window"] = ZC011007Trace.identity(window)
        fields["currentEditor"] = ZC011007Trace.identity(currentEditor())
        fields["firstResponder"] = ZC011007Trace.identity(window?.firstResponder)
        fields["stringValue"] = stringValue
        fields["attached"] = String(window != nil)
        fields["hasInputFocus"] = String(hasInputFocus)
        return fields
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
