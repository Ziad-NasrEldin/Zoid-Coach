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
    func independentSurfaceStatesDoNotResetEachOther() {
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

    @Test
    func legacyParserBoundariesRemainExact() {
        #expect(TaskEstimateInput.parse(" 1 ") == .success(1))
        #expect(TaskEstimateInput.parse("480") == .success(480))
        #expect(TaskEstimateInput.parse("0") == .failure(.nonPositive))
        #expect(TaskEstimateInput.parse("481") == .failure(.tooLarge(maximum: 480)))
        #expect(TaskEstimateInput.parse("٢٥") == .failure(.malformed))
        #expect(TaskEstimateInput.parse("25,0") == .failure(.malformed))
    }
}
