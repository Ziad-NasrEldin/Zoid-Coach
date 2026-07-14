import Testing
import ZoidCoachCore
@testable import ZoidCoachApp

@Test
func pendingAndRejectedDecisionsCauseZeroPromotions() throws {
    let sink = RecordingHypothesisPromotionSink()
    let service = ReviewHypothesisLearningService(sink: sink)
    let candidate = serviceCandidate()

    let pending = try service.reconcile(candidate: candidate, decision: .pending)
    let rejected = try service.reconcile(candidate: candidate, decision: .rejected)

    #expect(pending.kind == .notLearned)
    #expect(rejected.kind == .notLearned)
    #expect(sink.promotions.isEmpty)
}

@Test
func explicitAcceptancePromotesExactlyOnceWithSourceAndEvidence() throws {
    let sink = RecordingHypothesisPromotionSink()
    let service = ReviewHypothesisLearningService(sink: sink)
    let candidate = serviceCandidate()

    let first = try service.reconcile(candidate: candidate, decision: .accepted)
    let repeated = try service.reconcile(candidate: candidate, decision: .accepted)

    #expect(first.kind == .promoted)
    #expect(repeated.kind == .alreadyPromoted)
    #expect(sink.promotions == [ReviewHypothesisPromotion(candidate: candidate)])
    #expect(first.boundary.status == .learned)
    #expect(first.boundary.sourceLabel == "SOURCE DAY 2026-07-12 · 2 EVIDENCE ITEMS")
}

@Test
func persistedIdempotencyIsReportedWithoutCreatingAnotherPromotion() throws {
    let sink = RecordingHypothesisPromotionSink(insertsPromotion: false)
    let service = ReviewHypothesisLearningService(sink: sink)
    let candidate = serviceCandidate()

    let first = try service.reconcile(candidate: candidate, decision: .accepted)
    let repeated = try service.reconcile(candidate: candidate, decision: .accepted)

    #expect(first.kind == .alreadyPromoted)
    #expect(repeated.kind == .alreadyPromoted)
    #expect(sink.promotions.count == 1)
}

@Test
func acceptedHypothesisWithoutEvidenceIsNotPromoted() {
    let sink = RecordingHypothesisPromotionSink()
    let service = ReviewHypothesisLearningService(sink: sink)
    let candidate = ReviewHypothesisLearningCandidate(
        id: "review-hypothesis-2026-07-12",
        hypothesis: "Focused work may be easier before noon.",
        sourceDay: "2026-07-12",
        evidence: []
    )

    #expect(throws: ReviewHypothesisLearningError.missingEvidence) {
        try service.reconcile(candidate: candidate, decision: .accepted)
    }
    #expect(sink.promotions.isEmpty)
}

@Test
func reusedPromotionIdentityCannotSilentlyChangeItsEvidence() throws {
    let sink = RecordingHypothesisPromotionSink()
    let service = ReviewHypothesisLearningService(sink: sink)
    let candidate = serviceCandidate()
    _ = try service.reconcile(candidate: candidate, decision: .accepted)
    let conflicting = ReviewHypothesisLearningCandidate(
        id: candidate.id,
        hypothesis: candidate.hypothesis,
        sourceDay: candidate.sourceDay,
        evidence: ["Different evidence"]
    )

    #expect(throws: ReviewHypothesisLearningError.candidateConflict(candidate.id)) {
        try service.reconcile(candidate: conflicting, decision: .accepted)
    }
    #expect(sink.promotions.count == 1)
}

private final class RecordingHypothesisPromotionSink: ReviewHypothesisPromotionSink {
    let insertsPromotion: Bool
    private(set) var promotions: [ReviewHypothesisPromotion] = []
    private var persisted: [String: ReviewHypothesisPromotion] = [:]

    init(insertsPromotion: Bool = true) {
        self.insertsPromotion = insertsPromotion
    }

    func promote(_ promotion: ReviewHypothesisPromotion) throws -> Bool {
        promotions.append(promotion)
        if let existing = persisted[promotion.candidate.id] {
            guard existing == promotion else {
                throw ReviewHypothesisLearningError.candidateConflict(promotion.candidate.id)
            }
            return false
        }
        persisted[promotion.candidate.id] = promotion
        return insertsPromotion
    }

    func existingPromotion(candidateID: String) throws -> ReviewHypothesisPromotion? {
        persisted[candidateID]
    }
}

private func serviceCandidate() -> ReviewHypothesisLearningCandidate {
    ReviewHypothesisLearningCandidate(
        id: "review-hypothesis-2026-07-12",
        hypothesis: "Focused work may be easier before noon.",
        sourceDay: "2026-07-12",
        evidence: ["Monday: 42 corrected work minutes", "Wednesday: 38 corrected work minutes"]
    )
}
