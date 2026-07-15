import AppKit
import Testing
@testable import ZoidCoachApp

@Suite("Custom estimate editor interaction state")
struct CustomEstimateEditorStateTests {
    @Test(arguments: [
        ("", "Enter an estimate in minutes."),
        ("   ", "Enter an estimate in minutes."),
        ("\u{00A0}\u{2003}", "Enter an estimate in minutes."),
        ("0", "Estimate must be at least 1 minute."),
        ("-15", "Estimate must be at least 1 minute."),
        ("1.5", "Use a whole number of minutes, such as 25."),
        ("tomorrow", "Use a whole number of minutes, such as 25."),
        ("٢٥", "Use a whole number of minutes, such as 25."),
        ("25,0", "Use a whole number of minutes, such as 25."),
        ("481", "Estimate must be 480 minutes or less. Split larger work into smaller tasks."),
    ])
    func invalidReturnRetainsExactCorrectionState(rawInput: String, expectedMessage: String) {
        var state = CustomEstimateEditorState()
        var persistenceCount = 0
        state.open(initialMinutes: nil)
        state.input = rawInput
        let initialFocusRequest = state.focusRequest
        let initialPresentationID = state.presentationID

        let accepted = state.submit { _ in persistenceCount += 1 }

        #expect(!accepted)
        #expect(state.isPresented)
        #expect(state.input == rawInput)
        #expect(state.validationMessage == expectedMessage)
        #expect(state.focusRequest == initialFocusRequest + 1)
        #expect(state.presentationID == initialPresentationID)
        #expect(persistenceCount == 0)
    }

    @Test
    func paddedValidReturnPersistsExactlyOnceAndClosesAcrossRapidResubmit() {
        var state = CustomEstimateEditorState()
        var persisted: [Int] = []
        state.open(initialMinutes: 45)
        state.input = " 25 "

        let firstAccepted = state.submit { persisted.append($0) }
        let secondAccepted = state.submit { persisted.append($0) }

        #expect(firstAccepted)
        #expect(!secondAccepted)
        #expect(persisted == [25])
        #expect(!state.isPresented)
        #expect(state.validationMessage == nil)
    }

    @Test
    func dashboardAndTodayParentSurfaceStatesDoNotResetEachOther() {
        var dashboard = CustomEstimateEditorState()
        var today = CustomEstimateEditorState()
        dashboard.open(initialMinutes: 30)
        today.open(initialMinutes: 60)
        dashboard.input = "0"
        today.input = " 90 "

        _ = dashboard.submit { _ in Issue.record("invalid dashboard value persisted") }

        #expect(dashboard.isPresented)
        #expect(dashboard.input == "0")
        #expect(dashboard.validationMessage != nil)
        #expect(today.isPresented)
        #expect(today.input == " 90 ")
        #expect(today.validationMessage == nil)
    }

    @MainActor
    @Test(arguments: [
        UInt16(36),
        UInt16(76),
    ])
    func physicalReturnSynchronizesExactTextAndRetainsInvalidEditorFocusRequestAndError(
        keyCode: UInt16
    ) {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        let field = CustomEstimateTextView()
        field.string = "\u{00A0}\u{2003}"
        field.onReturn = { exactText in
            box.returnCallbackCount += 1
            box.state.input = exactText
            _ = box.state.submit { box.persisted.append($0) }
        }

        let handled = field.handleReturn(keyEvent(keyCode: keyCode))

        #expect(handled)
        #expect(field.accessibilityRole() == .textField)
        #expect(box.returnCallbackCount == 1)
        #expect(box.state.input == "\u{00A0}\u{2003}")
        #expect(box.state.isPresented)
        #expect(box.state.validationMessage == "Enter an estimate in minutes.")
        #expect(box.state.focusRequest == initialFocusRequest + 1)
        #expect(box.persisted.isEmpty)
    }

    @MainActor
    @Test
    func rapidPhysicalReturnPersistsPaddedValidInputExactlyOnce() {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let field = CustomEstimateTextView()
        field.string = " 25 "
        field.onReturn = { exactText in
            box.returnCallbackCount += 1
            box.state.input = exactText
            _ = box.state.submit { box.persisted.append($0) }
        }

        let returnEvent = keyEvent(keyCode: 36)
        let firstHandled = field.handleReturn(returnEvent)
        let secondHandled = field.handleReturn(returnEvent)

        #expect(firstHandled)
        #expect(secondHandled)
        #expect(box.returnCallbackCount == 2)
        #expect(box.state.input == " 25 ")
        #expect(box.persisted == [25])
        #expect(!box.state.isPresented)
        #expect(box.state.validationMessage == nil)
    }

    @MainActor
    @Test(arguments: [UInt16(48), UInt16(53), UInt16(123)])
    func tabEscapeAndNonReturnKeysPassThroughWithoutSubmitting(keyCode: UInt16) {
        let box = InteractionBox()
        box.state.open(initialMinutes: nil)
        let initialFocusRequest = box.state.focusRequest
        let field = CustomEstimateTextView()
        field.string = "25"
        field.onReturn = { _ in box.returnCallbackCount += 1 }

        let handled = field.handleReturn(keyEvent(keyCode: keyCode))

        #expect(!handled)
        #expect(box.returnCallbackCount == 0)
        #expect(box.state.input.isEmpty)
        #expect(box.state.isPresented)
        #expect(box.state.validationMessage == nil)
        #expect(box.state.focusRequest == initialFocusRequest)
        #expect(box.persisted.isEmpty)
    }

    @Test
    func legacyParserBoundariesRemainExact() {
        #expect(TaskEstimateInput.parse(" 1 ") == .success(1))
        #expect(TaskEstimateInput.parse("480") == .success(480))
        #expect(TaskEstimateInput.parse("0") == .failure(.nonPositive))
        #expect(TaskEstimateInput.parse("481") == .failure(.tooLarge(maximum: 480)))
        #expect(TaskEstimateInput.parse("٢٥") == .failure(.malformed))
        #expect(TaskEstimateInput.parse("25,0") == .failure(.malformed))
    }

    @MainActor
    private final class InteractionBox {
        var state = CustomEstimateEditorState()
        var persisted: [Int] = []
        var returnCallbackCount = 0
    }

    @MainActor
    private func keyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
