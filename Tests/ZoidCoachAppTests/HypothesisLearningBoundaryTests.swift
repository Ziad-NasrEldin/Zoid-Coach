import Testing
import ZoidCoachCore
@testable import ZoidCoachApp

@Test
func pendingAndRejectedHypothesesRemainExplicitlyNotLearned() {
    let candidate = reviewHypothesisCandidate()

    let pending = HypothesisLearningBoundary(candidate: candidate, decision: .pending, isPromoted: false)
    let rejected = HypothesisLearningBoundary(candidate: candidate, decision: .rejected, isPromoted: false)

    #expect(pending.status == .notLearned)
    #expect(pending.statusLabel == "NOT LEARNED")
    #expect(pending.detail.contains("still awaiting your decision"))
    #expect(rejected.status == .notLearned)
    #expect(rejected.statusLabel == "NOT LEARNED")
    #expect(rejected.detail.contains("rejected"))
}

@Test
func learningBoundaryExposesSourceAndEvidenceWithoutLeakingCollapsedEvidence() {
    let candidate = reviewHypothesisCandidate()
    let boundary = HypothesisLearningBoundary(candidate: candidate, decision: .accepted, isPromoted: true)

    #expect(boundary.status == .learned)
    #expect(boundary.sourceLabel == "SOURCE DAY 2026-07-12 · 2 EVIDENCE ITEMS")
    #expect(boundary.accessibilitySummary(showsEvidence: false).contains("SOURCE DAY 2026-07-12"))
    #expect(!boundary.accessibilitySummary(showsEvidence: false).contains("Private project title"))
    #expect(boundary.accessibilitySummary(showsEvidence: true).contains("Private project title"))
    #expect(boundary.accessibilitySummary(showsEvidence: true).contains("42 corrected work minutes"))
}

private func reviewHypothesisCandidate() -> ReviewHypothesisLearningCandidate {
    ReviewHypothesisLearningCandidate(
        id: "review-hypothesis-2026-07-12",
        hypothesis: "Focused work may be easier before noon.",
        sourceDay: "2026-07-12",
        evidence: ["Private project title", "42 corrected work minutes"]
    )
}
