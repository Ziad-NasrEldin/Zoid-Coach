import Testing
@testable import ZoidCoachApp

@Test
func customEstimateAcceptsTrimmedWholeMinutesWithinBounds() {
    #expect(TaskEstimateInput.parse(" 25 ") == .success(25))
    #expect(TaskEstimateInput.parse("1") == .success(1))
    #expect(TaskEstimateInput.parse("480") == .success(480))
}

@Test
func customEstimateRejectsEmptyZeroNegativeMalformedAndExcessiveValues() {
    #expect(TaskEstimateInput.parse("   ") == .failure(.empty))
    #expect(TaskEstimateInput.parse("0") == .failure(.nonPositive))
    #expect(TaskEstimateInput.parse("-15") == .failure(.nonPositive))
    #expect(TaskEstimateInput.parse("1.5") == .failure(.malformed))
    #expect(TaskEstimateInput.parse("tomorrow") == .failure(.malformed))
    #expect(TaskEstimateInput.parse("481") == .failure(.tooLarge(maximum: 480)))
}

@Test
func everyValidationFailureProvidesAnActionableMessage() {
    #expect(TaskEstimateInput.ValidationError.empty.message == "Enter an estimate in minutes.")
    #expect(TaskEstimateInput.ValidationError.malformed.message.contains("whole number"))
    #expect(TaskEstimateInput.ValidationError.nonPositive.message.contains("at least 1 minute"))
    #expect(TaskEstimateInput.ValidationError.tooLarge(maximum: 480).message.contains("Split larger work"))
}
