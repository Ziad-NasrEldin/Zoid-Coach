import Testing
@testable import ZoidCoachApp

@Test
func rulesOnlyReviewExplainsLocalFactsCorrectionAndNoGuessing() {
    let state = RulesOnlyReviewState(isRulesOnly: true, sessionCount: 2, hasLimitedCoverage: true)
    #expect(state.title == "LOCAL FACTS / NO AI REQUIRED")
    #expect(state.detail.contains("2 factual sessions"))
    #expect(state.detail.contains("correct, reject, and confirm"))
    #expect(state.detail.contains("without configuring a model"))
    #expect(state.detail.contains("labeled instead of filled with an AI guess"))
}

@Test
func rulesOnlyReviewUsesSingularAndSufficientCoverageCopy() {
    let state = RulesOnlyReviewState(isRulesOnly: true, sessionCount: 1, hasLimitedCoverage: false)
    #expect(state.detail.contains("1 factual session"))
    #expect(state.detail.contains("Coverage is sufficient"))
}

@Test
func configuredIntelligenceNeverChangesTheLocalFactBoundary() {
    let state = RulesOnlyReviewState(isRulesOnly: false, sessionCount: 3, hasLimitedCoverage: false)
    #expect(state.detail.contains("Observed facts and corrections remain local either way"))
}
