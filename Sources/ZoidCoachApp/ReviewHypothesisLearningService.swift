import Foundation
import ZoidCoachCore

struct ReviewHypothesisPromotion: Equatable, Sendable {
    let candidate: ReviewHypothesisLearningCandidate
}

protocol ReviewHypothesisPromotionSink: AnyObject {
    @discardableResult
    func promote(_ promotion: ReviewHypothesisPromotion) throws -> Bool
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

enum ReviewHypothesisLearningError: Error, Equatable {
    case invalidCandidate
    case missingEvidence
    case candidateConflict(String)
}

final class ReviewHypothesisLearningService: @unchecked Sendable {
    private let sink: ReviewHypothesisPromotionSink
    private let lock = NSLock()
    private var promotedCandidates: [String: ReviewHypothesisLearningCandidate] = [:]

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

        lock.lock()
        defer { lock.unlock() }

        if let existing = promotedCandidates[candidate.id] {
            guard existing == candidate else {
                throw ReviewHypothesisLearningError.candidateConflict(candidate.id)
            }
            return ReviewHypothesisLearningOutcome(
                kind: .alreadyPromoted,
                boundary: learnedBoundary(candidate: candidate)
            )
        }

        let inserted = try sink.promote(ReviewHypothesisPromotion(candidate: candidate))
        promotedCandidates[candidate.id] = candidate
        return ReviewHypothesisLearningOutcome(
            kind: inserted ? .promoted : .alreadyPromoted,
            boundary: learnedBoundary(candidate: candidate)
        )
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
