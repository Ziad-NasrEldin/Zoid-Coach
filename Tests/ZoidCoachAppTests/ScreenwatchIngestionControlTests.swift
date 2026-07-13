import Testing
@testable import ZoidCoachCore

@Test
func pausedScreenwatchIngestionSkipsTheSourceWithoutDiscardingTheExistingResult() {
    let paused = ScreenwatchIngestionControl(policy: CapturePolicy(ingestionEnabled: false))
    var sourceReads = 0

    let result = paused.run(disabledValue: 17) {
        sourceReads += 1
        return 99
    }

    #expect(!result.performed)
    #expect(result.value == 17)
    #expect(sourceReads == 0)
}

@Test
func resumedScreenwatchIngestionUsesTheSourceImmediately() {
    let resumed = ScreenwatchIngestionControl(policy: CapturePolicy(ingestionEnabled: true))
    var sourceReads = 0

    let result = resumed.run(disabledValue: 17) {
        sourceReads += 1
        return 99
    }

    #expect(result.performed)
    #expect(result.value == 99)
    #expect(sourceReads == 1)
}
