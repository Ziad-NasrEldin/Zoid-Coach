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
                submit: submit
            )
                .id(state.presentationID)
                .frame(width: 78)
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
    let submit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "Minutes"
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
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

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.text = textView.string
            parent.submit()
            return true
        }
    }
}
