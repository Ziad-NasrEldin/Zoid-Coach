import AppKit
import SwiftUI

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
            persist(minutes)
            return true
        case let .failure(error):
            validationMessage = error.message
            focusRequest &+= 1
            return false
        }
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
        field.onReturn = { _ = context.coordinator.submit($0) }
        return field
    }

    func updateNSView(_ field: CustomEstimateTextField, context: Context) {
        context.coordinator.parent = self
        field.onReturn = { _ = context.coordinator.submit($0) }
        if field.stringValue != text {
            field.stringValue = text
        }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        Task { @MainActor [weak field] in
            await Task.yield()
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    static func dismantleNSView(_ field: CustomEstimateTextField, coordinator: Coordinator) {
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
        func submit(_ exactText: String) -> Bool {
            parent.text = exactText
            return parent.submit(exactText)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let movementValue = notification.userInfo?[NSText.movementUserInfoKey] as? Int,
                  movementValue == NSTextMovement.return.rawValue else {
                return
            }
            let accepted = submit(field.stringValue)
            guard !accepted else { return }
            Task { @MainActor [weak field] in
                await Task.yield()
                guard let field else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }
}

final class CustomEstimateTextField: NSTextField {
    var onReturn: ((String) -> Void)?
    var onMonitorRemoved: (() -> Void)?
    private var keyMonitor: Any?
    private(set) var keyMonitorInstallCount = 0
    var hasInstalledKeyMonitor: Bool { keyMonitor != nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeKeyMonitor()
        } else {
            installKeyMonitorIfNeeded()
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
        guard let editor, firstResponder === editor else { return event }
        return handleReturn(event, exactText: editor.string) ? nil : event
    }

    @discardableResult
    func handleReturn(_ event: NSEvent, exactText: String) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        onReturn?(exactText)
        return true
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
