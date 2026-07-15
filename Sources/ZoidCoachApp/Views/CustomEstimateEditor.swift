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
    let submit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CustomEstimateTextView {
        let field = CustomEstimateTextView()
        field.string = text
        field.delegate = context.coordinator
        field.onReturn = context.coordinator.submit
        return field
    }

    func updateNSView(_ field: CustomEstimateTextView, context: Context) {
        context.coordinator.parent = self
        field.onReturn = context.coordinator.submit
        if field.string != text {
            field.string = text
            field.needsDisplay = true
        }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        Task { @MainActor [weak field] in
            await Task.yield()
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomEstimateInputField
        var lastFocusRequest = -1

        init(parent: CustomEstimateInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextView else { return }
            parent.text = field.string
        }

        func submit(_ exactText: String) {
            parent.text = exactText
            parent.submit()
        }
    }
}

final class CustomEstimateTextView: NSTextView {
    var onReturn: ((String) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 78, height: 22))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override func keyDown(with event: NSEvent) {
        if handleReturn(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult
    func handleReturn(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        onReturn?(string)
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        ("Minutes" as NSString).draw(
            at: NSPoint(x: 5, y: 3),
            withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textField
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textContainerInset = NSSize(width: 4, height: 2)
        textContainer?.maximumNumberOfLines = 1
        textContainer?.lineBreakMode = .byTruncatingTail
        focusRingType = .exterior
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
