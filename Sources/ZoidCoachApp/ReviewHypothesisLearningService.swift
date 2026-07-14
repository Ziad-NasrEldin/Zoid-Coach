import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

struct ReviewHypothesisPromotion: Equatable, Sendable {
    let candidate: ReviewHypothesisLearningCandidate
}

protocol ReviewHypothesisPromotionSink: AnyObject {
    @discardableResult
    func promote(_ promotion: ReviewHypothesisPromotion) throws -> Bool
    func existingPromotion(candidateID: String) throws -> ReviewHypothesisPromotion?
}

extension ReviewHypothesisPromotionStore: ReviewHypothesisPromotionSink {
    func promote(_ promotion: ReviewHypothesisPromotion) throws -> Bool {
        do {
            return try promote(
                candidateID: promotion.candidate.id,
                hypothesis: promotion.candidate.hypothesis,
                sourceDay: promotion.candidate.sourceDay,
                evidence: promotion.candidate.evidence
            )
        } catch let error as ReviewHypothesisPromotionStoreError {
            if case let .candidateConflict(id) = error {
                throw ReviewHypothesisLearningError.candidateConflict(id)
            }
            throw error
        }
    }

    func existingPromotion(candidateID: String) throws -> ReviewHypothesisPromotion? {
        guard let stored = try promotion(candidateID: candidateID) else { return nil }
        return ReviewHypothesisPromotion(candidate: ReviewHypothesisLearningCandidate(
            id: stored.candidateID,
            hypothesis: stored.hypothesis,
            sourceDay: stored.sourceDay,
            evidence: stored.evidence
        ))
    }
}

struct ReviewHypothesisLearningOutcome: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case notLearned
        case promoted
        case alreadyPromoted
    }

    let kind: Kind
    let boundary: HypothesisLearningBoundary
}

enum ReviewHypothesisLearningError: LocalizedError, Equatable {
    case invalidCandidate
    case missingEvidence
    case candidateConflict(String)

    var errorDescription: String? {
        switch self {
        case .invalidCandidate:
            "This review hypothesis is incomplete and cannot be learned."
        case .missingEvidence:
            "This review hypothesis has no supporting evidence and cannot be learned."
        case let .candidateConflict(id):
            "A different learned hypothesis already uses candidate ID \(id)."
        }
    }
}

final class ReviewHypothesisLearningService: @unchecked Sendable {
    private let sink: ReviewHypothesisPromotionSink

    init(sink: ReviewHypothesisPromotionSink) {
        self.sink = sink
    }

    func reconcile(
        candidate: ReviewHypothesisLearningCandidate,
        decision: DailyReviewHypothesisState
    ) throws -> ReviewHypothesisLearningOutcome {
        guard decision == .accepted else {
            return ReviewHypothesisLearningOutcome(
                kind: .notLearned,
                boundary: HypothesisLearningBoundary(
                    candidate: candidate,
                    decision: decision,
                    isPromoted: false
                )
            )
        }

        guard !candidate.id.isEmpty, !candidate.hypothesis.isEmpty, !candidate.sourceDay.isEmpty else {
            throw ReviewHypothesisLearningError.invalidCandidate
        }
        guard !candidate.evidence.isEmpty else {
            throw ReviewHypothesisLearningError.missingEvidence
        }

        if let existing = try sink.existingPromotion(candidateID: candidate.id) {
            guard existing.candidate == candidate else {
                throw ReviewHypothesisLearningError.candidateConflict(candidate.id)
            }
            return ReviewHypothesisLearningOutcome(
                kind: .alreadyPromoted,
                boundary: learnedBoundary(candidate: candidate)
            )
        }

        let inserted = try sink.promote(ReviewHypothesisPromotion(candidate: candidate))
        return ReviewHypothesisLearningOutcome(
            kind: inserted ? .promoted : .alreadyPromoted,
            boundary: learnedBoundary(candidate: candidate)
        )
    }

    func boundary(for candidate: ReviewHypothesisLearningCandidate) throws -> HypothesisLearningBoundary {
        guard let existing = try sink.existingPromotion(candidateID: candidate.id) else {
            return HypothesisLearningBoundary(
                candidate: candidate,
                decision: .pending,
                isPromoted: false
            )
        }
        guard existing.candidate == candidate else {
            throw ReviewHypothesisLearningError.candidateConflict(candidate.id)
        }
        return learnedBoundary(candidate: candidate)
    }

    private func learnedBoundary(
        candidate: ReviewHypothesisLearningCandidate
    ) -> HypothesisLearningBoundary {
        HypothesisLearningBoundary(
            candidate: candidate,
            decision: .accepted,
            isPromoted: true
        )
    }
}
