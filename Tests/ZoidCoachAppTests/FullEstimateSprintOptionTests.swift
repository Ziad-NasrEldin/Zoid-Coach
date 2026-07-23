import Testing
@testable import ZoidCoachApp

@Suite("Full-estimate sprint option")
struct FullEstimateSprintOptionTests {
    @Test("offers the exact known task estimate as a bounded commitment")
    func exactKnownEstimateIsOffered() throws {
        let option = try #require(FullEstimateSprintOption(estimateMinutes: 45, isUncertain: false))

        #expect(option.durationMinutes == 45)
        #expect(option.menuTitle == "Full task estimate - 45 minutes")
        #expect(option.accessibilityLabel == "Start a 45-minute sprint matching the full task estimate")
    }

    @Test("does not present a false exact boundary for unknown or unsupported estimates", arguments: [
        (nil, false),
        (45, true),
        (0, false),
        (241, false),
    ])
    func unavailableEstimateIsNotOffered(estimateMinutes: Int?, isUncertain: Bool) {
        #expect(FullEstimateSprintOption(
            estimateMinutes: estimateMinutes,
            isUncertain: isUncertain
        ) == nil)
    }
}
